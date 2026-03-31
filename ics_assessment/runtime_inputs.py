from dataclasses import dataclass


@dataclass(frozen=True)
class HumanityRuntimeInputs:
    discord: bool | None = None
    x: bool | None = None
    human_passport_score: float | None = None
    human_passport_address: str | None = None


@dataclass(frozen=True)
class EngagementRuntimeInputs:
    high_signal_score: float | None = None
    high_signal_address: str | None = None


@dataclass(frozen=True)
class AssessmentRuntimeInputs:
    humanity: HumanityRuntimeInputs = HumanityRuntimeInputs()
    engagement: EngagementRuntimeInputs = EngagementRuntimeInputs()
