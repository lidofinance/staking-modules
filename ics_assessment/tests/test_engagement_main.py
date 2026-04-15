import sys
import types
from importlib import util
from pathlib import Path


HERE = Path(__file__).resolve()
ENGAGEMENT_DIR = HERE.parent.parent / "engagement"
MODULE_PATH = ENGAGEMENT_DIR / "assess.py"


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def _load_module(tmp_path: Path):
    web3_stub = types.SimpleNamespace(
        Web3=types.SimpleNamespace(to_checksum_address=lambda x: x)
    )
    sys.modules.setdefault("web3", web3_stub)

    spec = util.spec_from_file_location("engagement_main", str(MODULE_PATH))
    mod = util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)

    mod.sources = mod.EngagementSources(
        aragon_voters_path=tmp_path / "aragon_voters.csv",
        snapshot_voters_path=tmp_path / "snapshot_voters.csv",
        galxe_loyalty_points_path=tmp_path / "galxe_loyalty_points.csv",
        gitpoap_holders_path=tmp_path / "gitpoap_holders.csv",
        protocol_guild_path=tmp_path / "protocol_guild.csv",
    )
    mod.evaluator = mod.EngagementEvaluator(mod.sources)
    return mod


def test_snapshot_vote_award(tmp_path):
    mod = _load_module(tmp_path)
    _write(mod.sources.snapshot_voters_path, "Address,VoteCount\n0xabc,3\n")
    outcome = mod.evaluator.snapshot_vote({"0xabc"})
    assert outcome.score == mod.ENGAGEMENT_SCORES["snapshot-vote"]
    assert "0xabc=3" in outcome.detail


def test_snapshot_vote_zero(tmp_path):
    mod = _load_module(tmp_path)
    _write(mod.sources.snapshot_voters_path, "Address,VoteCount\n0xabc,2\n")
    assert mod.evaluator.snapshot_vote({"0xabc"}) == mod.CheckOutcome(score=0)


def test_aragon_vote_threshold_awarded(tmp_path):
    mod = _load_module(tmp_path)
    _write(mod.sources.aragon_voters_path, "Address,VoteCount\n0xabc,1\n0xdef,2\n")
    outcome = mod.evaluator.aragon_vote({"0xdef"})
    assert outcome.score == mod.ENGAGEMENT_SCORES["aragon-vote"]
    assert "0xdef=2" in outcome.detail


def test_aragon_vote_below_threshold_zero(tmp_path):
    mod = _load_module(tmp_path)
    _write(mod.sources.aragon_voters_path, "Address,VoteCount\n0xabc,1\n")
    assert mod.evaluator.aragon_vote({"0xabc"}) == mod.CheckOutcome(score=0)


def test_aragon_vote_case_insensitive(tmp_path):
    mod = _load_module(tmp_path)
    _write(mod.sources.aragon_voters_path, "Address,VoteCount\n0xAbC,2\n")
    assert mod.evaluator.aragon_vote({"0xabc"}).score == mod.ENGAGEMENT_SCORES["aragon-vote"]


def test_galxe_scores_above_10_early_return(tmp_path):
    mod = _load_module(tmp_path)
    _write(mod.sources.galxe_loyalty_points_path, "Address,Points\n0xabc,11\n0xdef,4\n")
    outcome = mod.evaluator.galxe_scores({"0xabc", "0xdef"})
    assert outcome.score == mod.ENGAGEMENT_SCORES["galxe-score-above-10"]
    assert outcome.detail == "0xabc=11"


def test_galxe_scores_between_4_and_10(tmp_path):
    mod = _load_module(tmp_path)
    _write(mod.sources.galxe_loyalty_points_path, "Address,Points\n0xdef,7\n")
    assert mod.evaluator.galxe_scores({"0xabc", "0xdef"}) == mod.CheckOutcome(
        score=mod.ENGAGEMENT_SCORES["galxe-score-4-10"],
        detail="0xdef=7",
    )


def test_galxe_scores_none_zero(tmp_path):
    mod = _load_module(tmp_path)
    _write(mod.sources.galxe_loyalty_points_path, "Address,Points\n0xdef,3\n")
    assert mod.evaluator.galxe_scores({"0xabc"}) == mod.CheckOutcome(score=0)


def test_gitpoap_any_event_awards_once(tmp_path):
    mod = _load_module(tmp_path)
    _write(
        mod.sources.gitpoap_holders_path,
        "Address,EventID,EventName\n0xabc,1,evt1\n0xdef,2,evt2\n",
    )
    outcome = mod.evaluator.gitpoap({"0xabc"})
    assert outcome.score == mod.ENGAGEMENT_SCORES["git-poap"]
    assert "evt1" in outcome.detail


def test_gitpoap_no_matches_zero(tmp_path):
    mod = _load_module(tmp_path)
    _write(mod.sources.gitpoap_holders_path, "Address,EventID,EventName\n0xdef,1,evt1\n")
    assert mod.evaluator.gitpoap({"0xabc"}) == mod.CheckOutcome(score=0)


def test_high_signal_api_buckets_and_max(monkeypatch, tmp_path):
    mod = _load_module(tmp_path)
    outcome = mod.EngagementEvaluator(
        mod.sources,
        mod.EngagementRuntimeInputs(
            high_signal_score=85,
            high_signal_address="0x1231231231231231231312312312312311231232",
        ),
    ).high_signal()
    assert outcome.score == mod.ENGAGEMENT_SCORES["high-signal-80"]
    assert "address=0x1231231231231231231312312312312311231232" in outcome.detail


def test_high_signal_valid_boundaries(tmp_path):
    mod = _load_module(tmp_path)
    assert mod.EngagementEvaluator(mod.sources, mod.EngagementRuntimeInputs(high_signal_score=30)).high_signal().score == mod.ENGAGEMENT_SCORES["high-signal-30"]
    assert mod.EngagementEvaluator(mod.sources, mod.EngagementRuntimeInputs(high_signal_score=40)).high_signal().score == mod.ENGAGEMENT_SCORES["high-signal-30"]
    assert mod.EngagementEvaluator(mod.sources, mod.EngagementRuntimeInputs(high_signal_score=41)).high_signal().score == mod.ENGAGEMENT_SCORES["high-signal-40"]
    assert mod.EngagementEvaluator(mod.sources, mod.EngagementRuntimeInputs(high_signal_score=60)).high_signal().score == mod.ENGAGEMENT_SCORES["high-signal-40"]
    assert mod.EngagementEvaluator(mod.sources, mod.EngagementRuntimeInputs(high_signal_score=61)).high_signal().score == mod.ENGAGEMENT_SCORES["high-signal-60"]
    assert mod.EngagementEvaluator(mod.sources, mod.EngagementRuntimeInputs(high_signal_score=81)).high_signal().score == mod.ENGAGEMENT_SCORES["high-signal-80"]


def test_high_signal_invalid_and_out_of_range(tmp_path):
    mod = _load_module(tmp_path)
    assert mod.evaluator.high_signal() == mod.CheckOutcome(score=0)
    assert mod.EngagementEvaluator(mod.sources, mod.EngagementRuntimeInputs(high_signal_score=150)).high_signal() == mod.CheckOutcome(score=0)
    assert mod.EngagementEvaluator(mod.sources, mod.EngagementRuntimeInputs(high_signal_score=25)).high_signal() == mod.CheckOutcome(score=0)


def test_main_aggregator_threshold_and_capping(monkeypatch, tmp_path):
    mod = _load_module(tmp_path)
    monkeypatch.setattr(mod.EngagementEvaluator, "snapshot_vote", lambda self, addrs: mod.CheckOutcome(score=1))
    monkeypatch.setattr(mod.EngagementEvaluator, "aragon_vote", lambda self, addrs: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.EngagementEvaluator, "galxe_scores", lambda self, addrs: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.EngagementEvaluator, "gitpoap", lambda self, addrs: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.EngagementEvaluator, "high_signal", lambda self: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.EngagementEvaluator, "protocol_guild", lambda self, addrs: mod.CheckOutcome(score=0))
    assert mod.evaluator.evaluate({"0xabc"}).final_score == 0

    monkeypatch.setattr(mod.EngagementEvaluator, "snapshot_vote", lambda self, addrs: mod.CheckOutcome(score=3))
    monkeypatch.setattr(mod.EngagementEvaluator, "aragon_vote", lambda self, addrs: mod.CheckOutcome(score=3))
    monkeypatch.setattr(mod.EngagementEvaluator, "galxe_scores", lambda self, addrs: mod.CheckOutcome(score=3))
    monkeypatch.setattr(mod.EngagementEvaluator, "gitpoap", lambda self, addrs: mod.CheckOutcome(score=3))
    monkeypatch.setattr(mod.EngagementEvaluator, "high_signal", lambda self: mod.CheckOutcome(score=3))
    monkeypatch.setattr(mod.EngagementEvaluator, "protocol_guild", lambda self, addrs: mod.CheckOutcome(score=0))
    assert mod.evaluator.evaluate({"0xabc"}).final_score == mod.ENGAGEMENT_MAX_SCORE

    monkeypatch.setattr(mod.EngagementEvaluator, "snapshot_vote", lambda self, addrs: mod.CheckOutcome(score=1))
    monkeypatch.setattr(mod.EngagementEvaluator, "aragon_vote", lambda self, addrs: mod.CheckOutcome(score=2))
    monkeypatch.setattr(mod.EngagementEvaluator, "galxe_scores", lambda self, addrs: mod.CheckOutcome(score=0))
    monkeypatch.setattr(mod.EngagementEvaluator, "gitpoap", lambda self, addrs: mod.CheckOutcome(score=2))
    monkeypatch.setattr(mod.EngagementEvaluator, "high_signal", lambda self: mod.CheckOutcome(score=2))
    monkeypatch.setattr(mod.EngagementEvaluator, "protocol_guild", lambda self, addrs: mod.CheckOutcome(score=0))
    assert mod.evaluator.evaluate({"0xabc", "0xdef"}).final_score == 7
