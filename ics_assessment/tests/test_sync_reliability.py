"""Exercise Circles batching through actual web3 encoding and decoding."""

import json

import pytest
from web3 import Web3, HTTPProvider
from web3.exceptions import Web3RPCError

from ics_assessment import sync, config


START = 41_502_657
END = 48_135_713
HUB = Web3.to_checksum_address("0x" + "12" * 20)
TRUSTER = Web3.to_checksum_address(config.GROUP_ADDRESS)
TOPIC = Web3.to_hex(Web3.keccak(text="Trust(address,address,uint256)"))


def address(n):
    return Web3.to_checksum_address(f"0x{n:040x}")


def topic_address(addr):
    return "0x" + addr[2:].lower().zfill(64)


def log(block, n, truster=TRUSTER, trustee=None):
    return {
        "address": HUB,
        "topics": [TOPIC, topic_address(truster), topic_address(trustee or address(n))],
        "data": "0x" + (2**64 - 1).to_bytes(32, "big").hex(),
        "blockNumber": hex(block),
        "blockHash": "0x" + block.to_bytes(32, "big").hex(),
        "transactionHash": "0x" + n.to_bytes(32, "big").hex(),
        "transactionIndex": "0x0",
        "logIndex": hex(n),
        "removed": False,
    }


class RpcFixture:
    """Fake only HTTP response bytes, retaining actual web3 encoding/decoding."""

    def __init__(self, monkeypatch, limit=None):
        self.provider = HTTPProvider("https://rpc.example.invalid")
        self.w3 = Web3(self.provider)
        self.event = self.w3.eth.contract(address=HUB, abi=sync.HUB_ABI).events.Trust()
        self.requests = []
        self.limit = limit
        self.filter_params = None
        self.fault = None
        blocks = [
            START,
            START + 9_999,
            START + 10_000,
            START + 99_999,
            START + 100_000,
            END - 1,
            END,
        ]
        self.logs = [log(b, n) for n, b in enumerate(blocks, 1)]
        self.logs += [
            log(START - 1, 8),
            log(END + 1, 9),
            log(START + 1, 10, truster=address(999)),
        ]
        monkeypatch.setattr(
            self.provider._request_session_manager, "make_post_request", self.post
        )

    def post(self, url, data, **kwargs):
        req = json.loads(data)
        self.requests.append(req)
        method, params = req["method"], req["params"]
        if self.fault and method == "eth_getLogs":
            return self.fault
        if method == "eth_chainId":
            result = "0x64"
        elif method == "eth_call":
            if params[0]["to"].lower() == TRUSTER.lower():
                result = Web3.to_hex(self.w3.codec.encode(["address"], [HUB]))
            else:
                owner = address(int(params[0]["to"], 16) + 1000)
                result = Web3.to_hex(
                    self.w3.codec.encode(
                        ["address[]"], [[owner, config.DEFAULT_SAFE_OWNER]]
                    )
                )
        elif method == "eth_newFilter":
            self.filter_params = params[0]
            result = "0x1"
        elif method in ("eth_getLogs", "eth_getFilterLogs"):
            f = params[0] if method == "eth_getLogs" else self.filter_params
            start, end = int(f["fromBlock"], 16), int(f["toBlock"], 16)
            if self.limit and end - start + 1 > self.limit:
                return json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": req["id"],
                        "error": {
                            "code": -32062,
                            "message": "Block range is too large",
                        },
                    }
                ).encode()

            def matches(entry):
                if not start <= int(entry["blockNumber"], 16) <= end:
                    return False
                addresses = (
                    f["address"] if isinstance(f["address"], list) else [f["address"]]
                )
                if entry["address"].lower() not in [
                    value.lower() for value in addresses
                ]:
                    return False
                for actual, wanted in zip(entry["topics"], f["topics"]):
                    if wanted is None:
                        continue
                    if actual not in (wanted if isinstance(wanted, list) else [wanted]):
                        return False
                return True

            result = [entry for entry in reversed(self.logs) if matches(entry)]
        else:
            raise AssertionError(f"unexpected RPC method {method}")
        return json.dumps(
            {"jsonrpc": "2.0", "id": req["id"], "result": result}
        ).encode()

    def ranges(self):
        return [
            (int(r["params"][0]["fromBlock"], 16), int(r["params"][0]["toBlock"], 16))
            for r in self.requests
            if r["method"] == "eth_getLogs"
        ]


def rpc_error(code, message):
    return json.dumps(
        {"jsonrpc": "2.0", "id": 1, "error": {"code": code, "message": message}}
    ).encode()


def fetch(rpc, end=END):
    return sync.get_event_logs(
        rpc.event, START, end, argument_filters={"truster": TRUSTER}
    )


def setup_circles(monkeypatch, tmp_path, rpc):
    monkeypatch.setattr(sync, "LOG_CHUNK_SIZE", None)

    def factory(provider):
        return rpc.w3

    factory.HTTPProvider = lambda url: rpc.provider
    factory.to_checksum_address = Web3.to_checksum_address
    factory.to_hex = Web3.to_hex
    monkeypatch.setattr(sync.humanity_jobs, "Web3", factory)
    monkeypatch.setattr(sync.humanity_jobs, "GNOSIS_CUTOFF_BLOCK", END)
    members = tmp_path / "members.csv"
    monkeypatch.setattr(sync.humanity_jobs, "CIRCLE_GROUP_MEMBERS_PATH", members)
    monkeypatch.setattr(sync, "_rpc_chain_id", lambda url: 100)
    return members


def test_migration_preserves_indexed_filter_and_decoded_events(monkeypatch):
    rpc = RpcFixture(monkeypatch)
    old = rpc.event.create_filter(
        from_block=START, to_block=END, argument_filters={"truster": TRUSTER}
    ).get_all_entries()
    monkeypatch.setattr(sync, "LOG_CHUNK_SIZE", END - START + 1)
    new = fetch(rpc)
    assert rpc.filter_params == rpc.requests[-1]["params"][0]
    order = lambda event: (event.blockNumber, event.logIndex)
    assert sorted(old, key=order) == sorted(new, key=order)
    assert len(new) == 7
    assert {e.blockNumber for e in new} >= {START, END}


def test_default_handles_full_round_under_100k_limit(monkeypatch):
    rpc = RpcFixture(monkeypatch, limit=100_000)
    monkeypatch.setattr(sync, "LOG_CHUNK_SIZE", None)
    assert len(fetch(rpc)) == 7
    assert len(rpc.ranges()) == 664
    assert max(end - start + 1 for start, end in rpc.ranges()) == 10_000


@pytest.mark.parametrize("chunk_size", [None, 10000, 50000])
def test_circles_cli_writes_the_same_owners_at_the_cutoff(monkeypatch, tmp_path, chunk_size):
    rpc = RpcFixture(monkeypatch, limit=100_000)
    members = setup_circles(monkeypatch, tmp_path, rpc)
    args = [] if chunk_size is None else ["--chunk-size", str(chunk_size)]
    assert sync.main(args + ["circles"]) == 0
    assert max(end - start + 1 for start, end in rpc.ranges()) == (chunk_size or 10000)
    assert members.read_text().splitlines() == [
        address(n + 1000).lower() for n in range(1, 8)
    ]
    assert all(
        int(r["params"][1], 16) == END
        for r in rpc.requests
        if r["method"] == "eth_call"
    )
    assert not any(r["method"] == "eth_newFilter" for r in rpc.requests)


def test_failed_circles_chunk_does_not_replace_retained_members(monkeypatch, tmp_path):
    rpc = RpcFixture(monkeypatch)
    members = setup_circles(monkeypatch, tmp_path, rpc)
    members.write_text("retained\n")
    rpc.fault = rpc_error(-32602, "invalid filter")
    with pytest.raises(Web3RPCError):
        sync.main(["circles"])
    assert members.read_text() == "retained\n"


def test_raw_logs_use_default_chunks_and_preserve_filters(monkeypatch):
    rpc = RpcFixture(monkeypatch, limit=100_000)
    monkeypatch.setattr(sync, "LOG_CHUNK_SIZE", None)
    logs = sync.get_raw_logs(
        rpc.w3, {"address": HUB, "topics": [TOPIC, topic_address(TRUSTER)]}, START, END
    )
    assert len(logs) == 7
    assert len(rpc.ranges()) == 664
    assert all(end - start + 1 <= 10000 for start, end in rpc.ranges())


def test_provider_limit_error_propagates_without_retry_or_resizing(monkeypatch):
    rpc = RpcFixture(monkeypatch, limit=3000)
    monkeypatch.setattr(sync, "LOG_CHUNK_SIZE", 10000)
    with pytest.raises(Web3RPCError):
        fetch(rpc, START + 20000)
    assert rpc.ranges() == [(START, START + 9999)]
