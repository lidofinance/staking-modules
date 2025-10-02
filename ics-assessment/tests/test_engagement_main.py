import json
import types
import sys
from importlib import util
from pathlib import Path
import pytest


HERE = Path(__file__).resolve()
ENGAGEMENT_DIR = HERE.parent.parent / "engagement"
MODULE_PATH = ENGAGEMENT_DIR / "main.py"


@pytest.fixture()
def mod(tmp_path):
    # Stub web3 early to avoid import errors
    web3_stub = types.SimpleNamespace(
        Web3=types.SimpleNamespace(to_checksum_address=lambda x: x)
    )
    sys.modules.setdefault("web3", web3_stub)

    spec = util.spec_from_file_location("engagement_main", str(MODULE_PATH))
    mod = util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    # redirect file base to temp directory used by tests
    mod.current_dir = Path(tmp_path)
    mod.CACHE_DIR = mod.current_dir / ".cache"
    return mod


class DummyResp:
    def __init__(self, status=200, data=None):
        self.status_code = status
        self._data = data if data is not None else {}

    def raise_for_status(self):
        if not (200 <= self.status_code < 400):
            raise Exception(f"HTTP {self.status_code}")

    def json(self):
        return self._data


def test_snapshot_vote_award(monkeypatch, mod):
    def fake_post(url, json=None):
        assert "snapshot" in url
        return DummyResp(
            200,
            {"data": {"votes": [{"id": 1}, {"id": 2}, {"id": 3}]}},
        )

    monkeypatch.setattr(mod.requests, "post", fake_post)
    score = mod.snapshot_vote({"0xabc"})
    assert score == mod.scores["snapshot-vote"]


def test_snapshot_vote_zero(monkeypatch, mod):
    def fake_post(url, json=None):
        return DummyResp(200, {"data": {"votes": []}})

    monkeypatch.setattr(mod.requests, "post", fake_post)
    assert mod.snapshot_vote({"0xabc"}) == 0


def test_snapshot_vote_errors_raise(monkeypatch, mod):
    def fake_post(url, json=None):
        return DummyResp(200, {"errors": [{"message": "boom"}]})

    monkeypatch.setattr(mod.requests, "post", fake_post)
    try:
        mod.snapshot_vote({"0xabc"})
        assert False, "Expected exception"
    except Exception as e:
        assert "Error fetching Snapshot votes" in str(e)


def test_aragon_vote_threshold_awarded(monkeypatch, mod):
    csv_path = Path(mod.current_dir) / "aragon_voters.csv"
    csv_path.write_text("Address,VoteCount\n0xabc,1\n0xdef,2\n")
    assert mod.aragon_vote({"0xdef"}) == mod.scores["aragon-vote"]


def test_aragon_vote_below_threshold_zero(monkeypatch, mod):
    (Path(mod.current_dir) / "aragon_voters.csv").write_text("Address,VoteCount\n0xabc,1\n")
    assert mod.aragon_vote({"0xabc"}) == 0


def test_aragon_vote_case_insensitive(monkeypatch, mod):
    (Path(mod.current_dir) / "aragon_voters.csv").write_text("Address,VoteCount\n0xAbC,2\n")
    assert mod.aragon_vote({"0xabc"}) == mod.scores["aragon-vote"]


def test_galxe_scores_above_10_early_return(monkeypatch, mod):
    calls = {"count": 0}

    def fake_post(url, json=None, headers=None):
        calls["count"] += 1
        # First page with next page
        if calls["count"] == 1:
            data = {
                "data": {
                    "space": {
                        "loyaltyPointsRanks": {
                            "pageInfo": {"hasNextPage": True, "endCursor": "1"},
                            "edges": [
                                {"node": {"points": 11, "address": {"address": "0xabc"}}}
                            ],
                        }
                    }
                }
            }
        else:
            data = {
                "data": {
                    "space": {
                        "loyaltyPointsRanks": {
                            "pageInfo": {"hasNextPage": False, "endCursor": None},
                            "edges": [],
                        }
                    }
                }
            }
        return DummyResp(200, data)

    monkeypatch.setattr(mod.requests, "post", fake_post)
    score = mod.galxe_scores({"0xabc", "0xdef"})
    assert score == mod.scores["galxe-score-above-10"]


def test_galxe_scores_between_4_and_10(monkeypatch, mod):
    pages = [
        {
            "data": {
                "space": {
                    "loyaltyPointsRanks": {
                        "pageInfo": {"hasNextPage": False, "endCursor": None},
                        "edges": [
                            {"node": {"points": 7, "address": {"address": "0xdef"}}}
                        ],
                    }
                }
            }
        }
    ]

    def fake_post(url, json=None, headers=None):
        return DummyResp(200, pages[0])

    monkeypatch.setattr(mod.requests, "post", fake_post)
    score = mod.galxe_scores({"0xabc", "0xdef"})
    assert score == mod.scores["galxe-score-4-10"]


def test_galxe_scores_none_zero(monkeypatch, mod):
    data = {
        "data": {
            "space": {
                "loyaltyPointsRanks": {
                    "pageInfo": {"hasNextPage": False, "endCursor": None},
                    "edges": [],
                }
            }
        }
    }

    def fake_post(url, json=None, headers=None):
        return DummyResp(200, data)

    monkeypatch.setattr(mod.requests, "post", fake_post)
    assert mod.galxe_scores({"0xabc"}) == 0


def test_galxe_scores_uses_cache(monkeypatch, mod, capsys):
    cache_dir = mod.CACHE_DIR
    cache_dir.mkdir(parents=True, exist_ok=True)
    cached_data = [
        {"points": 12, "address": {"address": "0xabc"}},
        {"points": 3, "address": {"address": "0xdef"}},
    ]
    (cache_dir / "galxe_loyalty_points.json").write_text(json.dumps(cached_data))

    def fail_post(*_args, **_kwargs):
        raise AssertionError("Network call should be skipped when cache is present")

    monkeypatch.setattr(mod.requests, "post", fail_post)
    score = mod.galxe_scores({"0xabc"})
    captured = capsys.readouterr()
    assert "Warning: found cache file" in captured.out
    assert score == mod.scores["galxe-score-above-10"]


def test_gitpoap_any_event_awards_once(monkeypatch, mod):
    # prepare events csv
    (Path(mod.current_dir) / "gitpoap_events.csv").write_text("ID,Name\n1,evt1\n2,evt2\n")

    class FakeSession:
        def __init__(self):
            self.reqs = []

        def get(self, url):
            if url.endswith("/1/addresses"):
                return DummyResp(200, {"addresses": ["0xabc"]})
            return DummyResp(200, {"addresses": []})

        def mount(self, *args, **kwargs):
            return None

    monkeypatch.setattr(mod.requests, "Session", FakeSession)
    score = mod.gitpoap({"0xabc"})
    assert score == mod.scores["git-poap"]


def test_gitpoap_no_matches_zero(monkeypatch, mod):
    (Path(mod.current_dir) / "gitpoap_events.csv").write_text("ID,Name\n1,evt1\n")

    class FakeSession:
        def get(self, url):
            return DummyResp(200, {"addresses": []})

        def mount(self, *args, **kwargs):
            return None

    monkeypatch.setattr(mod.requests, "Session", FakeSession)
    assert mod.gitpoap({"0xabc"}) == 0


def test_gitpoap_uses_cache(monkeypatch, mod, capsys):
    events_csv = Path(mod.current_dir) / "gitpoap_events.csv"
    events_csv.write_text("ID,Name\n1,evt1\n")

    cache_dir = mod.CACHE_DIR
    cache_dir.mkdir(parents=True, exist_ok=True)
    cached = {"1": ["0xabc"]}
    (cache_dir / "gitpoap_holders.json").write_text(json.dumps(cached))

    class FailSession:
        def __init__(self):
            raise AssertionError("Session should not be instantiated when cache is used")

    monkeypatch.setattr(mod.requests, "Session", FailSession)
    score = mod.gitpoap({"0xabc"})
    captured = capsys.readouterr()
    assert "Warning: found cache file" in captured.out
    assert score == mod.scores["git-poap"]


def test_high_signal_api_buckets_and_max(monkeypatch, mod):
    monkeypatch.setenv("HIGH_SIGNAL_API_KEY", "key")

    # Return 35 for addr1, 85 for addr2, 404 for addr3
    def fake_get(url, params=None):
        val = params.get("searchValue")
        if val == "0x1231231231231231231312312312312311231233":
            return DummyResp(200, {"totalScores": [{"totalScore": 35}]})
        if val == "0x1231231231231231231312312312312311231232":
            return DummyResp(200, {"totalScores": [{"totalScore": 85}]})
        return DummyResp(404, {})

    monkeypatch.setattr(mod.requests, "get", fake_get)
    score = mod.high_signal({"0x1231231231231231231312312312312311231233", "0x1231231231231231231312312312312311231232", "0x1231231231231231231312312312312311231231"})
    assert score == mod.scores["high-signal-80"]


def test_high_signal_manual_valid_boundaries(monkeypatch, mod):
    monkeypatch.delenv("HIGH_SIGNAL_API_KEY", raising=False)
    # boundary 30 -> 2
    monkeypatch.setattr("builtins.input", lambda _: "30")
    assert mod.high_signal({"0xabc"}) == mod.scores["high-signal-30"]
    # boundary 40 -> 2
    monkeypatch.setattr("builtins.input", lambda _: "40")
    assert mod.high_signal({"0xabc"}) == mod.scores["high-signal-30"]
    # 41 -> 3
    monkeypatch.setattr("builtins.input", lambda _: "41")
    assert mod.high_signal({"0xabc"}) == mod.scores["high-signal-40"]
    # 60 -> 3
    monkeypatch.setattr("builtins.input", lambda _: "60")
    assert mod.high_signal({"0xabc"}) == mod.scores["high-signal-40"]
    # 61 -> 4
    monkeypatch.setattr("builtins.input", lambda _: "61")
    assert mod.high_signal({"0xabc"}) == mod.scores["high-signal-60"]
    # 81 -> 5
    monkeypatch.setattr("builtins.input", lambda _: "81")
    assert mod.high_signal({"0xabc"}) == mod.scores["high-signal-80"]


def test_high_signal_manual_invalid_and_out_of_range(monkeypatch, mod):
    monkeypatch.delenv("HIGH_SIGNAL_API_KEY", raising=False)
    # invalid input
    monkeypatch.setattr("builtins.input", lambda _: "abc")
    assert mod.high_signal({"0xabc"}) == 0
    # out of range
    monkeypatch.setattr("builtins.input", lambda _: "150")
    assert mod.high_signal({"0xabc"}) == 0
    # below threshold
    monkeypatch.setattr("builtins.input", lambda _: "25")
    assert mod.high_signal({"0xabc"}) == 0


def test_main_aggregator_threshold_and_capping(monkeypatch, mod):
    # Patch scoring functions to controlled values
    monkeypatch.setattr(mod, "snapshot_vote", lambda addrs: 1)
    monkeypatch.setattr(mod, "aragon_vote", lambda addrs: 0)
    monkeypatch.setattr(mod, "galxe_scores", lambda addrs: 0)
    monkeypatch.setattr(mod, "gitpoap", lambda addrs: 0)
    monkeypatch.setattr(mod, "high_signal", lambda addrs, score=None: 0)
    monkeypatch.setattr(mod, "protocol_guild", lambda addrs, score=None: 0)

    # Below MIN_SCORE (2) -> 0
    res = mod.main(addresses={"0xabc"})
    assert res == 0

    # Now make it exceed MAX_SCORE (7)
    monkeypatch.setattr(mod, "snapshot_vote", lambda addrs: 3)
    monkeypatch.setattr(mod, "aragon_vote", lambda addrs: 3)
    monkeypatch.setattr(mod, "galxe_scores", lambda addrs: 3)
    monkeypatch.setattr(mod, "gitpoap", lambda addrs: 3)
    monkeypatch.setattr(mod, "high_signal", lambda addrs, score=None: 3)
    monkeypatch.setattr(mod, "protocol_guild", lambda addrs, score=None: 0)
    res2 = mod.main(addresses={"0xabc"})
    assert res2 == mod.MAX_SCORE

    # Normal sum within range
    monkeypatch.setattr(mod, "snapshot_vote", lambda addrs: 1)
    monkeypatch.setattr(mod, "aragon_vote", lambda addrs: 2)
    monkeypatch.setattr(mod, "galxe_scores", lambda addrs: 0)
    monkeypatch.setattr(mod, "gitpoap", lambda addrs: 2)
    monkeypatch.setattr(mod, "high_signal", lambda addrs, score=None: 2)
    monkeypatch.setattr(mod, "protocol_guild", lambda addrs, score=None: 0)
    res3 = mod.main(addresses={"0xabc", "0xdef"})
    assert res3 == 7  # 1+2+0+2+2 = 7, capped by MAX_SCORE=7 but already equal
