#!/usr/bin/env python3
import argparse
import csv
import os
import sys
from pathlib import Path
from typing import Iterable

import requests


TRANSFER_EVENT_ABI = [
    {
        "type": "event",
        "name": "Transfer",
        "inputs": [
            {"name": "from", "type": "address", "indexed": True},
            {"name": "to", "type": "address", "indexed": True},
            {"name": "value", "type": "uint256", "indexed": False},
        ],
        "anonymous": False,
    }
]

NFT_TRANSFER_EVENT_ABI = [
    {
        "type": "event",
        "name": "Transfer",
        "inputs": [
            {"name": "from", "type": "address", "indexed": True},
            {"name": "to", "type": "address", "indexed": True},
            {"name": "tokenId", "type": "uint256", "indexed": True},
        ],
        "anonymous": False,
    }
]

GROUP_ABI = """[{"inputs": [], "name": "HUB", "outputs": [{"internalType": "address", "name": "", "type": "address"}], "stateMutability": "view", "type": "function"}]"""
SAFE_ABI = """[{"inputs": [], "name": "getOwners", "outputs": [{"internalType": "address[]", "name": "", "type": "address[]"}], "stateMutability": "view", "type": "function"}]"""
HUB_ABI = """[{"anonymous": false, "inputs": [{"indexed": true, "internalType": "address", "name": "truster", "type": "address"}, {"indexed": true, "internalType": "address", "name": "trustee", "type": "address"}, {"indexed": false, "internalType": "uint256", "name": "expiryTime", "type": "uint256"}], "name": "Trust", "type": "event"}]"""
ARAGON_ABI = '[{"anonymous":false,"inputs":[{"indexed":true,"name":"voteId","type":"uint256"},{"indexed":true,"name":"voter","type":"address"},{"indexed":false,"name":"supports","type":"bool"},{"indexed":false,"name":"stake","type":"uint256"}],"name":"CastVote","type":"event"}]'
FEE_DISTRIBUTOR_EVENT_SIGNATURE = "DistributionLogUpdated(string)"
LOG_CHUNK_SIZE = int(os.getenv("ICS_SYNC_CHUNK_SIZE")) if os.getenv("ICS_SYNC_CHUNK_SIZE") else None


def write_lines(path: Path, values: Iterable[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as file:
        for value in sorted({v.lower() for v in values}):
            file.write(f"{value}\n")


def write_csv(path: Path, header: list[str], rows: list[list[str | int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.writer(file, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def read_csm_abi() -> str:
    abi_path = (
        Path(__file__).resolve().parent.parent
        / "artifacts"
        / "mainnet"
        / "ics"
        / "abi"
        / "csm_abi.json"
    )
    return abi_path.read_text(encoding="utf-8")


def _format_block_range(from_block: int, to_block: int) -> str:
    return f"{from_block:,}-{to_block:,}"


def _validate_chunk_size(chunk_size: int | None) -> int | None:
    if chunk_size is None:
        return None
    if chunk_size <= 0:
        raise ValueError("chunk size must be positive")
    return chunk_size


def _fetch_logs(
    fetch_logs,
    from_block: int,
    to_block: int,
    label: str,
    chunk_size: int | None,
):
    def run_fetch(start: int, end: int):
        try:
            return fetch_logs(start, end)
        except requests.HTTPError as exc:
            response = exc.response
            if response is not None:
                body = response.text.strip()
                if body:
                    print(
                        f"[sync] {label}: HTTP {response.status_code} body for "
                        f"{_format_block_range(start, end)}: {body}"
                    )
            raise

    if chunk_size is None or (to_block - from_block + 1) <= chunk_size:
        print(f"[sync] {label}: fetching {_format_block_range(from_block, to_block)}")
        logs = run_fetch(from_block, to_block)
        print(f"[sync] {label}: fetched {len(logs)} log(s) for {_format_block_range(from_block, to_block)}")
        return logs

    logs = []
    total_chunks = ((to_block - from_block) // chunk_size) + 1
    start = from_block
    chunk_index = 1
    while start <= to_block:
        end = min(start + chunk_size - 1, to_block)
        print(
            f"[sync] {label}: fetching chunk {chunk_index}/{total_chunks} "
            f"({_format_block_range(start, end)})"
        )
        chunk_logs = run_fetch(start, end)
        print(
            f"[sync] {label}: fetched {len(chunk_logs)} log(s) for chunk "
            f"{chunk_index}/{total_chunks} ({_format_block_range(start, end)})"
        )
        logs.extend(chunk_logs)
        start = end + 1
        chunk_index += 1
    return logs


def get_event_logs(event, from_block: int, to_block: int, label: str = "event logs"):
    return _fetch_logs(
        lambda start, end: event.get_logs(from_block=start, to_block=end),
        from_block,
        to_block,
        label,
        _validate_chunk_size(LOG_CHUNK_SIZE),
    )


def get_raw_logs(w3, filter_params: dict, from_block: int, to_block: int, label: str = "raw logs"):
    return _fetch_logs(
        lambda start, end: w3.eth.get_logs(
            {
                **filter_params,
                "fromBlock": start,
                "toBlock": end,
            }
        ),
        from_block,
        to_block,
        label,
        _validate_chunk_size(LOG_CHUNK_SIZE),
    )

from ics_assessment.engagement import sync as engagement_jobs
from ics_assessment.experience import sync as experience_jobs
from ics_assessment.humanity import sync as humanity_jobs


JOB_ORDER = [
    "aragon",
    "snapshot",
    "galxe",
    "gitpoap",
    "protocol-guild",
    "obol-techne",
    "ssv-verified",
    "node-owners",
    "mainnet-performance",
    "hoodi-eligible",
    "circles",
]

JOBS = {
    "aragon": engagement_jobs.sync_aragon,
    "snapshot": engagement_jobs.sync_snapshot,
    "galxe": engagement_jobs.sync_galxe,
    "gitpoap": engagement_jobs.sync_gitpoap,
    "protocol-guild": engagement_jobs.sync_protocol_guild,
    "obol-techne": experience_jobs.sync_obol_techne,
    "ssv-verified": experience_jobs.sync_ssv_verified,
    "node-owners": experience_jobs.sync_node_owners,
    "mainnet-performance": experience_jobs.sync_mainnet_performance,
    "hoodi-eligible": experience_jobs.sync_hoodi_eligible,
    "circles": humanity_jobs.sync_circles,
}

def _target_rpc_values(target: str) -> list[tuple[str, str]]:
    if target == "aragon" or target == "protocol-guild":
        return [("MAINNET_RPC_URL", engagement_jobs.MAINNET_RPC_URL)]
    if target == "obol-techne":
        return [
            ("ARBITRUM_RPC_URL", experience_jobs.ARBITRUM_RPC_URL),
            ("MAINNET_RPC_URL", experience_jobs.MAINNET_RPC_URL),
        ]
    if target == "node-owners":
        return [
            ("MAINNET_ARCHIVE_RPC_URL", experience_jobs.MAINNET_ARCHIVE_RPC_URL),
            ("HOODI_ARCHIVE_RPC_URL", experience_jobs.HOODI_ARCHIVE_RPC_URL),
        ]
    if target == "hoodi-eligible":
        return [("HOODI_RPC_URL", experience_jobs.HOODI_RPC_URL)]
    return []


def _ensure_required_rpcs(target: str) -> None:
    rpc_values = _target_rpc_values(target)
    missing = [env_var for env_var, url in rpc_values if not url]
    if missing:
        raise SystemExit(
            f"Sync target '{target}' requires configured RPC URLs. "
            f"Export {', '.join(missing)} before running sync."
        )


def _expand_targets(targets: list[str]) -> list[str]:
    expanded: list[str] = []
    for target in targets or ["all"]:
        if target == "all":
            expanded.extend(JOB_ORDER)
            continue
        if target not in JOBS:
            raise SystemExit(f"Unknown sync target: {target}")
        expanded.append(target)
    seen = set()
    ordered = []
    for target in expanded:
        if target not in seen:
            seen.add(target)
            ordered.append(target)
    return ordered


def run_sync(targets: list[str], chunk_size: int | None = None) -> int:
    global LOG_CHUNK_SIZE
    LOG_CHUNK_SIZE = _validate_chunk_size(chunk_size if chunk_size is not None else LOG_CHUNK_SIZE)

    targets = _expand_targets(targets)
    total = len(targets)
    for index, target in enumerate(targets, start=1):
        print(f"[sync] [{index}/{total}] starting {target}")
        _ensure_required_rpcs(target)
        JOBS[target]()
        print(f"[sync] [{index}/{total}] finished {target}")
    return 0


def main(argv: list[str] | None = None, *, chunk_size: int | None = None) -> int:
    parser = argparse.ArgumentParser(description="Sync ICS assessment snapshot sources.")
    parser.add_argument("--chunk-size", type=int, default=chunk_size, help="Optional log-fetch block chunk size")
    parser.add_argument("targets", nargs="*", help="Sync target(s) or 'all'")
    args = parser.parse_args(argv)
    return run_sync(args.targets, chunk_size=args.chunk_size)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
