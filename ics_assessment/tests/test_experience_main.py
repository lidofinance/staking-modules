import json
from importlib import util
from pathlib import Path

import pytest


HERE = Path(__file__).resolve()
EXPERIENCE_DIR = HERE.parent.parent / "experience"
MODULE_PATH = EXPERIENCE_DIR / "assess.py"


@pytest.fixture()
def mod(tmp_path):
    spec = util.spec_from_file_location("experience_main", str(MODULE_PATH))
    mod = util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)

    mod.current_dir = Path(tmp_path)
    mod.sources = mod.ExperienceSources(
        data_dir=tmp_path,
        static_dir=tmp_path,
        circles_group_members_path=tmp_path / "circle_group_members.csv",
        eligible_addresses_holesky_path=tmp_path / "eligible_addresses_holesky.json",
        eligible_node_operators_hoodi_path=tmp_path / "eligible_node_operators_hoodi.json",
        eligible_node_operators_mainnet_path=tmp_path / "eligible_node_operators_mainnet.json",
        node_operator_owners_hoodi_path=tmp_path / "node_operator_owners_hoodi.json",
        node_operator_owners_mainnet_path=tmp_path / "node_operator_owners_mainnet.json",
    )
    mod.evaluator = mod.ExperienceEvaluator(mod.sources)
    return mod


def _write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))


def make_perf_data(threshold, validators):
    return {
        "threshold": threshold,
        "operators": {
            "42": {
                "validators": validators,
            }
        },
        "blockstamp": {"block_timestamp": 1_700_000_000, "block_number": 1},
    }


def test_is_addresses_in_csv_true_false(mod):
    (mod.current_dir / "list.csv").write_text("0xabc\n0xdef\n")
    assert mod.evaluator.is_addresses_in_csv({"0xabc"}, "list.csv") is True
    assert mod.evaluator.is_addresses_in_csv({"0x123"}, "list.csv") is False


def test_eth_staker_score(mod):
    (mod.current_dir / "eth-staker-solo-stakers.csv").write_text("0xabc\n")
    assert mod.evaluator.eth_staker_score({"0xabc"}) == mod.CheckOutcome(
        score=mod.EXPERIENCE_SCORES["eth-staker"],
        detail="0xabc",
    )
    assert mod.evaluator.eth_staker_score({"0xdef"}) == mod.CheckOutcome(score=0)


def test_stake_cat_score_either_file(mod):
    (mod.current_dir / "stake-cat-solo-B.csv").write_text("")
    (mod.current_dir / "stake-cat-rocketpool-solo-stakers.csv").write_text("")
    (mod.current_dir / "stake-cat-gnosischain.csv").write_text("0xabc\n")
    assert mod.evaluator.stake_cat_score({"0xabc"}).score == mod.EXPERIENCE_SCORES["stake-cat"]
    (mod.current_dir / "stake-cat-gnosischain.csv").write_text("")
    (mod.current_dir / "stake-cat-solo-B.csv").write_text("0xabc\n")
    assert mod.evaluator.stake_cat_score({"0xabc"}).score == mod.EXPERIENCE_SCORES["stake-cat"]


def test_obol_techne_precedence(mod):
    (mod.current_dir / "obol-techne-credentials-silver.csv").write_text("")
    (mod.current_dir / "obol-techne-credentials-bronze.csv").write_text("")
    (mod.current_dir / "obol-techne-credentials-base.csv").write_text("0xabc\n")
    assert mod.evaluator.obol_techne_score({"0xabc"}).score == mod.EXPERIENCE_SCORES["obol-techne-base"]
    (mod.current_dir / "obol-techne-credentials-bronze.csv").write_text("0xabc\n")
    assert mod.evaluator.obol_techne_score({"0xabc"}).score == mod.EXPERIENCE_SCORES["obol-techne-bronze"]
    (mod.current_dir / "obol-techne-credentials-silver.csv").write_text("0xabc\n")
    assert mod.evaluator.obol_techne_score({"0xabc"}).score == mod.EXPERIENCE_SCORES["obol-techne-silver"]


def test_ssv_verified_score(mod):
    (mod.current_dir / "ssv-verified-operators.csv").write_text("0xdef\n")
    assert mod.evaluator.ssv_verified_score({"0xdef"}) == mod.CheckOutcome(
        score=mod.EXPERIENCE_SCORES["ssv-verified"],
        detail="0xdef",
    )
    assert mod.evaluator.ssv_verified_score({"0xabc"}) == mod.CheckOutcome(score=0)


def test_sdvtm_mainnet_prioritized(mod):
    (mod.current_dir / "sdvtm-mainnet.csv").write_text("0xabc\n")
    (mod.current_dir / "sdvtm-testnet.csv").write_text("0xabc\n")
    assert mod.evaluator.sdvtm_score({"0xabc"}) == mod.CheckOutcome(
        score=mod.EXPERIENCE_SCORES["sdvtm-mainnet"],
        detail="0xabc",
    )


def test_csm_score_prefers_mainnet(mod):
    _write_json(mod.sources.node_operator_owners_hoodi_path, {"42": "0xabc"})
    _write_json(mod.sources.node_operator_owners_mainnet_path, {"42": "0xabc"})
    _write_json(mod.sources.eligible_node_operators_hoodi_path, ["42"])
    _write_json(mod.sources.eligible_node_operators_mainnet_path, ["42"])
    _write_json(mod.sources.eligible_addresses_holesky_path, [])

    outcome = mod.evaluator.csm_score({"0xabc"})
    assert outcome.score == mod.EXPERIENCE_SCORES["csm-mainnet"]
    assert "mainnet ids: 42" in outcome.detail


def test_csm_testnet_reads_eligible_file_and_scores(mod):
    _write_json(mod.sources.node_operator_owners_hoodi_path, {"42": "0xabc"})
    _write_json(mod.sources.eligible_node_operators_hoodi_path, ["42"])
    _write_json(mod.sources.eligible_addresses_holesky_path, [])
    score = mod.evaluator._csm_testnet_score({"0xabc"})
    assert score == mod.EXPERIENCE_SCORES["csm-testnet"]


def test_csm_testnet_reads_eligible_file_with_circles_bonus(mod):
    _write_json(mod.sources.node_operator_owners_hoodi_path, {"42": "0xabc"})
    _write_json(mod.sources.eligible_node_operators_hoodi_path, ["42"])
    _write_json(mod.sources.eligible_addresses_holesky_path, [])
    mod.sources.circles_group_members_path.write_text("0xabc\n")
    score = mod.evaluator._csm_testnet_score({"0xabc"})
    assert score == mod.EXPERIENCE_SCORES["csm-testnet-circles-verified"]


def test_main_aggregator_threshold_and_capping(monkeypatch, mod):
    monkeypatch.setattr(mod.ExperienceEvaluator, "eth_staker_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.ExperienceEvaluator, "stake_cat_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.ExperienceEvaluator, "obol_techne_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.ExperienceEvaluator, "ssv_verified_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.ExperienceEvaluator, "sdvtm_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.ExperienceEvaluator, "csm_score", lambda self, a: mod.CheckOutcome(score=4))
    assert mod.evaluator.evaluate({"0xabc"}).final_score == 0

    monkeypatch.setattr(mod.ExperienceEvaluator, "eth_staker_score", lambda self, a: mod.CheckOutcome(score=6))
    monkeypatch.setattr(mod.ExperienceEvaluator, "stake_cat_score", lambda self, a: mod.CheckOutcome(score=6))
    monkeypatch.setattr(mod.ExperienceEvaluator, "obol_techne_score", lambda self, a: mod.CheckOutcome(score=6))
    monkeypatch.setattr(mod.ExperienceEvaluator, "ssv_verified_score", lambda self, a: mod.CheckOutcome(score=7))
    monkeypatch.setattr(mod.ExperienceEvaluator, "sdvtm_score", lambda self, a: mod.CheckOutcome(score=5))
    monkeypatch.setattr(mod.ExperienceEvaluator, "csm_score", lambda self, a: mod.CheckOutcome(score=6))
    assert mod.evaluator.evaluate({"0xabc"}).final_score == mod.EXPERIENCE_MAX_SCORE

    monkeypatch.setattr(mod.ExperienceEvaluator, "eth_staker_score", lambda self, a: mod.CheckOutcome(score=6))
    monkeypatch.setattr(mod.ExperienceEvaluator, "stake_cat_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.ExperienceEvaluator, "obol_techne_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.ExperienceEvaluator, "ssv_verified_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.ExperienceEvaluator, "sdvtm_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.ExperienceEvaluator, "csm_score", lambda self, a: mod.CheckOutcome(score=0))
    assert mod.evaluator.evaluate({"0xabc"}).final_score == 6
