from dataclasses import dataclass, field

from ics_assessment.config import (
    HUMANITY_MAX_SCORE,
    HUMANITY_MIN_SCORE,
    HUMANITY_SCORES,
)
from ics_assessment.result_models import CategoryResult, CheckOutcome
from ics_assessment.data_utils import truncate
from ics_assessment.humanity.sources import HumanitySources, circles_matches, ssv_verified_matches
from ics_assessment.runtime_inputs import HumanityRuntimeInputs


@dataclass
class HumanityEvaluator:
    sources: HumanitySources
    runtime_inputs: HumanityRuntimeInputs = field(default_factory=HumanityRuntimeInputs)

    def human_passport_score(self) -> CheckOutcome:
        """
        Determine Human Passport score from a resolved score.
        """
        final_score = self.runtime_inputs.human_passport_score
        if final_score is None:
            return CheckOutcome(score=0)
        if final_score and final_score < HUMANITY_SCORES["human-passport-min"]:
            return CheckOutcome(score=0)
        if final_score > HUMANITY_SCORES["human-passport-max"]:
            detail = f"score={final_score}"
            if self.runtime_inputs.human_passport_address:
                detail += f"; address={self.runtime_inputs.human_passport_address}"
            return CheckOutcome(score=HUMANITY_SCORES["human-passport-max"], detail=detail)
        detail = f"score={final_score}" if final_score else None
        if detail and self.runtime_inputs.human_passport_address:
            detail += f"; address={self.runtime_inputs.human_passport_address}"
        return CheckOutcome(score=final_score, detail=detail)

    def circles_verified_score(self, addresses: set[str]) -> CheckOutcome:
        matches = circles_matches(addresses, self.sources)
        if matches:
            return CheckOutcome(score=HUMANITY_SCORES["circles-verified"], detail=truncate(matches))
        return CheckOutcome(score=0)

    def ssv_verified_score(self, addresses: set[str]) -> CheckOutcome:
        """
        Returns the Proof-of-Humanity score for SSV Verified Operators.
        """
        matches = ssv_verified_matches(addresses, self.sources)
        if matches:
            return CheckOutcome(score=HUMANITY_SCORES["ssv-verified"], detail=truncate(matches))
        return CheckOutcome(score=0)

    def discord_account_score(self, provided: bool) -> int:
        """
        Return Discord score from a resolved boolean.
        """
        return HUMANITY_SCORES["discord-account"] if provided else 0

    def x_account_score(self, provided: bool) -> int:
        """
        Return X(Twitter) score from a resolved boolean.
        """
        return HUMANITY_SCORES["x-account"] if provided else 0

    def evaluate(self, addresses: set[str]) -> CategoryResult:
        hp = self.human_passport_score()
        circles = self.circles_verified_score(addresses)
        ssv_verified = self.ssv_verified_score(addresses)
        discord_score = self.discord_account_score(bool(self.runtime_inputs.discord))
        x_score = self.x_account_score(bool(self.runtime_inputs.x))
        checks = [
            hp.to_result("human-passport"),
            circles.to_result("circles-verified"),
            ssv_verified.to_result("ssv-verified"),
            CheckOutcome(score=discord_score, detail="provided" if discord_score else None).to_result("discord-account"),
            CheckOutcome(score=x_score, detail="provided" if x_score else None).to_result("x-account"),
        ]
        raw_score = sum(check.score for check in checks)
        final_score = 0 if raw_score < HUMANITY_MIN_SCORE else min(raw_score, HUMANITY_MAX_SCORE)
        return CategoryResult(
            name="Humanity",
            min_score=HUMANITY_MIN_SCORE,
            max_score=HUMANITY_MAX_SCORE,
            checks=checks,
            raw_score=raw_score,
            final_score=final_score,
        )
