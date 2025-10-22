from importlib import util
from pathlib import Path
import pytest


HERE = Path(__file__).resolve()
EXPERIENCE_DIR = HERE.parent.parent / "experience"
MODULE_PATH = EXPERIENCE_DIR / "main.py"


@pytest.fixture()
def mod(tmp_path, monkeypatch):
    spec = util.spec_from_file_location("experience_main", str(MODULE_PATH))
    mod = util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    # Redirect current_dir for file I/O
    mod.current_dir = Path(tmp_path)
    # Ensure CSV lookups use redirected directory by default
    _orig_is = mod.is_addresses_in_csv

    def _is_addresses_in_csv(addresses, csv_file, base_dir=None):
        return _orig_is(addresses, csv_file, base_dir=mod.current_dir if base_dir is None else base_dir)

    mod.is_addresses_in_csv = _is_addresses_in_csv
    return mod


class DummyResp:
    def __init__(self, status=200, data=None, json_exc=None):
        self.status_code = status
        self._data = data if data is not None else {}
        self._json_exc = json_exc

    def raise_for_status(self):
        if not (200 <= self.status_code < 400):
            import requests
            raise requests.HTTPError(f"HTTP {self.status_code}")

    def json(self):
        if self._json_exc:
            raise self._json_exc
        return self._data


def test_is_addresses_in_csv_true_false(mod):
    (mod.current_dir / "list.csv").write_text("0xabc\n0xdef\n")
    assert mod.is_addresses_in_csv({"0xabc"}, "list.csv", base_dir=mod.current_dir) is True
    assert mod.is_addresses_in_csv({"0x123"}, "list.csv", base_dir=mod.current_dir) is False


def test_eth_staker_score(mod):
    (mod.current_dir / "eth-staker-solo-stakers.csv").write_text("0xabc\n")
    assert mod.eth_staker_score({"0xabc"}) == mod.scores["eth-staker"]
    assert mod.eth_staker_score({"0xdef"}) == 0


def test_stake_cat_score_either_file(mod):
    # Ensure both files exist; populate only one at a time
    (mod.current_dir / "stake-cat-solo-B.csv").write_text("")
    (mod.current_dir / "stake-cat-rocketpool-solo-stakers.csv").write_text("")
    (mod.current_dir / "stake-cat-gnosischain.csv").write_text("0xabc\n")
    assert mod.stake_cat_score({"0xabc"}) == mod.scores["stake-cat"]
    # prefer either, so remove and use other file
    (mod.current_dir / "stake-cat-gnosischain.csv").write_text("")
    (mod.current_dir / "stake-cat-solo-B.csv").write_text("0xabc\n")
    assert mod.stake_cat_score({"0xabc"}) == mod.scores["stake-cat"]


def test_obol_techne_precedence(mod):
    # base only
    (mod.current_dir / "obol-techne-credentials-silver.csv").write_text("")
    (mod.current_dir / "obol-techne-credentials-bronze.csv").write_text("")
    (mod.current_dir / "obol-techne-credentials-base.csv").write_text("0xabc\n")
    assert mod.obol_techne_score({"0xabc"}) == mod.scores["obol-techne-base"]
    # bronze overrides base
    (mod.current_dir / "obol-techne-credentials-bronze.csv").write_text("0xabc\n")
    assert mod.obol_techne_score({"0xabc"}) == mod.scores["obol-techne-bronze"]
    # silver overrides bronze
    (mod.current_dir / "obol-techne-credentials-silver.csv").write_text("0xabc\n")
    assert mod.obol_techne_score({"0xabc"}) == mod.scores["obol-techne-silver"]


def test_ssv_verified_score(mod):
    (mod.current_dir / "ssv-verified-operators.csv").write_text("0xdef\n")
    assert mod.ssv_verified_score({"0xdef"}) == mod.scores["ssv-verified"]
    assert mod.ssv_verified_score({"0xabc"}) == 0


def test_sdvtm_mainnet_prioritized(mod):
    (mod.current_dir / "sdvtm-mainnet.csv").write_text("0xabc\n")
    (mod.current_dir / "sdvtm-testnet.csv").write_text("0xabc\n")
    assert mod.sdvtm_score({"0xabc"}) == mod.scores["sdvtm-mainnet"]


def test_request_performance_report_retry_then_success(monkeypatch, mod):
    # Ensure JSONDecodeError exists on requests for catch
    monkeypatch.setattr(mod.requests, "JSONDecodeError", ValueError, raising=False)

    calls = {"n": 0}

    def fake_get(url):
        calls["n"] += 1
        if calls["n"] == 1:
            return DummyResp(status=500)
        if calls["n"] == 2:
            return DummyResp(status=200, json_exc=mod.requests.JSONDecodeError("bad", "doc", 0))
        return DummyResp(status=200, data={"ok": True})

    monkeypatch.setattr(mod.requests, "get", fake_get)
    data = mod._request_performance_report("Qm...")
    assert data == {"ok": True}


def test_request_performance_report_retry_exhaust(monkeypatch, mod):
    calls = {"n": 0}

    def fake_get(url):
        calls["n"] += 1
        return DummyResp(status=500)

    monkeypatch.setattr(mod.requests, "get", fake_get)
    with pytest.raises(Exception):
        mod._request_performance_report("Qm...")
    assert calls["n"] == 3


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


def test_check_csm_performance_logs_true(monkeypatch, mod):
    # owners mapping
    (mod.current_dir / "node_operator_owners_hoodi.json").write_text('{"42": "0xabc"}')

    # patch request to return passing report once
    validators = {
        "v1": {"perf": {"assigned": 10, "included": 9}},
        "v2": {"perf": {"assigned": 0, "included": 0}},  # skipped
    }
    data = make_perf_data(threshold=0.9, validators=validators)
    monkeypatch.setattr(mod, "_request_performance_report", lambda _: data)

    ok = mod._check_csm_performance_logs({"0xabc"}, "node_operator_owners_hoodi.json", ["Qm..."], "Testnet")
    assert ok is True


def test_check_csm_performance_logs_false_when_threshold_not_met(monkeypatch, mod):
    mod = mod
    (mod.current_dir / "node_operator_owners_hoodi.json").write_text('{"42": "0xabc"}')
    validators = {"v1": {"perf": {"assigned": 10, "included": 8}}}
    data = make_perf_data(threshold=0.9, validators=validators)
    monkeypatch.setattr(mod, "_request_performance_report", lambda _: data)
    ok = mod._check_csm_performance_logs({"0xabc"}, "node_operator_owners_hoodi.json", ["Qm..."], "Testnet")
    assert ok is False


def test_csm_score_prefers_mainnet(monkeypatch, mod):
    # owners files
    (mod.current_dir / "node_operator_owners_hoodi.json").write_text('{"42": "0xabc"}')
    (mod.current_dir / "node_operator_owners_mainnet.json").write_text('{"42": "0xabc"}')

    # make mainnet report eligible
    validators = {"v1": {"perf": {"assigned": 10, "included": 10}}}
    data_ok = make_perf_data(threshold=0.9, validators=validators)
    monkeypatch.setattr(mod, "_request_performance_report", lambda _: data_ok)

    # With testnet logic delegated and pending, overall score should use mainnet
    score = mod.csm_score({"0xabc"})
    assert score == mod.scores["csm-mainnet"]


def test_csm_testnet_reads_eligible_file_and_scores(mod):
    # prepare owners mapping
    (mod.current_dir / "node_operator_owners_hoodi.json").write_text('{"42": "0xabc"}')
    # eligible operators file
    (mod.current_dir / "eligible_node_operators_hoodi.json").write_text('["42"]')
    score = mod._csm_testnet_score({"0xabc"})
    assert score == mod.scores["csm-testnet"]


def test_csm_testnet_reads_eligible_file_with_circles_bonus(mod):
    (mod.current_dir / "node_operator_owners_hoodi.json").write_text('{"42": "0xabc"}')
    (mod.current_dir / "eligible_node_operators_hoodi.json").write_text('["42"]')
    humanity_dir = mod.current_dir.parent / "humanity"
    humanity_dir.mkdir(parents=True, exist_ok=True)
    (humanity_dir / "circle_group_members.csv").write_text("0xabc\n")
    score = mod._csm_testnet_score({"0xabc"})
    assert score == mod.scores["csm-testnet-circles-verified"]


def test_main_aggregator_threshold_and_capping(monkeypatch, mod):
    # Below MIN_SCORE -> 0
    monkeypatch.setattr(mod, "eth_staker_score", lambda a: 0)
    monkeypatch.setattr(mod, "stake_cat_score", lambda a: 0)
    monkeypatch.setattr(mod, "obol_techne_score", lambda a: 0)
    monkeypatch.setattr(mod, "ssv_verified_score", lambda a: 0)
    monkeypatch.setattr(mod, "sdvtm_score", lambda a: 0)
    monkeypatch.setattr(mod, "csm_score", lambda a: 4)
    assert mod.main(addresses={"0xabc"}) == 0

    # Exceed MAX_SCORE -> capped
    monkeypatch.setattr(mod, "eth_staker_score", lambda a: 6)
    monkeypatch.setattr(mod, "stake_cat_score", lambda a: 6)
    monkeypatch.setattr(mod, "obol_techne_score", lambda a: 6)
    monkeypatch.setattr(mod, "ssv_verified_score", lambda a: 7)
    monkeypatch.setattr(mod, "sdvtm_score", lambda a: 5)
    monkeypatch.setattr(mod, "csm_score", lambda a: 6)
    assert mod.main(addresses={"0xabc"}) == mod.MAX_SCORE

    # Normal within range
    monkeypatch.setattr(mod, "eth_staker_score", lambda a: 6)
    monkeypatch.setattr(mod, "stake_cat_score", lambda a: 0)
    monkeypatch.setattr(mod, "obol_techne_score", lambda a: 0)
    monkeypatch.setattr(mod, "ssv_verified_score", lambda a: 0)
    monkeypatch.setattr(mod, "sdvtm_score", lambda a: 0)
    monkeypatch.setattr(mod, "csm_score", lambda a: 0)
    assert mod.main(addresses={"0xabc"}) == 6

