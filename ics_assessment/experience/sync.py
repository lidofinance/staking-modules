import asyncio
import csv
import json
import time
from pathlib import Path

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
    MAINNET_RPC_URL,
    MAINNET_CUTOFF_BLOCK,
    MAINNET_PERFORMANCE_REPORT_CIDS,
    NODE_OPERATOR_OWNERS_HOODI_PATH,
    NODE_OPERATOR_OWNERS_MAINNET_PATH,
    OBOL_TECHNE_CREDENTIALS,
    SSV_OPERATORS_API_URL,
    SSV_VERIFIED_OPERATORS_PATH,
)
from ics_assessment.sync import (
    FEE_DISTRIBUTOR_EVENT_SIGNATURE,
    NFT_TRANSFER_EVENT_ABI,
    get_event_logs,
    get_raw_logs,
    read_csm_abi,
    write_csv,
    write_lines,
)


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
    rows = [[address] for address in addresses]
    write_csv(SSV_VERIFIED_OPERATORS_PATH, ["Address"], rows)
    print(f"Wrote {len(rows)} SSV verified operators to {SSV_VERIFIED_OPERATORS_PATH}")


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
                try:
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
                finally:
                    queue.task_done()

        workers = [asyncio.create_task(worker()) for _ in range(4)]
        try:
            await queue.join()
        finally:
            for worker_task in workers:
                worker_task.cancel()
            await asyncio.gather(*workers, return_exceptions=True)

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", encoding="utf-8") as file:
            json.dump(dict(sorted(node_operators.items(), key=lambda item: item[0])), file, indent=2)
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


def _operator_meets_report_threshold(operator: dict, threshold: float) -> bool:
    for validator in operator.get("validators", {}).values():
        perf = validator.get("perf", {})
        assigned = perf.get("assigned", 0)
        included = perf.get("included", 0)
        if assigned == 0:
            continue
        if included / assigned < threshold:
            return False
    return True


def _eligible_operator_ids_from_report(report: dict | list[dict]) -> set[str]:
    data = report[0] if isinstance(report, list) else report
    threshold = data.get("threshold", 0)
    operators = data.get("operators", {})
    eligible: set[str] = set()
    for operator_id, operator in operators.items():
        if _operator_meets_report_threshold(operator, threshold):
            eligible.add(str(operator_id))
    return eligible


def sync_mainnet_performance() -> None:
    eligible: set[str] = set()
    for cid in MAINNET_PERFORMANCE_REPORT_CIDS:
        report = request_performance_report(cid)
        eligible.update(_eligible_operator_ids_from_report(report))
        print(f"Processed mainnet performance report {cid}")
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
        evaluate_eligibility_window,
        extract_frame_epochs,
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
        if isinstance(report, list):
            for item in report:
                start_epoch, end_epoch = extract_frame_epochs(item)
                if start_epoch is None or end_epoch is None:
                    continue
                reports_with_meta.append(
                    (ReportMeta(cid=cid, version="v2", start_epoch=start_epoch, end_epoch=end_epoch), item)
                )
            continue
        start_epoch, end_epoch = extract_frame_epochs(report)
        if start_epoch is None or end_epoch is None:
            continue
        reports_with_meta.append(
            (ReportMeta(cid=cid, version="v1", start_epoch=start_epoch, end_epoch=end_epoch), report)
        )

    reports_with_meta.sort(key=lambda item: item[0].start_epoch)
    eligible = sorted(evaluate_eligibility_window(reports_with_meta))
    ELIGIBLE_NODE_OPERATORS_HOODI_PATH.parent.mkdir(parents=True, exist_ok=True)
    with ELIGIBLE_NODE_OPERATORS_HOODI_PATH.open("w", encoding="utf-8") as file:
        json.dump(eligible, file, indent=2)
    print(f"Wrote {len(eligible)} eligible hoodi operators to {ELIGIBLE_NODE_OPERATORS_HOODI_PATH}")
