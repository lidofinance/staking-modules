import asyncio
import json
import time
from pathlib import Path
from tempfile import NamedTemporaryFile

import requests
from web3 import AsyncWeb3, Web3

from ics_assessment.config import (
    CSM_HOODI_ADDRESS,
    CSM_MAINNET_ADDRESS,
    ELIGIBLE_NODE_OPERATORS_HOODI_PATH,
    ELIGIBLE_NODE_OPERATORS_MAINNET_PATH,
    HOODI_ARCHIVE_RPC_URL,
    HOODI_CUTOFF_BLOCK,
    HOODI_FEE_DISTRIBUTOR_ADDRESS,
    HOODI_FEE_DISTRIBUTOR_FROM_BLOCK,
    HOODI_RPC_URL,
    MAINNET_ARCHIVE_RPC_URL,
    MAINNET_CUTOFF_BLOCK,
    MAINNET_FEE_DISTRIBUTOR_ADDRESS,
    MAINNET_FEE_DISTRIBUTOR_FROM_BLOCK,
    MAINNET_RPC_URL,
    NODE_OPERATOR_OWNERS_HOODI_PATH,
    NODE_OPERATOR_OWNERS_MAINNET_PATH,
    OBOL_TECHNE_CREDENTIALS,
    REQUIRED_ACTIVITY_WINDOW_MAINNET,
    SSV_OPERATORS_API_URL,
    SSV_VERIFIED_OPERATORS_PATH,
)
from ics_assessment.experience.performance import (
    PerformanceFrame,
    parse_performance_frames,
    parse_performance_report,
)
from ics_assessment.sync import (
    FEE_DISTRIBUTOR_EVENT_SIGNATURE,
    NFT_TRANSFER_EVENT_ABI,
    get_event_logs,
    get_raw_logs,
    read_csm_abi,
    write_lines,
)

SECONDS_PER_DAY = 24 * 60 * 60
SECONDS_PER_EPOCH = 32 * 12


def sync_obol_techne() -> None:
    for credential in OBOL_TECHNE_CREDENTIALS:
        w3 = Web3(Web3.HTTPProvider(credential["rpc_url"]))
        contract = w3.eth.contract(
            address=w3.to_checksum_address(str(credential["contract_address"])),
            abi=NFT_TRANSFER_EVENT_ABI,
        )
        logs = get_event_logs(
            contract.events.Transfer,
            int(credential["from_block"]),
            int(credential["to_block"]),
            label=f"Obol Techne {credential['name']} Transfer",
        )
        holders = {log.args.to.lower() for log in logs}
        write_lines(Path(credential["output_path"]), holders)
        print(
            f"Wrote {len(holders)} Obol Techne {credential['name']} holders to {credential['output_path']}"
        )


def sync_ssv_verified() -> None:
    response = requests.get(SSV_OPERATORS_API_URL, timeout=20)
    response.raise_for_status()
    items = response.json()["operators"]
    addresses = sorted({item["owner_address"].lower() for item in items})
    write_lines(SSV_VERIFIED_OPERATORS_PATH, addresses)
    print(f"Wrote {len(addresses)} SSV verified operators to {SSV_VERIFIED_OPERATORS_PATH}")


async def _sync_node_operator_owners_one(
    provider_url: str,
    contract_address: str,
    reference_block: int,
    output_path: Path,
) -> None:
    w3 = AsyncWeb3(AsyncWeb3.AsyncHTTPProvider(provider_url))
    try:
        contract = w3.eth.contract(
            address=contract_address,
            abi=read_csm_abi(),
            decode_tuples=True,
        )

        node_operators: dict[int, str] = {}
        count = await contract.functions.getNodeOperatorsCount().call(
            block_identifier=reference_block
        )
        processed = 0
        progress_lock = asyncio.Lock()

        print(
            f"[sync] node owners {output_path.name}: fetching {count} operator(s) "
            f"at block {reference_block}"
        )

        queue: asyncio.Queue[int] = asyncio.Queue()
        for i in range(count):
            await queue.put(i)

        async def worker() -> None:
            nonlocal processed
            while True:
                try:
                    i = queue.get_nowait()
                except asyncio.QueueEmpty:
                    break
                node_operator = await contract.functions.getNodeOperator(i).call(
                    block_identifier=reference_block
                )
                owner = (
                    node_operator.managerAddress
                    if node_operator.extendedManagerPermissions
                    else node_operator.rewardAddress
                )
                node_operators[i] = owner.lower()
                async with progress_lock:
                    processed += 1
                    if processed % 100 == 0 or processed == count:
                        print(
                            f"[sync] node owners {output_path.name}: processed "
                            f"{processed}/{count}"
                        )

        workers = [asyncio.create_task(worker()) for _ in range(4)]
        try:
            await asyncio.gather(*workers)
        except BaseException:
            for worker_task in workers:
                worker_task.cancel()
            await asyncio.gather(*workers, return_exceptions=True)
            raise

        expected_ids = set(range(count))
        actual_ids = set(node_operators)
        if actual_ids != expected_ids:
            missing = sorted(expected_ids - actual_ids)
            unexpected = sorted(actual_ids - expected_ids)
            raise RuntimeError(
                f"Incomplete node owner snapshot at block {reference_block}: "
                f"missing IDs {missing}, unexpected IDs {unexpected}"
            )

        output_path.parent.mkdir(parents=True, exist_ok=True)
        temp_path: Path | None = None
        try:
            with NamedTemporaryFile(
                "w",
                encoding="utf-8",
                dir=output_path.parent,
                prefix=f".{output_path.name}.",
                suffix=".tmp",
                delete=False,
            ) as file:
                temp_path = Path(file.name)
                json.dump(
                    dict(sorted(node_operators.items(), key=lambda item: item[0])),
                    file,
                    indent=2,
                )
                file.write("\n")
            temp_path.replace(output_path)
        finally:
            if temp_path is not None:
                temp_path.unlink(missing_ok=True)
        print(f"Wrote {len(node_operators)} node operators to {output_path}")
    finally:
        await w3.provider.disconnect()


def sync_node_owners() -> None:
    asyncio.run(
        _sync_node_operator_owners_one(
            MAINNET_ARCHIVE_RPC_URL,
            CSM_MAINNET_ADDRESS,
            MAINNET_CUTOFF_BLOCK,
            NODE_OPERATOR_OWNERS_MAINNET_PATH,
        )
    )
    asyncio.run(
        _sync_node_operator_owners_one(
            HOODI_ARCHIVE_RPC_URL,
            CSM_HOODI_ADDRESS,
            HOODI_CUTOFF_BLOCK,
            NODE_OPERATOR_OWNERS_HOODI_PATH,
        )
    )


def _fetch_cids_via_getlogs(w3: Web3, address: str, from_block: int, to_block: int) -> list[str]:
    topic0 = "0x" + Web3.keccak(text=FEE_DISTRIBUTOR_EVENT_SIGNATURE).hex()
    logs = get_raw_logs(
        w3,
        {
            "address": Web3.to_checksum_address(address),
            "topics": [topic0],
        },
        from_block,
        to_block,
        label="Fee distributor DistributionLogUpdated",
    )
    pairs = []
    for log in logs:
        cid = w3.codec.decode(["string"], log.get("data"))[0]
        pairs.append((log["blockNumber"], cid))
    pairs.sort(key=lambda item: item[0])
    return [cid for _, cid in pairs]


def request_performance_report(cid: str) -> dict | list[dict]:
    url = f"https://ipfs.io/ipfs/{cid}"
    last_exc: Exception | None = None
    for _ in range(3):
        try:
            response = requests.get(url, timeout=20)
            response.raise_for_status()
            return response.json()
        except Exception as exc:
            last_exc = exc
            time.sleep(1.5)
    if last_exc is not None:
        raise last_exc
    raise RuntimeError("unexpected: no exception but no data")


def _eligible_operator_ids_from_report(report: dict | list[dict]) -> set[str]:
    return set().union(
        *(frame.eligible_operator_ids for frame in parse_performance_report(report))
    )


def _historically_active_operator_ids(frames: list[PerformanceFrame]) -> set[str]:
    required_epochs = (
        REQUIRED_ACTIVITY_WINDOW_MAINNET * SECONDS_PER_DAY // SECONDS_PER_EPOCH
    )
    assigned_epochs_by_operator: dict[str, int] = {}
    for frame in frames:
        for operator_id, assigned_epochs in frame.assigned_epochs_by_operator.items():
            assigned_epochs_by_operator[operator_id] = (
                assigned_epochs_by_operator.get(operator_id, 0) + assigned_epochs
            )
    return {
        operator_id
        for operator_id, assigned_epochs in assigned_epochs_by_operator.items()
        if assigned_epochs >= required_epochs
    }


def _eligible_mainnet_operator_ids(reports: list[dict | list[dict]]) -> set[str]:
    frames = parse_performance_frames(reports)
    historically_active = _historically_active_operator_ids(frames)
    return historically_active & frames[-1].eligible_operator_ids


def sync_mainnet_performance() -> None:
    w3 = Web3(Web3.HTTPProvider(MAINNET_RPC_URL))
    cids = _fetch_cids_via_getlogs(
        w3,
        MAINNET_FEE_DISTRIBUTOR_ADDRESS,
        MAINNET_FEE_DISTRIBUTOR_FROM_BLOCK,
        MAINNET_CUTOFF_BLOCK,
    )
    reports: list[dict | list[dict]] = []
    for cid in cids:
        report = request_performance_report(cid)
        reports.append(report)
        print(f"Processed mainnet performance report {cid}")
    eligible = _eligible_mainnet_operator_ids(reports)
    ELIGIBLE_NODE_OPERATORS_MAINNET_PATH.parent.mkdir(parents=True, exist_ok=True)
    with ELIGIBLE_NODE_OPERATORS_MAINNET_PATH.open("w", encoding="utf-8") as file:
        json.dump(sorted(eligible, key=int), file, indent=2)
    print(
        f"Wrote {len(eligible)} eligible mainnet operators to "
        f"{ELIGIBLE_NODE_OPERATORS_MAINNET_PATH}"
    )


def sync_hoodi_eligible() -> None:
    from ics_assessment.experience.sync_hoodi import (
        ReportMeta,
        append_report_frames,
        evaluate_eligibility_window,
    )

    w3 = Web3(Web3.HTTPProvider(HOODI_RPC_URL))
    cids = _fetch_cids_via_getlogs(
        w3,
        HOODI_FEE_DISTRIBUTOR_ADDRESS,
        HOODI_FEE_DISTRIBUTOR_FROM_BLOCK,
        HOODI_CUTOFF_BLOCK,
    )

    reports_with_meta: list[tuple[ReportMeta, dict]] = []
    for cid in cids:
        report = request_performance_report(cid)
        append_report_frames(reports_with_meta, cid, report)

    reports_with_meta.sort(key=lambda item: item[0].start_epoch)
    eligible = sorted(evaluate_eligibility_window(reports_with_meta))
    ELIGIBLE_NODE_OPERATORS_HOODI_PATH.parent.mkdir(parents=True, exist_ok=True)
    with ELIGIBLE_NODE_OPERATORS_HOODI_PATH.open("w", encoding="utf-8") as file:
        json.dump(eligible, file, indent=2)
    print(f"Wrote {len(eligible)} eligible hoodi operators to {ELIGIBLE_NODE_OPERATORS_HOODI_PATH}")
