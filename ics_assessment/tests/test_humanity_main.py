from importlib import util
from pathlib import Path

import pytest


HERE = Path(__file__).resolve()
HUMANITY_DIR = HERE.parent.parent / "humanity"
MODULE_PATH = HUMANITY_DIR / "assess.py"


@pytest.fixture()
def mod(tmp_path):
    spec = util.spec_from_file_location("humanity_main", str(MODULE_PATH))
    mod = util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    mod.current_dir = Path(tmp_path)
    mod.sources = mod.HumanitySources(circle_group_members_path=tmp_path / "circle_group_members.csv")
    mod.evaluator = mod.HumanityEvaluator(mod.sources)
    return mod


def test_human_passport_score_with_source_address(mod):
    outcome = mod.HumanityEvaluator(
        mod.sources,
        mod.HumanityRuntimeInputs(human_passport_score=7.2, human_passport_address="0xdef"),
    ).human_passport_score()
    assert outcome.score == 7.2
    assert "address=0xdef" in outcome.detail


def test_human_passport_score_min_and_cap(mod):
    assert mod.HumanityEvaluator(
        mod.sources,
        mod.HumanityRuntimeInputs(human_passport_score=mod.HUMANITY_SCORES["human-passport-min"] - 0.1),
    ).human_passport_score() == mod.CheckOutcome(score=0)
    assert mod.HumanityEvaluator(
        mod.sources,
        mod.HumanityRuntimeInputs(human_passport_score=mod.HUMANITY_SCORES["human-passport-max"] + 5),
    ).human_passport_score().score == mod.HUMANITY_SCORES["human-passport-max"]


def test_human_passport_score_none_zero(mod):
    assert mod.evaluator.human_passport_score() == mod.CheckOutcome(score=0)


def test_circles_verified_score(mod):
    mod.sources.circle_group_members_path.write_text("0xabc\n")
    assert mod.evaluator.circles_verified_score({"0xabc"}) == mod.CheckOutcome(
        score=mod.HUMANITY_SCORES["circles-verified"],
        detail="0xabc",
    )
    assert mod.evaluator.circles_verified_score({"0xdef"}) == mod.CheckOutcome(score=0)


def test_discord_and_x_account_scores(mod):
    assert mod.evaluator.discord_account_score(True) == mod.HUMANITY_SCORES["discord-account"]
    assert mod.evaluator.discord_account_score(False) == 0
    assert mod.evaluator.x_account_score(True) == mod.HUMANITY_SCORES["x-account"]
    assert mod.evaluator.x_account_score(False) == 0


def test_main_aggregator_threshold_and_capping(monkeypatch, mod):
    monkeypatch.setattr(mod.HumanityEvaluator, "human_passport_score", lambda self: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.HumanityEvaluator, "circles_verified_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.HumanityEvaluator, "discord_account_score", lambda self, discord: 2)
    monkeypatch.setattr(mod.HumanityEvaluator, "x_account_score", lambda self, x: 1)
    assert mod.evaluator.evaluate({"0xabc"}).final_score == 0

    monkeypatch.setattr(mod.HumanityEvaluator, "human_passport_score", lambda self: mod.CheckOutcome(score=8))
    monkeypatch.setattr(mod.HumanityEvaluator, "circles_verified_score", lambda self, a: mod.CheckOutcome(score=4))
    monkeypatch.setattr(mod.HumanityEvaluator, "discord_account_score", lambda self, discord: 2)
    monkeypatch.setattr(mod.HumanityEvaluator, "x_account_score", lambda self, x: 1)
    assert mod.evaluator.evaluate({"0xabc"}).final_score == mod.HUMANITY_MAX_SCORE

    monkeypatch.setattr(mod.HumanityEvaluator, "human_passport_score", lambda self: mod.CheckOutcome(score=4))
    monkeypatch.setattr(mod.HumanityEvaluator, "circles_verified_score", lambda self, a: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.HumanityEvaluator, "discord_account_score", lambda self, discord: 0)
    monkeypatch.setattr(mod.HumanityEvaluator, "x_account_score", lambda self, x: 0)
    assert mod.evaluator.evaluate({"0xabc"}).final_score == 4
