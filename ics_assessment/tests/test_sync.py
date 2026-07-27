import asyncio
import csv
import importlib
import json
import sys
import types

import pytest
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


def _patch_node_owner_web3(monkeypatch, mod, count, failure_counts):
    state = {
        "calls": {},
        "disconnected": False,
    }

    class CountCall:
        async def call(self, block_identifier=None):
            return count

    class OperatorCall:
        def __init__(self, operator_id):
            self.operator_id = operator_id

        async def call(self, block_identifier=None):
            operator_id = self.operator_id
            state["calls"][operator_id] = state["calls"].get(operator_id, 0) + 1
            if state["calls"][operator_id] <= failure_counts.get(operator_id, 0):
                raise ConnectionError(f"failed operator {operator_id}")
            address = f"0x{operator_id + 1:040x}"
            return types.SimpleNamespace(
                extendedManagerPermissions=False,
                managerAddress=address,
                rewardAddress=address,
            )

    functions = types.SimpleNamespace(
        getNodeOperatorsCount=lambda: CountCall(),
        getNodeOperator=lambda operator_id: OperatorCall(operator_id),
    )
    contract = types.SimpleNamespace(functions=functions)

    class Provider:
        async def disconnect(self):
            state["disconnected"] = True

    class FakeAsyncWeb3:
        AsyncHTTPProvider = staticmethod(lambda url: url)

        def __init__(self, provider):
            self.eth = types.SimpleNamespace(contract=lambda **kwargs: contract)
            self.provider = Provider()

    monkeypatch.setattr(mod.experience_jobs, "AsyncWeb3", FakeAsyncWeb3)
    monkeypatch.setattr(mod.experience_jobs, "read_csm_abi", lambda: "[]")
    return state


def _load_module():
    async_web3_stub = types.SimpleNamespace(AsyncHTTPProvider=object)

    class Web3Stub:
        HTTPProvider = staticmethod(lambda url: url)

        def __init__(self, provider):
            self.provider = provider

    web3_stub = types.SimpleNamespace(
        AsyncWeb3=async_web3_stub,
        Web3=Web3Stub,
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

    rows = mod.experience_jobs.SSV_VERIFIED_OPERATORS_PATH.read_text().splitlines()
    assert rows == ["0xabc", "0xdef"]


def test_write_csv_uses_lf_line_endings(tmp_path):
    mod = _load_module()
    path = tmp_path / "out.csv"

    mod.write_csv(path, ["Address", "VoteCount"], [["0xabc", 1]])

    data = path.read_bytes()
    assert b"\r\n" not in data
    assert data == b"Address,VoteCount\n0xabc,1\n"


def test_run_sync_requires_configured_rpc_env():
    mod = _load_module()
    mod.MAINNET_RPC_URL = ""
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


def test_rpc_chain_id_uses_json_rpc_probe(monkeypatch):
    mod = _load_module()
    request = {}

    def fake_post(url, json=None, timeout=None):
        request.update(url=url, json=json, timeout=timeout)
        return DummyResp(data={"jsonrpc": "2.0", "id": 1, "result": "0x88bb0"})

    monkeypatch.setattr(mod.requests, "post", fake_post)

    assert mod._rpc_chain_id("https://hoodi.example") == mod.HOODI_CHAIN_ID
    assert request == {
        "url": "https://hoodi.example",
        "json": {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_chainId",
            "params": [],
        },
        "timeout": 20,
    }


def test_run_sync_verifies_rpc_chain_id(monkeypatch):
    mod = _load_module()
    mod.MAINNET_RPC_URL = "https://mainnet.example"
    called = {"value": False}
    mod.JOBS["aragon"] = lambda: called.__setitem__("value", True)

    monkeypatch.setattr(
        mod,
        "_rpc_chain_id",
        lambda url: 1 if url == mod.MAINNET_RPC_URL else None,
    )

    assert mod.run_sync(["aragon"]) == 0
    assert called["value"] is True


def test_run_sync_rejects_wrong_rpc_chain_id(monkeypatch):
    mod = _load_module()
    mod.MAINNET_RPC_URL = "https://hoodi.example"
    called = {"value": False}
    mod.JOBS["aragon"] = lambda: called.__setitem__("value", True)

    monkeypatch.setattr(
        mod,
        "_rpc_chain_id",
        lambda url: 560048 if url == mod.MAINNET_RPC_URL else None,
    )

    with pytest.raises(
        SystemExit,
        match="expected MAINNET_RPC_URL chain ID 1, got 560048",
    ):
        mod.run_sync(["aragon"])
    assert called["value"] is False


def test_node_owner_sync_writes_complete_snapshot_atomically(monkeypatch, tmp_path):
    mod = _load_module()
    state = _patch_node_owner_web3(
        monkeypatch,
        mod,
        count=5,
        failure_counts={},
    )
    output_path = tmp_path / "owners.json"

    asyncio.run(
        mod.experience_jobs._sync_node_operator_owners_one(
            "https://archive.example",
            "0xcontract",
            123,
            output_path,
        )
    )

    assert state["calls"][1] == 1
    assert state["disconnected"] is True
    assert set(json.loads(output_path.read_text())) == {"0", "1", "2", "3", "4"}
    assert list(tmp_path.glob(".owners.json.*.tmp")) == []


def test_node_owner_sync_failure_preserves_retained_snapshot(monkeypatch, tmp_path):
    mod = _load_module()
    state = _patch_node_owner_web3(
        monkeypatch,
        mod,
        count=5,
        failure_counts={1: 1},
    )
    output_path = tmp_path / "owners.json"
    retained = '{"retained": true}\n'
    output_path.write_text(retained)

    with pytest.raises(
        ConnectionError,
        match="failed operator 1",
    ):
        asyncio.run(
            mod.experience_jobs._sync_node_operator_owners_one(
                "https://archive.example",
                "0xcontract",
                123,
                output_path,
            )
        )

    assert state["calls"][1] == 1
    assert state["disconnected"] is True
    assert output_path.read_text() == retained
    assert list(tmp_path.glob(".owners.json.*.tmp")) == []


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
    mod.experience_jobs.MAINNET_FEE_DISTRIBUTOR_ADDRESS = "0x" + "12" * 20
    mod.experience_jobs.MAINNET_FEE_DISTRIBUTOR_FROM_BLOCK = 100
    mod.experience_jobs.MAINNET_CUTOFF_BLOCK = 200

    def fake_fetch_cids(w3, address, from_block, to_block):
        assert address == mod.experience_jobs.MAINNET_FEE_DISTRIBUTOR_ADDRESS
        assert from_block == 100
        assert to_block == 200
        return ["first", "latest"]

    monkeypatch.setattr(
        mod.experience_jobs,
        "_fetch_cids_via_getlogs",
        fake_fetch_cids,
    )

    reports = iter(
        [
            {
                "frame": [0, 6299],
                "threshold": 0.9,
                "operators": {
                    "42": {
                        "validators": {
                            "v1": {"perf": {"assigned": 500, "included": 400}}
                        }
                    },
                    "43": {
                        "validators": {
                            "v1": {"perf": {"assigned": 6300, "included": 6300}}
                        }
                    },
                },
            },
            {
                "frame": [6300, 12599],
                "threshold": 0.9,
                "operators": {
                    "42": {
                        "validators": {
                            "v1": {"perf": {"assigned": 6250, "included": 6250}}
                        }
                    },
                    "44": {
                        "validators": {
                            "v1": {"perf": {"assigned": 6300, "included": 6300}}
                        }
                    },
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
        mod.experience_jobs.ELIGIBLE_NODE_OPERATORS_MAINNET_PATH.read_text(
            encoding="utf-8"
        )
    ) == ["42"]


def _v2_validator(performance, threshold, assigned=10):
    return {
        "performance": performance,
        "threshold": threshold,
        "attestation_duty": {"assigned": assigned, "included": assigned},
        "proposal_duty": {"assigned": 0, "included": 0},
        "sync_duty": {"assigned": 0, "included": 0},
    }


def test_mainnet_performance_supports_v2_validator_thresholds():
    mod = _load_module()
    report = [
        {
            "frame": [0, 9],
            "operators": {
                "42": {"validators": {"v1": _v2_validator(0.95, 0.9)}},
                "43": {"validators": {"v1": _v2_validator(0.8, 0.9)}},
            },
        }
    ]

    assert mod.experience_jobs._eligible_operator_ids_from_report(report) == {"42"}


def test_mainnet_performance_supports_all_v3_frames():
    mod = _load_module()
    report = {
        "_ver": 1,
        "frames": [
            {
                "frame": [0, 9],
                "operators": {
                    "42": {"validators": {"v1": _v2_validator(0.8, 0.9)}},
                },
            },
            {
                "frame": [10, 19],
                "operators": {
                    "42": {"validators": {"v1": _v2_validator(0.95, 0.9)}},
                },
            },
        ],
    }

    assert mod.experience_jobs._eligible_operator_ids_from_report(report) == {"42"}


def test_mainnet_performance_rejects_missing_v2_fields():
    mod = _load_module()
    validator = _v2_validator(0.95, 0.9)
    del validator["performance"]

    with pytest.raises(KeyError, match="performance"):
        mod.experience_jobs._eligible_operator_ids_from_report(
            [{"frame": [0, 9], "operators": {"42": {"validators": {"v1": validator}}}}]
        )


@pytest.mark.parametrize(
    "report",
    [
        [],
        {"_ver": 1, "frames": []},
    ],
)
def test_mainnet_performance_rejects_empty_or_unknown_reports(report):
    mod = _load_module()

    with pytest.raises(ValueError):
        mod.experience_jobs._eligible_operator_ids_from_report(report)


def test_mainnet_performance_rejects_unsupported_v3_logs_version():
    mod = _load_module()

    with pytest.raises(ValueError, match="unsupported staking module logs version"):
        mod.experience_jobs._eligible_operator_ids_from_report(
            {"_ver": 2, "frames": [{"frame": [0, 9], "operators": {}}]}
        )


def test_mainnet_performance_requires_duty_evidence():
    mod = _load_module()
    report = [
        {
            "frame": [0, 9],
            "operators": {
                "42": {"validators": {"v1": _v2_validator(0, 0, assigned=0)}},
                "43": {"validators": {}},
            },
        }
    ]

    assert mod.experience_jobs._eligible_operator_ids_from_report(report) == set()


def test_mainnet_eligibility_requires_30_days_and_latest_performance():
    mod = _load_module()
    reports = [
        [
            {
                "frame": [0, 6299],
                "operators": {
                    "42": {"validators": {"v1": _v2_validator(0.8, 0.9, assigned=450)}},
                    "43": {"validators": {"v1": _v2_validator(1, 0.9, assigned=449)}},
                    "44": {"validators": {"v1": _v2_validator(1, 0.9, assigned=6300)}},
                },
            }
        ],
        [
            {
                "frame": [6300, 12599],
                "operators": {
                    "42": {"validators": {"v1": _v2_validator(1, 0.9, assigned=6300)}},
                    "43": {"validators": {"v1": _v2_validator(1, 0.9, assigned=6300)}},
                    "45": {"validators": {"v1": _v2_validator(1, 0.9, assigned=6300)}},
                },
            }
        ],
    ]

    assert mod.experience_jobs._eligible_mainnet_operator_ids(reports) == {"42"}


def test_mainnet_activity_qualification_is_permanent():
    mod = _load_module()
    reports = [
        [
            {
                "frame": [0, 6299],
                "operators": {
                    "42": {"validators": {"v1": _v2_validator(0.8, 0.9, assigned=450)}},
                },
            }
        ],
        [
            {
                "frame": [6300, 12599],
                "operators": {
                    "42": {"validators": {"v1": _v2_validator(1, 0.9, assigned=6300)}},
                },
            }
        ],
        [{"frame": [12600, 18899], "operators": {}}],
    ]
    frames = mod.experience_jobs.parse_performance_frames(reports)

    assert mod.experience_jobs._historically_active_operator_ids(frames[:1]) == set()
    assert mod.experience_jobs._historically_active_operator_ids(frames[:2]) == {"42"}
    assert mod.experience_jobs._historically_active_operator_ids(frames) == {"42"}


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
