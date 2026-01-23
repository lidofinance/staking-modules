import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Set, Tuple

from web3 import Web3
import requests


# ----------------------------
# Configurable constants
# ----------------------------

# Fill these constants before running the script.
RPC_URL: str = "http://127.0.0.1:8545"
FEE_DISTRIBUTOR_ADDRESS: str = "0xaCd9820b0A2229a82dc1A0770307ce5522FF3582"
FROM_BLOCK: int = 4980
TO_BLOCK: str | int = 2086013
OUTPUT_PATH: Path = Path(__file__).parent / "eligible_node_operators_hoodi.json"
REQUIRED_PERFORMANCE_WINDOW = 53  # days

# Event signature for DistributionLogUpdated(string logCid)
EVENT_SIGNATURE: str = "DistributionLogUpdated(string)"


def fetch_cids_via_getlogs(w3: Web3, address: str, from_block: int, to_block: int | str) -> List[Tuple[int, str]]:
    topic0 = "0x" +Web3.keccak(text=EVENT_SIGNATURE).hex()
    addr = Web3.to_checksum_address(address)
    logs = w3.eth.get_logs({
        "address": addr,
        "topics": [topic0],
        "fromBlock": from_block,
        "toBlock": to_block,
    })
    out: List[Tuple[int, str]] = []
    for log in logs:
        cid: str = w3.codec.decode(["string"], log.get("data"))[0]
        out.append((log["blockNumber"], cid))
    out.sort(key=lambda x: x[0])
    print(f"Fetched {len(out)} logs from block {from_block} to {to_block}")
    return out


# ----------------------------
# Report fetch + eligibility window logic
# ----------------------------

SECONDS_PER_DAY = 24 * 60 * 60
SLOTS_PER_EPOCH = 32
SECONDS_PER_SLOT = 12
EPOCH_SECONDS = SLOTS_PER_EPOCH * SECONDS_PER_SLOT  # 384s


def request_performance_report(cid: str, retries: int = 3, delay: float = 1.5) -> dict:
    url = f"https://ipfs.io/ipfs/{cid}"
    last_exc: Optional[Exception] = None
    for _ in range(retries):
        try:
            r = requests.get(url, timeout=20)
            r.raise_for_status()
            return r.json()
        except Exception as e:
            last_exc = e
            time.sleep(delay)
    if last_exc:
        raise last_exc
    raise RuntimeError("unexpected: no exception but no data")


def operator_passes_in_report_v1(report: dict, operator_id: str) -> Optional[bool]:
    def _validator_meets_threshold(v: dict, threshold: float) -> bool:
        perf = v.get("perf", {})
        assigned = perf.get("assigned", 0)
        included = perf.get("included", 0)
        if assigned == 0:
            return True
        return (included / assigned) >= threshold

    ops = report.get("operators", {}) or {}
    data = ops.get(operator_id)
    if not data:
        return None
    validators = list((data.get("validators") or {}).values())
    if not validators:
        return None
    threshold = float(report.get("threshold", 0))
    for v in validators:
        if not _validator_meets_threshold(v, threshold):
            return False
    return True


def operator_passes_in_report_v2(report: dict, operator_id: str) -> Optional[bool]:
    ops = report.get("operators", {}) or {}
    data = ops.get(operator_id)
    if not data:
        return None
    validators = list((data.get("validators") or {}).values())
    if not validators:
        return None
    for v in validators:
        dr = int(v.get("distributed_rewards", 0))
        if dr <= 0:
            return False
    return True


@dataclass
class ReportMeta:
    cid: str
    version: str = "v1"
    start_epoch: int = 0
    end_epoch: int = 0


def extract_frame_epochs(report: dict) -> Tuple[Optional[int], Optional[int]]:
    frame = report.get("frame")
    start_e = int(frame[0])
    end_e = int(frame[1])
    return start_e, end_e


def evaluate_eligibility_window(
    reports: List[Tuple[ReportMeta, dict]],
    min_days: int = REQUIRED_PERFORMANCE_WINDOW,
) -> Set[str]:
    """
    Determine operators that accumulate at least min_days of GOOD performance
    in total (cumulative), summing durations of frames where the operator is
    present and GOOD. BAD frames do not break or reset the accumulation — they
    simply contribute 0. EMPTY frames (operator absent or zero validators)
    are tolerated and also contribute 0.

    Rules:
    - GOOD frame: operator present and all relevant validators pass (v1/v2 rules)
      -> add frame duration to the cumulative sum.
    - BAD frame: any validator fails -> add 0, do not reset.
    - EMPTY frame: operator absent or has zero validators -> add 0, do not reset.

    Eligibility is achieved when the cumulative sum of GOOD frame durations
    reaches at least min_days.
    """
    if not reports:
        return set()

    operator_ids: Set[str] = set()
    for _, rep in reports:
        status = rep.get("status") if isinstance(rep, dict) else None
        if isinstance(status, dict):
            operator_ids.update(status.keys())
        else:
            operator_ids.update((rep.get("operators") or {}).keys())

    min_span_secs = min_days * SECONDS_PER_DAY
    eligible: Set[str] = set()

    for op_id in operator_ids:
        good_sum_secs: int = 0

        for meta, rep in reports:
            if meta.version == "v2":
                status = operator_passes_in_report_v2(rep, op_id)
            elif meta.version == "v1":
                status = operator_passes_in_report_v1(rep, op_id)
            else:
                raise ValueError(f"Unknown report version: {meta.version}")

            if status:
                # GOOD: accumulate this frame's duration
                good_sum_secs += (meta.end_epoch - meta.start_epoch) * EPOCH_SECONDS
                if good_sum_secs >= min_span_secs:
                    eligible.add(op_id)
                    break
            # status is False (BAD) or None (EMPTY): contribute 0 and continue
            continue
        else:
            # End of reports; check accumulated sum
            if good_sum_secs >= min_span_secs:
                eligible.add(op_id)

    return eligible


def write_eligible_file(eligible: list, out_path: Path) -> None:
    out_path.write_text(json.dumps(eligible))


def write_frames_meta(frames: list[dict], out_path: Path) -> None:
    out_path.write_text(json.dumps(frames, indent=2))


def main() -> int:
    w3 = Web3(Web3.HTTPProvider(RPC_URL))
    pairs = fetch_cids_via_getlogs(w3, FEE_DISTRIBUTOR_ADDRESS, FROM_BLOCK, TO_BLOCK)
    cids = [cid for _, cid in pairs]

    # Fetch reports and build sorted list by start (epoch preferred)
    reports_with_meta: List[Tuple[ReportMeta, dict]] = []
    for cid in cids:
        rep = request_performance_report(cid)
        # V2: root is list — flatten into individual items
        if isinstance(rep, list):
            for item in rep:
                start_e, end_e = extract_frame_epochs(item)
                if start_e is None or end_e is None:
                    continue
                reports_with_meta.append((ReportMeta(cid=cid, version="v2", start_epoch=start_e, end_epoch=end_e), item))
            continue
        # V1: single dict
        start_e, end_e = extract_frame_epochs(rep)
        if start_e is None or end_e is None:
            continue
        reports_with_meta.append((ReportMeta(cid=cid, version="v1", start_epoch=start_e, end_epoch=end_e), rep))
    # Sort by epoch start
    reports_with_meta.sort(key=lambda x: x[0].start_epoch)

    eligible = evaluate_eligibility_window(reports_with_meta, min_days=REQUIRED_PERFORMANCE_WINDOW)
    write_eligible_file(sorted(eligible), OUTPUT_PATH)
    print(f"Wrote {len(eligible)} eligible operators to {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
