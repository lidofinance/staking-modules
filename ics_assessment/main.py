import argparse
import os
import sys
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from ics_assessment.config import (
    ARAGON_VOTERS_PATH,
    CIRCLE_GROUP_MEMBERS_PATH,
    ELIGIBLE_ADDRESSES_HOLESKY_PATH,
    ELIGIBLE_NODE_OPERATORS_HOODI_PATH,
    ELIGIBLE_NODE_OPERATORS_MAINNET_PATH,
    EXPERIENCE_DATA_DIR,
    EXPERIENCE_STATIC_DIR,
    GALXE_LOYALTY_POINTS_PATH,
    GITPOAP_HOLDERS_PATH,
    NODE_OPERATOR_OWNERS_HOODI_PATH,
    NODE_OPERATOR_OWNERS_MAINNET_PATH,
    PROTOCOL_GUILD_PATH,
    SNAPSHOT_VOTERS_PATH,
    SSV_VERIFIED_OPERATORS_PATH,
)
from ics_assessment.engagement.assess import EngagementEvaluator
from ics_assessment.engagement.sources import EngagementSources, fetch_high_signal_max
from ics_assessment.experience.assess import ExperienceEvaluator
from ics_assessment.experience.sources import ExperienceSources
from ics_assessment.humanity.assess import HumanityEvaluator
from ics_assessment.humanity.sources import HumanitySources, fetch_human_passport_max
from ics_assessment.render import render_assessment_result
from ics_assessment.result_models import AssessmentResult
from ics_assessment.runtime_inputs import (
    AssessmentRuntimeInputs,
    EngagementRuntimeInputs,
    HumanityRuntimeInputs,
)
from ics_assessment.sync import main as sync_main


DEFAULT_ENGAGEMENT_SOURCES = EngagementSources(
    aragon_voters_path=ARAGON_VOTERS_PATH,
    snapshot_voters_path=SNAPSHOT_VOTERS_PATH,
    galxe_loyalty_points_path=GALXE_LOYALTY_POINTS_PATH,
    gitpoap_holders_path=GITPOAP_HOLDERS_PATH,
    protocol_guild_path=PROTOCOL_GUILD_PATH,
)

DEFAULT_EXPERIENCE_SOURCES = ExperienceSources(
    data_dir=EXPERIENCE_DATA_DIR,
    static_dir=EXPERIENCE_STATIC_DIR,
    circles_group_members_path=CIRCLE_GROUP_MEMBERS_PATH,
    eligible_addresses_holesky_path=ELIGIBLE_ADDRESSES_HOLESKY_PATH,
    eligible_node_operators_hoodi_path=ELIGIBLE_NODE_OPERATORS_HOODI_PATH,
    eligible_node_operators_mainnet_path=ELIGIBLE_NODE_OPERATORS_MAINNET_PATH,
    node_operator_owners_hoodi_path=NODE_OPERATOR_OWNERS_HOODI_PATH,
    node_operator_owners_mainnet_path=NODE_OPERATOR_OWNERS_MAINNET_PATH,
)

DEFAULT_HUMANITY_SOURCES = HumanitySources(
    circle_group_members_path=CIRCLE_GROUP_MEMBERS_PATH,
    ssv_verified_operators_path=SSV_VERIFIED_OPERATORS_PATH,
)


def evaluate_assessment(
    addresses: set[str],
    *,
    runtime_inputs: AssessmentRuntimeInputs | None = None,
    engagement_sources: EngagementSources = DEFAULT_ENGAGEMENT_SOURCES,
    experience_sources: ExperienceSources = DEFAULT_EXPERIENCE_SOURCES,
    humanity_sources: HumanitySources = DEFAULT_HUMANITY_SOURCES,
) -> AssessmentResult:
    if runtime_inputs is None:
        runtime_inputs = AssessmentRuntimeInputs()

    experience = ExperienceEvaluator(experience_sources).evaluate(addresses)
    humanity = HumanityEvaluator(humanity_sources, runtime_inputs.humanity).evaluate(addresses)
    engagement = EngagementEvaluator(engagement_sources, runtime_inputs.engagement).evaluate(addresses)
    categories = [experience, humanity, engagement]
    total_score = sum(category.final_score for category in categories)
    eligible = all(category.final_score > 0 for category in categories) and total_score >= 15
    return AssessmentResult(
        addresses=sorted(addresses),
        categories=categories,
        total_score=total_score,
        eligible=eligible,
    )


def _parse_optional_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    value = value.strip().lower()
    if value in {"yes", "y", "true", "1"}:
        return True
    if value in {"no", "n", "false", "0"}:
        return False
    raise ValueError(value)


def _require_interactive(option_name: str, env_var: str | None = None) -> None:
    if sys.stdin.isatty():
        return
    parts = [f"provide {option_name}"]
    if env_var:
        parts.append(f"set {env_var}")
    raise SystemExit(f"Cannot prompt in non-interactive mode; {', or '.join(parts)}.")


def _prompt_bool(prompt: str) -> bool:
    while True:
        answer = input(f"{prompt} (yes/no): ").strip().lower()
        if answer in {"yes", "y"}:
            return True
        if answer in {"no", "n"}:
            return False
        print("Invalid input. Please enter 'yes' or 'no'.")


def _prompt_float(prompt: str, option_name: str, env_var: str | None = None) -> float:
    _require_interactive(option_name, env_var=env_var)
    while True:
        answer = input(f"{prompt}: ").strip()
        try:
            return float(answer)
        except ValueError:
            print("Invalid input. Please enter a numeric value.")


def resolve_runtime_inputs(
    addresses: set[str],
    *,
    discord: bool | None = None,
    x: bool | None = None,
    human_passport_score_override: float | None = None,
    lido_high_signal_score: float | None = None,
    ssv_high_signal_score: float | None = None,
    allow_prompt: bool = True,
) -> AssessmentRuntimeInputs:
    humanity = HumanityRuntimeInputs(
        discord=discord,
        x=x,
        human_passport_score=human_passport_score_override,
    )
    engagement = EngagementRuntimeInputs(
        high_signal_score=max(
            score
            for score in (lido_high_signal_score or 0.0, ssv_high_signal_score or 0.0)
        )
        if lido_high_signal_score is not None or ssv_high_signal_score is not None
        else None,
        high_signal_project=(
            "ssv"
            if ssv_high_signal_score is not None
            and (lido_high_signal_score is None or ssv_high_signal_score > lido_high_signal_score)
            else "lido"
            if lido_high_signal_score is not None
            else None
        ),
    )

    if humanity.human_passport_score is None:
        human_passport_api_key = os.getenv("HUMAN_PASSPORT_API_KEY")
        if human_passport_api_key:
            score, address = fetch_human_passport_max(addresses, human_passport_api_key)
            humanity = HumanityRuntimeInputs(
                discord=humanity.discord,
                x=humanity.x,
                human_passport_score=score,
                human_passport_address=address,
            )
        elif allow_prompt:
            humanity = HumanityRuntimeInputs(
                discord=humanity.discord,
                x=humanity.x,
                human_passport_score=_prompt_float(
                    "Human Passport score (0-20)",
                    "--human-passport-score",
                    env_var="HUMAN_PASSPORT_API_KEY",
                ),
            )

    if humanity.discord is None and allow_prompt:
        humanity = HumanityRuntimeInputs(
            discord=_prompt_bool("Discord account provided?"),
            x=humanity.x,
            human_passport_score=humanity.human_passport_score,
            human_passport_address=humanity.human_passport_address,
        )

    if humanity.x is None and allow_prompt:
        humanity = HumanityRuntimeInputs(
            discord=humanity.discord,
            x=_prompt_bool("X account provided?"),
            human_passport_score=humanity.human_passport_score,
            human_passport_address=humanity.human_passport_address,
        )

    if engagement.high_signal_score is None:
        high_signal_api_key = os.getenv("HIGH_SIGNAL_API_KEY")
        if high_signal_api_key:
            score, address, username, project = fetch_high_signal_max(addresses, high_signal_api_key)
            engagement = EngagementRuntimeInputs(
                high_signal_score=score,
                high_signal_address=address,
                high_signal_username=username,
                high_signal_project=project,
            )
        elif allow_prompt:
            lido_score = _prompt_float(
                "Lido High-signal score (0-100)",
                "--lido-high-signal-score",
                env_var="HIGH_SIGNAL_API_KEY",
            )
            ssv_score = _prompt_float(
                "SSV High-signal score (0-100)",
                "--ssv-high-signal-score",
                env_var="HIGH_SIGNAL_API_KEY",
            )
            engagement = EngagementRuntimeInputs(
                high_signal_score=max(lido_score, ssv_score),
                high_signal_project="ssv" if ssv_score > lido_score else "lido",
            )

    return AssessmentRuntimeInputs(humanity=humanity, engagement=engagement)


def _run_assess(
    addresses: list[str],
    *,
    discord: bool | None = None,
    x: bool | None = None,
    human_passport_score_override: float | None = None,
    lido_high_signal_score: float | None = None,
    ssv_high_signal_score: float | None = None,
) -> int:
    normalized_addresses = {address.strip().lower() for address in addresses}
    runtime_inputs = resolve_runtime_inputs(
        normalized_addresses,
        discord=discord,
        x=x,
        human_passport_score_override=human_passport_score_override,
        lido_high_signal_score=lido_high_signal_score,
        ssv_high_signal_score=ssv_high_signal_score,
        allow_prompt=True,
    )
    result = evaluate_assessment(
        normalized_addresses,
        runtime_inputs=runtime_inputs,
    )
    styled = sys.stdout.isatty() and not os.getenv("NO_COLOR")
    print(render_assessment_result(result, styled=styled))
    return 0


def _add_runtime_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--discord", choices=["yes", "no"])
    parser.add_argument("--x", choices=["yes", "no"])
    parser.add_argument("--human-passport-score", type=float)
    parser.add_argument("--lido-high-signal-score", type=float)
    parser.add_argument("--ssv-high-signal-score", type=float)


def main(argv: list[str] | None = None):
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0].startswith("0x"):
        return _run_assess(args)

    parser = argparse.ArgumentParser(description="ICS assessment entrypoint.")
    subparsers = parser.add_subparsers(dest="command")

    assess_parser = subparsers.add_parser("assess", help="Run the full assessment")
    assess_parser.add_argument("addresses", nargs="+")
    _add_runtime_args(assess_parser)

    sync_parser = subparsers.add_parser("sync", help="Sync snapshot-based sources")
    sync_parser.add_argument("--chunk-size", type=int)
    sync_parser.add_argument("targets", nargs="*")

    batch_parser = subparsers.add_parser("batch", help="Run form batch processing")
    batch_parser.add_argument("--full", action="store_true", help="Process all forms, not just the approved ones")

    parsed = parser.parse_args(args)

    if parsed.command == "assess":
        return _run_assess(
            parsed.addresses,
            discord=_parse_optional_bool(parsed.discord),
            x=_parse_optional_bool(parsed.x),
            human_passport_score_override=parsed.human_passport_score,
            lido_high_signal_score=parsed.lido_high_signal_score,
            ssv_high_signal_score=parsed.ssv_high_signal_score,
        )
    if parsed.command == "sync":
        return sync_main(parsed.targets, chunk_size=parsed.chunk_size)
    if parsed.command == "batch":
        from ics_assessment.batch_process_forms import main as batch_main

        batch_main(full=parsed.full)
        return 0

    parser.print_help()
    return 1

if __name__ == "__main__":
    raise SystemExit(main())
