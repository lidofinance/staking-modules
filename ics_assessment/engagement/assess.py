from dataclasses import dataclass, field

from ics_assessment.config import (
    ENGAGEMENT_MAX_SCORE,
    ENGAGEMENT_MIN_SCORE,
    ENGAGEMENT_SCORES,
    REQUIRED_ARAGON_VOTES,
    REQUIRED_SNAPSHOT_VOTES,
)
from ics_assessment.result_models import CategoryResult, CheckOutcome
from ics_assessment.data_utils import truncate
from ics_assessment.engagement.sources import (
    EngagementSources,
    aragon_votes_for_addresses,
    galxe_points_by_address,
    gitpoap_matches,
    protocol_guild_matches,
    snapshot_votes_for_addresses,
)
from ics_assessment.runtime_inputs import EngagementRuntimeInputs


@dataclass
class EngagementEvaluator:
    sources: EngagementSources
    runtime_inputs: EngagementRuntimeInputs = field(default_factory=EngagementRuntimeInputs)

    def snapshot_vote(self, addresses: set[str]) -> CheckOutcome:
        total_votes_count, matched_addresses = snapshot_votes_for_addresses(addresses, self.sources)
        if total_votes_count >= REQUIRED_SNAPSHOT_VOTES:
            return CheckOutcome(
                score=ENGAGEMENT_SCORES["snapshot-vote"],
                detail=f"votes: {total_votes_count}; {truncate(matched_addresses)}",
            )
        return CheckOutcome(score=0)

    def aragon_vote(self, addresses: set[str]) -> CheckOutcome:
        total_votes_count, matched_addresses = aragon_votes_for_addresses(addresses, self.sources)
        if total_votes_count >= REQUIRED_ARAGON_VOTES:
            return CheckOutcome(
                score=ENGAGEMENT_SCORES["aragon-vote"],
                detail=f"votes: {total_votes_count}; {truncate(matched_addresses)}",
            )
        return CheckOutcome(score=0)

    def galxe_scores(self, addresses: set[str]) -> CheckOutcome:
        addr_to_points = galxe_points_by_address(self.sources)

        score = 0
        detail = None
        for address in addresses:
            point = addr_to_points.get(address, 0)
            if point > 10:
                score = ENGAGEMENT_SCORES["galxe-score-above-10"]
                return CheckOutcome(score=score, detail=f"{address}={point}")
            if 4 <= point <= 10:
                score = ENGAGEMENT_SCORES["galxe-score-4-10"]
                detail = f"{address}={point}"
        return CheckOutcome(score=score, detail=detail)

    def gitpoap(self, addresses: set[str]) -> CheckOutcome:
        matched_events = gitpoap_matches(addresses, self.sources)
        if matched_events:
            return CheckOutcome(score=ENGAGEMENT_SCORES["git-poap"], detail=truncate(matched_events))
        return CheckOutcome(score=0)

    def high_signal(self) -> CheckOutcome:
        """
        Determine High-signal points from a resolved score.
        """
        high_signal_score = self.runtime_inputs.high_signal_score
        if high_signal_score is None:
            return CheckOutcome(score=0)
        if high_signal_score < 0 or high_signal_score > 100:
            return CheckOutcome(score=0)
        if 30 <= high_signal_score <= 40:
            hs_points = ENGAGEMENT_SCORES["high-signal-30"]
        elif 40 < high_signal_score <= 60:
            hs_points = ENGAGEMENT_SCORES["high-signal-40"]
        elif 60 < high_signal_score <= 80:
            hs_points = ENGAGEMENT_SCORES["high-signal-60"]
        elif high_signal_score > 80:
            hs_points = ENGAGEMENT_SCORES["high-signal-80"]
        else:
            return CheckOutcome(score=0)
        detail = f"score={high_signal_score}"
        if self.runtime_inputs.high_signal_project:
            detail += f"; project={self.runtime_inputs.high_signal_project}"
        if self.runtime_inputs.high_signal_username:
            detail += f"; username={self.runtime_inputs.high_signal_username}"
        if self.runtime_inputs.high_signal_address:
            detail += f"; address={self.runtime_inputs.high_signal_address}"
        return CheckOutcome(score=hs_points, detail=detail)

    def protocol_guild(self, addresses: set[str]) -> CheckOutcome:
        matched_addresses = protocol_guild_matches(addresses, self.sources)
        if matched_addresses:
            return CheckOutcome(score=0, detail=truncate(matched_addresses), matched=True)
        return CheckOutcome(score=0)

    def evaluate(self, addresses: set[str]) -> CategoryResult:
        snapshot = self.snapshot_vote(addresses)
        aragon = self.aragon_vote(addresses)
        galxe = self.galxe_scores(addresses)
        gitpoap_result = self.gitpoap(addresses)
        hs = self.high_signal()
        pg = self.protocol_guild(addresses)

        checks = [
            snapshot.to_result("snapshot-vote"),
            aragon.to_result("aragon-vote"),
            galxe.to_result("galxe-score"),
            gitpoap_result.to_result("git-poap"),
            hs.to_result("high-signal"),
            pg.to_result("protocol-guild"),
        ]
        raw_score = sum(check.score for check in checks)
        final_score = 0 if raw_score < ENGAGEMENT_MIN_SCORE else min(raw_score, ENGAGEMENT_MAX_SCORE)
        return CategoryResult(
            name="Engagement",
            min_score=ENGAGEMENT_MIN_SCORE,
            max_score=ENGAGEMENT_MAX_SCORE,
            checks=checks,
            raw_score=raw_score,
            final_score=final_score,
        )
