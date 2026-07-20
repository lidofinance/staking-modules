from dataclasses import dataclass

STAKING_MODULE_LOGS_VERSION = 1


def _validator_performance_with_frame_threshold(
    validator: dict,
    threshold: float,
) -> tuple[bool, int]:
    assigned = validator["perf"]["assigned"]
    return (
        assigned > 0 and validator["perf"]["included"] / assigned >= threshold,
        assigned,
    )


def _validator_performance_with_embedded_threshold(
    validator: dict,
) -> tuple[bool, int]:
    assigned = validator["attestation_duty"]["assigned"]
    has_duties = (
        assigned
        + validator["proposal_duty"]["assigned"]
        + validator["sync_duty"]["assigned"]
        > 0
    )
    return has_duties and validator["performance"] >= validator["threshold"], assigned


@dataclass(frozen=True)
class PerformanceFrame:
    start_epoch: int
    end_epoch: int
    eligible_operator_ids: frozenset[str]
    assigned_epochs_by_operator: dict[str, int]

    @classmethod
    def from_report(cls, report: dict, version: str) -> "PerformanceFrame":
        start_epoch, end_epoch = report["frame"]
        eligible: set[str] = set()
        assigned_epochs_by_operator: dict[str, int] = {}

        for operator_id, operator in report["operators"].items():
            validators = operator["validators"].values()
            if version == "v1":
                performance = [
                    _validator_performance_with_frame_threshold(
                        validator,
                        report["threshold"],
                    )
                    for validator in validators
                ]
            elif version in {"v2", "v3"}:
                performance = [
                    _validator_performance_with_embedded_threshold(validator)
                    for validator in validators
                ]
            else:
                raise ValueError(f"unknown performance report version: {version}")
            assigned_epochs_by_operator[operator_id] = max(
                (assigned for _, assigned in performance),
                default=0,
            )
            if performance and all(meets_threshold for meets_threshold, _ in performance):
                eligible.add(operator_id)

        return cls(
            start_epoch=start_epoch,
            end_epoch=end_epoch,
            eligible_operator_ids=frozenset(eligible),
            assigned_epochs_by_operator=assigned_epochs_by_operator,
        )


def parse_performance_report(payload: object) -> list[PerformanceFrame]:
    if isinstance(payload, list):
        version = "v2"
        reports = payload
    elif isinstance(payload, dict) and "frames" in payload:
        if payload["_ver"] != STAKING_MODULE_LOGS_VERSION:
            raise ValueError(
                f"unsupported staking module logs version: {payload['_ver']}"
            )
        version, reports = "v3", payload["frames"]
    elif isinstance(payload, dict) and "threshold" in payload:
        version = "v1"
        reports = [payload]
    else:
        raise ValueError("unknown performance report version")
    if not reports:
        raise ValueError("performance report has no frames")

    return [PerformanceFrame.from_report(report, version) for report in reports]


def parse_performance_frames(
    payloads: list[dict | list[dict]],
) -> list[PerformanceFrame]:
    frames = [
        frame for payload in payloads for frame in parse_performance_report(payload)
    ]
    frames.sort(key=lambda frame: frame.start_epoch)
    return frames
