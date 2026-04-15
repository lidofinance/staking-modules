import csv
import importlib
import json
import sys
import types
from pathlib import Path

import requests


class DummyResp:
    def __init__(self, status=200, data=None):
        self.status_code = status
        self._data = data if data is not None else {}

    def raise_for_status(self):
        if not (200 <= self.status_code < 400):
            raise Exception(f"HTTP {self.status_code}")

    def json(self):
        return self._data


def _load_module():
    async_web3_stub = types.SimpleNamespace(AsyncHTTPProvider=object)
    web3_stub = types.SimpleNamespace(
        AsyncWeb3=async_web3_stub,
        Web3=types.SimpleNamespace(HTTPProvider=object),
    )
    sys.modules.setdefault("web3", web3_stub)
    sys.modules.pop("ics_assessment.sync", None)
    return importlib.import_module("ics_assessment.sync")


def test_expand_targets_all_dedupes():
    mod = _load_module()
    targets = mod._expand_targets(["all", "galxe"])
    assert targets == mod.JOB_ORDER


def test_sync_snapshot_writes_votes(monkeypatch, tmp_path):
    mod = _load_module()
    mod.engagement_jobs.SNAPSHOT_VOTERS_PATH = tmp_path / "snapshot_voters.csv"

    calls = {"count": 0}

    def fake_post(url, json=None):
        calls["count"] += 1
        created_lt = json["variables"]["created_lt"]
        if created_lt == mod.engagement_jobs.SNAPSHOT_VOTE_TIMESTAMP:
            return DummyResp(
                200,
                {
                    "data": {
                        "votes": [
                            {"voter": "0xabc", "id": "v1", "created": 100},
                            {"voter": "0xabc", "id": "v2", "created": 99},
                            {"voter": "0xdef", "id": "v3", "created": 99},
                        ]
                    }
                },
            )
        if created_lt == 99:
            return DummyResp(
                200,
                {
                    "data": {
                        "votes": [
                            {"voter": "0xabc", "id": "v4", "created": 98},
                        ]
                    }
                },
            )
        return DummyResp(200, {"data": {"votes": []}})

    monkeypatch.setattr(mod.engagement_jobs.requests, "post", fake_post)
    mod.engagement_jobs.sync_snapshot()

    rows = list(csv.DictReader(mod.engagement_jobs.SNAPSHOT_VOTERS_PATH.open()))
    assert rows == [
        {"Address": "0xabc", "VoteCount": "3"},
        {"Address": "0xdef", "VoteCount": "1"},
    ]
    assert calls["count"] == 3


def test_sync_galxe_writes_points(monkeypatch, tmp_path):
    mod = _load_module()
    mod.engagement_jobs.GALXE_LOYALTY_POINTS_PATH = tmp_path / "galxe_loyalty_points.csv"

    def fake_post(url, json=None, headers=None):
        cursor = json["variables"]["cursor"]
        if cursor is None:
            return DummyResp(
                200,
                {
                    "data": {
                        "space": {
                            "loyaltyPointsRanks": {
                                "pageInfo": {"hasNextPage": True, "endCursor": "next"},
                                "edges": [{"node": {"points": 7, "address": {"address": "0xdef"}}}],
                            }
                        }
                    }
                },
            )
        return DummyResp(
            200,
            {
                "data": {
                    "space": {
                        "loyaltyPointsRanks": {
                            "pageInfo": {"hasNextPage": False, "endCursor": None},
                            "edges": [{"node": {"points": 11, "address": {"address": "0xabc"}}}],
                        }
                    }
                }
            },
        )

    monkeypatch.setattr(mod.engagement_jobs.requests, "post", fake_post)
    mod.engagement_jobs.sync_galxe()

    rows = list(csv.DictReader(mod.engagement_jobs.GALXE_LOYALTY_POINTS_PATH.open()))
    assert rows == [
        {"Address": "0xabc", "Points": "11"},
        {"Address": "0xdef", "Points": "7"},
    ]


def test_sync_gitpoap_writes_holders(monkeypatch, tmp_path):
    mod = _load_module()
    mod.engagement_jobs.GITPOAP_EVENTS_PATH = tmp_path / "gitpoap_events.csv"
    mod.engagement_jobs.GITPOAP_HOLDERS_PATH = tmp_path / "gitpoap_holders.csv"
    mod.engagement_jobs.GITPOAP_EVENTS_PATH.write_text("ID,Name\n1,evt1\n2,evt2\n")

    class FakeSession:
        def mount(self, *args, **kwargs):
            return None

        def get(self, url):
            if url.endswith("/1/addresses"):
                return DummyResp(200, {"addresses": ["0xabc"]})
            return DummyResp(200, {"addresses": ["0xdef"]})

    monkeypatch.setattr(mod.engagement_jobs.requests, "Session", FakeSession)
    mod.engagement_jobs.sync_gitpoap()

    rows = list(csv.DictReader(mod.engagement_jobs.GITPOAP_HOLDERS_PATH.open()))
    assert rows == [
        {"Address": "0xabc", "EventID": "1", "EventName": "evt1"},
        {"Address": "0xdef", "EventID": "2", "EventName": "evt2"},
    ]


def test_sync_ssv_verified_writes_holders(monkeypatch, tmp_path):
    mod = _load_module()
    mod.experience_jobs.SSV_VERIFIED_OPERATORS_PATH = tmp_path / "ssv-verified-operators.csv"

    def fake_get(url, timeout=None):
        assert "ssv.network" in url
        return DummyResp(
            200,
            {
                "operators": [
                    {"owner_address": "0xDef"},
                    {"owner_address": "0xabc"},
                    {"owner_address": "0xabc"},
                ]
            },
        )

    monkeypatch.setattr(mod.experience_jobs.requests, "get", fake_get)
    mod.experience_jobs.sync_ssv_verified()

    rows = list(csv.DictReader(mod.experience_jobs.SSV_VERIFIED_OPERATORS_PATH.open()))
    assert rows == [
        {"Address": "0xabc"},
        {"Address": "0xdef"},
    ]


def test_write_csv_uses_lf_line_endings(tmp_path):
    mod = _load_module()
    path = tmp_path / "out.csv"

    mod.write_csv(path, ["Address", "VoteCount"], [["0xabc", 1]])

    data = path.read_bytes()
    assert b"\r\n" not in data
    assert data == b"Address,VoteCount\n0xabc,1\n"


def test_run_sync_requires_configured_rpc_env():
    mod = _load_module()
    mod.engagement_jobs.MAINNET_RPC_URL = ""
    called = {"value": False}
    mod.JOBS["aragon"] = lambda: called.__setitem__("value", True)

    try:
        mod.run_sync(["aragon"])
    except SystemExit as exc:
        message = str(exc)
        assert "MAINNET_RPC_URL" in message
        assert "before running sync" in message
    else:
        raise AssertionError("expected sync env validation")
    assert called["value"] is False


def test_request_performance_report_retries_then_succeeds(monkeypatch):
    mod = _load_module()
    calls = {"count": 0}

    class FailingResp:
        def raise_for_status(self):
            raise Exception("boom")

    class OkResp:
        def raise_for_status(self):
            return None

        def json(self):
            return {"ok": True}

    def fake_get(url, timeout=None):
        calls["count"] += 1
        if calls["count"] < 3:
            return FailingResp()
        return OkResp()

    monkeypatch.setattr(mod.experience_jobs.requests, "get", fake_get)
    monkeypatch.setattr(mod.experience_jobs.time, "sleep", lambda _: None)

    assert mod.experience_jobs.request_performance_report("Qm") == {"ok": True}
    assert calls["count"] == 3


def test_sync_mainnet_performance_writes_eligible_ids(monkeypatch, tmp_path):
    mod = _load_module()
    mod.experience_jobs.ELIGIBLE_NODE_OPERATORS_MAINNET_PATH = (
        tmp_path / "eligible_node_operators_mainnet.json"
    )

    reports = iter(
        [
            {
                "threshold": 0.9,
                "operators": {
                    "42": {"validators": {"v1": {"perf": {"assigned": 10, "included": 10}}}},
                    "43": {"validators": {"v1": {"perf": {"assigned": 10, "included": 8}}}},
                },
            },
            {
                "threshold": 0.8,
                "operators": {
                    "44": {"validators": {"v1": {"perf": {"assigned": 5, "included": 4}}}},
                },
            },
        ]
    )

    monkeypatch.setattr(
        mod.experience_jobs,
        "request_performance_report",
        lambda cid: next(reports),
    )

    mod.experience_jobs.sync_mainnet_performance()

    assert json.loads(
        mod.experience_jobs.ELIGIBLE_NODE_OPERATORS_MAINNET_PATH.read_text(encoding="utf-8")
    ) == ["42", "44"]


def test_get_event_logs_splits_range_on_failure():
    mod = _load_module()
    mod.LOG_CHUNK_SIZE = 5

    class FakeEvent:
        def __init__(self):
            self.calls = []

        def get_logs(self, from_block=None, to_block=None):
            self.calls.append((from_block, to_block))
            return [f"{from_block}-{to_block}"]

    event = FakeEvent()
    logs = mod.get_event_logs(event, 0, 9)

    assert logs == ["0-4", "5-9"]
    assert event.calls == [(0, 4), (5, 9)]


def test_get_event_logs_fails_fast_on_connection_error():
    mod = _load_module()
    mod.LOG_CHUNK_SIZE = None

    class FakeEvent:
        def __init__(self):
            self.calls = []

        def get_logs(self, from_block=None, to_block=None):
            self.calls.append((from_block, to_block))
            raise Exception("Connection refused")

    event = FakeEvent()

    try:
        mod.get_event_logs(event, 0, 9)
    except Exception as exc:
        assert str(exc) == "Connection refused"
    else:
        raise AssertionError("expected connection error")

    assert event.calls == [(0, 9)]


def test_get_event_logs_logs_http_error_body(capsys):
    mod = _load_module()
    mod.LOG_CHUNK_SIZE = None

    class FakeEvent:
        def get_logs(self, from_block=None, to_block=None):
            response = requests.Response()
            response.status_code = 400
            response._content = b'{"error":"range too wide"}'
            exc = requests.HTTPError("boom", response=response)
            raise exc

    try:
        mod.get_event_logs(FakeEvent(), 0, 9, label="Test Event")
    except requests.HTTPError:
        pass
    else:
        raise AssertionError("expected HTTPError")

    out = capsys.readouterr().out
    assert 'HTTP 400 body' in out
    assert 'range too wide' in out
