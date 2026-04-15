from dataclasses import dataclass

from ics_assessment.config import (
    EXPERIENCE_MAX_SCORE,
    EXPERIENCE_MIN_SCORE,
    EXPERIENCE_SCORES,
)
from ics_assessment.result_models import CategoryResult, CheckOutcome
from ics_assessment.data_utils import truncate
from ics_assessment.experience.sources import (
    ExperienceSources,
    circles_matches,
    csv_matches,
    load_holesky_eligible_addresses,
    load_hoodi_eligible_ids,
    load_hoodi_owner_ids,
    load_mainnet_eligible_ids,
    load_hoodi_owner_map,
    load_mainnet_owner_ids,
)


@dataclass
class ExperienceEvaluator:
    sources: ExperienceSources

    def find_addresses_in_csv(self, addresses: set[str], csv_file: str, base_dir=None) -> list[str]:
        return csv_matches(addresses, csv_file, base_dir or self.sources.data_dir)

    def is_addresses_in_csv(self, addresses: set[str], csv_file: str, base_dir=None) -> bool:
        """
        Returns True if any address in `addresses` is found in the first column of the given CSV file.
        The CSV file should contain a single column with addresses or a header with 'Address'.
        """
        return bool(self.find_addresses_in_csv(addresses, csv_file, base_dir=base_dir))

    def _safe_csv_matches(self, addresses: set[str], csv_files: list[str], base_dir=None) -> str | None:
        matches: list[str] = []
        try:
            for csv_file in csv_files:
                matches.extend(self.find_addresses_in_csv(addresses, csv_file, base_dir=base_dir))
        except FileNotFoundError:
            return None
        return truncate(matches) if matches else None

    def _csv_outcome(
        self, addresses: set[str], csv_files: list[str], score: int, base_dir=None
    ) -> CheckOutcome:
        detail = self._safe_csv_matches(addresses, csv_files, base_dir=base_dir)
        if detail:
            return CheckOutcome(score=score, detail=detail)
        return CheckOutcome(score=0)

    def _csm_detail(self, addresses: set[str]) -> str | None:
        details: list[str] = []
        try:
            mainnet_ids = load_mainnet_owner_ids(addresses, self.sources)
            hoodi_ids = load_hoodi_owner_ids(addresses, self.sources)
            if mainnet_ids:
                details.append(f"mainnet ids: {truncate(mainnet_ids)}")
            if hoodi_ids:
                details.append(f"hoodi ids: {truncate(hoodi_ids)}")
            eligible_addresses_holesky = load_holesky_eligible_addresses(self.sources)
            holesky_matches = sorted(addresses & eligible_addresses_holesky)
            if holesky_matches:
                details.append(f"holesky: {truncate(holesky_matches)}")
        except FileNotFoundError:
            return None
        return "; ".join(details) if details else None

    def eth_staker_score(self, addresses: set[str]) -> CheckOutcome:
        """
        Returns the score for EthStaker solo-staker list if any address is present, otherwise 0.
        """
        return self._csv_outcome(
            addresses,
            ["eth-staker-solo-stakers.csv"],
            EXPERIENCE_SCORES["eth-staker"],
            base_dir=self.sources.static_dir,
        )

    def stake_cat_score(self, addresses: set[str]) -> CheckOutcome:
        """
        Returns the score for StakeCat solo-staker list (mainnet, gnosis, rp) if any address is present, otherwise 0.
        """
        return self._csv_outcome(
            addresses,
            [
                "stake-cat-solo-B.csv",
                "stake-cat-gnosischain.csv",
                "stake-cat-rocketpool-solo-stakers.csv",
            ],
            EXPERIENCE_SCORES["stake-cat"],
            base_dir=self.sources.static_dir,
        )

    def obol_techne_score(self, addresses: set[str]) -> CheckOutcome:
        """
        Returns the highest Obol Techne credential score for the given addresses, or 0 if none found.
        """
        silver = self._safe_csv_matches(addresses, ["obol-techne-credentials-silver.csv"])
        if silver:
            return CheckOutcome(score=EXPERIENCE_SCORES["obol-techne-silver"], detail=silver)
        bronze = self._safe_csv_matches(addresses, ["obol-techne-credentials-bronze.csv"])
        if bronze:
            return CheckOutcome(score=EXPERIENCE_SCORES["obol-techne-bronze"], detail=bronze)
        base = self._safe_csv_matches(addresses, ["obol-techne-credentials-base.csv"])
        if base:
            return CheckOutcome(score=EXPERIENCE_SCORES["obol-techne-base"], detail=base)
        return CheckOutcome(score=0)

    def ssv_verified_score(self, addresses: set[str]) -> CheckOutcome:
        """
        Returns the score for SSV Verified Operators if any address is present, otherwise 0.
        """
        return self._csv_outcome(addresses, ["ssv-verified-operators.csv"], EXPERIENCE_SCORES["ssv-verified"])

    def sdvtm_score(self, addresses: set[str]) -> CheckOutcome:
        """
        Returns the score for SDVTM participation if any address is eligible, otherwise 0.
        """
        mainnet = self._safe_csv_matches(
            addresses,
            ["sdvtm-mainnet.csv"],
            base_dir=self.sources.static_dir,
        )
        if mainnet:
            return CheckOutcome(score=EXPERIENCE_SCORES["sdvtm-mainnet"], detail=mainnet)
        testnet = self._safe_csv_matches(
            addresses,
            ["sdvtm-testnet.csv"],
            base_dir=self.sources.static_dir,
        )
        if testnet:
            return CheckOutcome(score=EXPERIENCE_SCORES["sdvtm-testnet"], detail=testnet)
        return CheckOutcome(score=0)

    def csm_score(self, addresses: set[str]) -> CheckOutcome:
        """
        Returns the score for CSM participation if any address is eligible, otherwise 0.
        This function checks both testnet and mainnet CSM participation.
        """
        mainnet_score = self._csm_mainnet_score(addresses)
        if mainnet_score:
            return CheckOutcome(score=mainnet_score, detail=self._csm_detail(addresses))

        testnet_score = self._csm_testnet_score(addresses)
        if testnet_score:
            return CheckOutcome(score=testnet_score, detail=self._csm_detail(addresses))
        return CheckOutcome(score=0)

    def _csm_testnet_score(self, addresses: set[str]) -> int:
        """
        Returns the score for CSM testnet participation using a precomputed file
        produced by _collect_testnet_eligible.py. If any of the addresses belongs to
        an eligible node operator, returns the corresponding testnet score, with an
        extra point for Circles-verified addresses.
        """
        eligible_ids = load_hoodi_eligible_ids(self.sources)
        node_operators = load_hoodi_owner_map(self.sources)
        eligible_addresses_holesky = load_holesky_eligible_addresses(self.sources)
        eligible_holesky = any(a in eligible_addresses_holesky for a in addresses)

        addr_to_id: dict[str, str] = {v.lower(): k for k, v in node_operators.items()}
        found_ids = {addr_to_id[a] for a in addresses if a in addr_to_id}
        if not found_ids and not eligible_holesky:
            return 0

        testnet_eligible = eligible_holesky or any(no_id in eligible_ids for no_id in found_ids)
        if not testnet_eligible:
            return 0
        if circles_matches(addresses, self.sources):
            return EXPERIENCE_SCORES["csm-testnet-circles-verified"]
        return EXPERIENCE_SCORES["csm-testnet"]

    def _csm_mainnet_score(self, addresses: set[str]) -> int:
        """
        Returns the score for CSM mainnet participation if any address is eligible, otherwise 0.
        """
        eligible_ids = load_mainnet_eligible_ids(self.sources)
        found_ids = set(load_mainnet_owner_ids(addresses, self.sources))
        if any(no_id in eligible_ids for no_id in found_ids):
            return EXPERIENCE_SCORES["csm-mainnet"]
        return 0

    def evaluate(self, addresses: set[str]) -> CategoryResult:
        eth_staker = self.eth_staker_score(addresses)
        stake_cat = self.stake_cat_score(addresses)
        obol_techne = self.obol_techne_score(addresses)
        ssv_verified = self.ssv_verified_score(addresses)
        sdvtm = self.sdvtm_score(addresses)
        csm = self.csm_score(addresses)

        checks = [
            eth_staker.to_result("eth-staker"),
            stake_cat.to_result("stake-cat"),
            obol_techne.to_result("obol-techne"),
            ssv_verified.to_result("ssv-verified"),
            sdvtm.to_result("sdvtm-testnet/mainnet"),
            csm.to_result("csm-testnet/mainnet"),
        ]
        raw_score = sum(check.score for check in checks)
        final_score = 0 if raw_score < EXPERIENCE_MIN_SCORE else min(raw_score, EXPERIENCE_MAX_SCORE)
        return CategoryResult(
            name="Experience",
            min_score=EXPERIENCE_MIN_SCORE,
            max_score=EXPERIENCE_MAX_SCORE,
            checks=checks,
            raw_score=raw_score,
            final_score=final_score,
        )
