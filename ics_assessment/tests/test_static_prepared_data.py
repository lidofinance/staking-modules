import csv
import json
from pathlib import Path

from ics_assessment.config import (
    ARAGON_VOTERS_PATH,
    CIRCLE_GROUP_MEMBERS_PATH,
    ELIGIBLE_ADDRESSES_HOLESKY_PATH,
    ELIGIBLE_NODE_OPERATORS_HOODI_PATH,
    ELIGIBLE_NODE_OPERATORS_MAINNET_PATH,
    EXPERIENCE_STATIC_DIR,
    ENGAGEMENT_SCORES,
    EXPERIENCE_DATA_DIR,
    EXPERIENCE_SCORES,
    HUMANITY_SCORES,
    NODE_OPERATOR_OWNERS_HOODI_PATH,
    NODE_OPERATOR_OWNERS_MAINNET_PATH,
    PROTOCOL_GUILD_PATH,
    REQUIRED_ARAGON_VOTES,
    SSV_VERIFIED_OPERATORS_PATH,
)
from ics_assessment.engagement.assess import EngagementEvaluator
from ics_assessment.engagement.sources import EngagementSources
from ics_assessment.experience.assess import ExperienceEvaluator
from ics_assessment.experience.sources import ExperienceSources
from ics_assessment.humanity.assess import HumanityEvaluator
from ics_assessment.humanity.sources import HumanitySources


ROOT = Path("ics_assessment")
ENGAGEMENT_SOURCES = EngagementSources(
    aragon_voters_path=ARAGON_VOTERS_PATH,
    snapshot_voters_path=ROOT / "engagement/data/snapshot_voters.csv",
    galxe_loyalty_points_path=ROOT / "engagement/data/galxe_loyalty_points.csv",
    gitpoap_holders_path=ROOT / "engagement/data/gitpoap_holders.csv",
    protocol_guild_path=PROTOCOL_GUILD_PATH,
)
ENGAGEMENT_EVALUATOR = EngagementEvaluator(ENGAGEMENT_SOURCES)
EXPERIENCE_SOURCES = ExperienceSources(
    data_dir=EXPERIENCE_DATA_DIR,
    static_dir=EXPERIENCE_STATIC_DIR,
    circles_group_members_path=CIRCLE_GROUP_MEMBERS_PATH,
    eligible_addresses_holesky_path=ELIGIBLE_ADDRESSES_HOLESKY_PATH,
    eligible_node_operators_hoodi_path=ELIGIBLE_NODE_OPERATORS_HOODI_PATH,
    eligible_node_operators_mainnet_path=ELIGIBLE_NODE_OPERATORS_MAINNET_PATH,
    node_operator_owners_hoodi_path=NODE_OPERATOR_OWNERS_HOODI_PATH,
    node_operator_owners_mainnet_path=NODE_OPERATOR_OWNERS_MAINNET_PATH,
)
EXPERIENCE_EVALUATOR = ExperienceEvaluator(EXPERIENCE_SOURCES)
HUMANITY_SOURCES = HumanitySources(
    circle_group_members_path=CIRCLE_GROUP_MEMBERS_PATH,
    ssv_verified_operators_path=SSV_VERIFIED_OPERATORS_PATH,
)
HUMANITY_EVALUATOR = HumanityEvaluator(HUMANITY_SOURCES)


def _first_csv_row(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8") as file:
        return next(csv.reader(file))


def _first_dict_row_matching(path: Path, predicate) -> dict[str, str]:
    with path.open("r", encoding="utf-8") as file:
        for row in csv.DictReader(file):
            if predicate(row):
                return row
    raise AssertionError(f"No matching row in {path}")


def _first_json_item(path: Path) -> str:
    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)
    if not data:
        raise AssertionError(f"No items in {path}")
    return data[0]


def test_static_aragon_vote_uses_prepared_data():
    row = _first_dict_row_matching(
        ARAGON_VOTERS_PATH,
        lambda row: int(row["VoteCount"]) >= REQUIRED_ARAGON_VOTES,
    )
    address = row["Address"].strip().lower()
    votes = int(row["VoteCount"])

    outcome = ENGAGEMENT_EVALUATOR.aragon_vote({address})

    assert outcome.score == ENGAGEMENT_SCORES["aragon-vote"]
    assert f"{address}={votes}" in (outcome.detail or "")


def test_static_protocol_guild_uses_prepared_data():
    address = _first_csv_row(PROTOCOL_GUILD_PATH)[0].strip().lower()

    outcome = ENGAGEMENT_EVALUATOR.protocol_guild({address})

    assert outcome.matched is True
    assert address in (outcome.detail or "")


def test_static_eth_staker_uses_prepared_data():
    address = _first_csv_row(ROOT / "experience/static/eth-staker-solo-stakers.csv")[0].strip().lower()

    outcome = EXPERIENCE_EVALUATOR.eth_staker_score({address})

    assert outcome.score == EXPERIENCE_SCORES["eth-staker"]
    assert address in (outcome.detail or "")


def test_static_stake_cat_uses_prepared_data():
    address = _first_csv_row(ROOT / "experience/static/stake-cat-solo-B.csv")[0].strip().lower()

    outcome = EXPERIENCE_EVALUATOR.stake_cat_score({address})

    assert outcome.score == EXPERIENCE_SCORES["stake-cat"]
    assert address in (outcome.detail or "")


def test_static_obol_techne_uses_prepared_data():
    address = _first_csv_row(ROOT / "experience/data/obol-techne-credentials-silver.csv")[0].strip().lower()

    outcome = EXPERIENCE_EVALUATOR.obol_techne_score({address})

    assert outcome.score == EXPERIENCE_SCORES["obol-techne-silver"]
    assert address in (outcome.detail or "")


def test_static_ssv_verified_uses_prepared_data():
    address = _first_csv_row(SSV_VERIFIED_OPERATORS_PATH)[0].strip().lower()

    outcome = EXPERIENCE_EVALUATOR.ssv_verified_score({address})

    assert outcome.score == EXPERIENCE_SCORES["ssv-verified"]
    assert address in (outcome.detail or "")


def test_static_ssv_verified_humanity_uses_prepared_data():
    address = _first_csv_row(SSV_VERIFIED_OPERATORS_PATH)[0].strip().lower()

    outcome = HUMANITY_EVALUATOR.ssv_verified_score({address})

    assert outcome.score == HUMANITY_SCORES["ssv-verified"]
    assert address in (outcome.detail or "")


def test_static_sdvtm_uses_prepared_data():
    address = _first_csv_row(ROOT / "experience/static/sdvtm-mainnet.csv")[0].strip().lower()

    outcome = EXPERIENCE_EVALUATOR.sdvtm_score({address})

    assert outcome.score == EXPERIENCE_SCORES["sdvtm-mainnet"]
    assert address in (outcome.detail or "")


def test_static_csm_testnet_uses_prepared_data():
    address = _first_json_item(ELIGIBLE_ADDRESSES_HOLESKY_PATH).strip().lower()

    outcome = EXPERIENCE_EVALUATOR.csm_score({address})

    assert outcome.score in {
        EXPERIENCE_SCORES["csm-testnet"],
        EXPERIENCE_SCORES["csm-testnet-circles-verified"],
    }
    assert address in (outcome.detail or "")


def test_static_csm_mainnet_uses_prepared_data():
    operator_id = _first_json_item(ELIGIBLE_NODE_OPERATORS_MAINNET_PATH).strip()
    with NODE_OPERATOR_OWNERS_MAINNET_PATH.open("r", encoding="utf-8") as file:
        owners = json.load(file)
    address = owners[operator_id].strip().lower()

    outcome = EXPERIENCE_EVALUATOR.csm_score({address})

    assert outcome.score == EXPERIENCE_SCORES["csm-mainnet"]
    assert f"mainnet ids: {operator_id}" in (outcome.detail or "")


def test_static_circles_uses_prepared_data():
    address = _first_csv_row(CIRCLE_GROUP_MEMBERS_PATH)[0].strip().lower()

    outcome = HUMANITY_EVALUATOR.circles_verified_score({address})

    assert outcome.score == HUMANITY_SCORES["circles-verified"]
    assert address in (outcome.detail or "")
