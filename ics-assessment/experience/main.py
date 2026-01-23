# Proof of experience

import sys
import csv
import json
import time
from pathlib import Path
from datetime import datetime

import requests
from functools import lru_cache

scores = {
    # TODO exclude slashed
    "eth-staker": 6,
    "stake-cat": 6,
    "obol-techne-base": 4,
    "obol-techne-bronze": 5,
    "obol-techne-silver": 6,
    "ssv-verified": 7,
    "csm-testnet": 4,
    "csm-testnet-circles-verified": 5,
    "csm-mainnet": 6,
    "sdvtm-testnet": 5,
    "sdvtm-mainnet": 7
}

MAINNET_PERFORMANCE_REPORTS = [
    "QmdjvGW2yT8dgvK88sDaA9KFpmxTBxayLP6R1wm5mmzCnP",  # 24048776 block
    "QmaaokMVEPoEPcoMzVN5EtMuauTLfLnGZAkwma7nkpRCK4"   # 24247804 block
]

MIN_SCORE = 5
MAX_SCORE = 8

current_dir = Path(__file__).parent.resolve()

@lru_cache(maxsize=None)
def _read_csv_rows_cached(path_str: str):
    with open(path_str, "r") as f:
        reader = csv.reader(f)
        return tuple(tuple(row) for row in reader)

def is_addresses_in_csv(addresses: set[str], csv_file: str, base_dir=current_dir) -> bool:
    """
    Returns True if any address in `addresses` is found in the first column of the given CSV file.
    The CSV file should contain a single column with addresses or a header with 'Address'.
    """
    for row in _read_csv_rows_cached(str((base_dir / csv_file).resolve())):
        if row and row[0].strip().lower() in addresses:
            print(f"    Found address {row[0]} in {csv_file}")
            return True
    return False


def eth_staker_score(addresses: set[str]) -> int:
    """
    Returns the score for EthStaker solo-staker list if any address is present, otherwise 0.
    """
    if is_addresses_in_csv(addresses, "eth-staker-solo-stakers.csv"):
        return scores["eth-staker"]
    return 0

def stake_cat_score(addresses: set[str]) -> int:
    """
    Returns the score for StakeCat solo-staker list (mainnet, gnosis, rp) if any address is present, otherwise 0.
    """
    is_b = is_addresses_in_csv(addresses, "stake-cat-solo-B.csv")
    is_gnosis = is_addresses_in_csv(addresses, "stake-cat-gnosischain.csv")
    is_rp = is_addresses_in_csv(addresses, "stake-cat-rocketpool-solo-stakers.csv")
    if any([is_b, is_gnosis, is_rp]):
        return scores["stake-cat"]
    return 0

def obol_techne_score(addresses: set[str]) -> int:
    """
    Returns the highest Obol Techne credential score for the given addresses, or 0 if none found.
    """

    if is_addresses_in_csv(addresses, "obol-techne-credentials-silver.csv"):
        return scores["obol-techne-silver"]
    elif is_addresses_in_csv(addresses, "obol-techne-credentials-bronze.csv"):
        return scores["obol-techne-bronze"]
    elif is_addresses_in_csv(addresses, "obol-techne-credentials-base.csv"):
        return scores["obol-techne-base"]
    return 0

def ssv_verified_score(addresses: set[str]) -> int:
    """
    Returns the score for SSV Verified Operators if any address is present, otherwise 0.
    """
    if is_addresses_in_csv(addresses, "ssv-verified-operators.csv"):
        return scores["ssv-verified"]
    return 0


def sdvtm_score(addresses: set[str]) -> int:
    """
    Returns the score for SDVTM participation if any address is eligible, otherwise 0.
    """
    if is_addresses_in_csv(addresses, "sdvtm-mainnet.csv"):
        return scores["sdvtm-mainnet"]
    if is_addresses_in_csv(addresses, "sdvtm-testnet.csv"):
        return scores["sdvtm-testnet"]
    return 0


def csm_score(addresses: set[str]) -> int:
    """
    Returns the score for CSM participation if any address is eligible, otherwise 0.
    This function checks both testnet and mainnet CSM participation.
    """
    mainnet_score = _csm_mainnet_score(addresses)
    if mainnet_score:
        return mainnet_score

    testnet_score = _csm_testnet_score(addresses)
    if testnet_score:
        return testnet_score
    return 0

def _csm_testnet_score(addresses: set[str]) -> int:
    """
    Returns the score for CSM testnet participation using a precomputed file
    produced by _collect_testnet_eligible.py. If any of the addresses belongs to
    an eligible node operator, returns the corresponding testnet score, with an
    extra point for Circles-verified addresses.
    """
    eligible_file = current_dir / "eligible_node_operators_hoodi.json"
    with open(eligible_file, "r") as f:
        data = json.load(f)
        eligible_ids = set(data)

    owners_file = current_dir / "node_operator_owners_hoodi.json"
    with open(owners_file, "r") as f:
        node_operators = json.load(f)  # {no_id: owner}

    holesky_file = current_dir / "eligible_addresses_holesky.json"
    with open(holesky_file, "r") as f:
        eligible_addresses_holesky = set(json.load(f))
    
    eligible_holesky = any(a in eligible_addresses_holesky for a in addresses)

    # Map owner address -> node operator id
    addr_to_id: dict[str, str] = {v.lower(): k for k, v in node_operators.items()}
    found_ids = {addr_to_id[a] for a in addresses if a in addr_to_id}
    if not found_ids and not eligible_holesky:
        return 0
    
    testnet_eligible = False
    if eligible_holesky:
        print("    Found eligible Holesky address among given addresses.")
        testnet_eligible = True
    elif any(no_id in eligible_ids for no_id in found_ids):
        print("    Found node operator IDs for given addresses on Testnet:", ", ".join(found_ids & eligible_ids))
        testnet_eligible = True

    if testnet_eligible:
        # Optional Circles bonus
        circles_file = current_dir.parent / "humanity" / "circle_group_members.csv"
        is_circles_verified = is_addresses_in_csv(addresses, "circle_group_members.csv",
                                                  base_dir=current_dir.parent / "humanity") if circles_file.exists() else False
        if is_circles_verified:
            return scores["csm-testnet-circles-verified"]
        return scores["csm-testnet"]
    return 0

def _csm_mainnet_score(addresses: set[str]) -> int:
    """
    Returns the score for CSM mainnet participation if any address is eligible, otherwise 0.
    """
    if _check_csm_performance_logs(
            addresses,
            "node_operator_owners_mainnet.json",
            MAINNET_PERFORMANCE_REPORTS,
            "Mainnet"  # Network name for logging
    ):
        return scores["csm-mainnet"]
    return 0

def _request_performance_report_uncached(report_file, retries=3, delay=2):
    url = f"https://ipfs.io/ipfs/{report_file}"
    for attempt in range(retries):
        try:
            response = requests.get(url)
            response.raise_for_status()
            return response.json()
        except (requests.HTTPError, requests.JSONDecodeError) as e:
            print(f"Error fetching report {report_file}: {e}")
            if attempt < retries - 1:
                time.sleep(delay)
                continue
            raise e
    raise Exception(f"Failed to fetch report {report_file}")


@lru_cache(maxsize=None)
def _request_performance_report(report_file):
    """LRU-cached IPFS fetch for performance reports keyed by CID."""
    return _request_performance_report_uncached(report_file)


def _check_csm_performance_logs(addresses: set[str], no_owners_file_name, perf_reports, network_name) -> bool:
    """
    Returns True if any address is a node operator with all validators above the threshold in any logs.
    """
    with open(current_dir / no_owners_file_name, 'r') as f:
        node_operators = json.load(f)

    address_to_id = {}
    for no_id, addr in node_operators.items():
        address_to_id[addr.lower()] = no_id

    found_ids = set(address_to_id[a] for a in addresses if a in address_to_id)
    if not found_ids:
        return False
    print(f"    Found node operator IDs for given addresses on {network_name}:", ", ".join(found_ids))

    # If any operator id for the addresses is eligible, continue
    eligible = False
    for report in perf_reports:
        data = _request_performance_report(report)[0]
        threshold = data.get('threshold', 0)
        operators = data.get('operators', {})
        for no_id in found_ids:
            no = operators.get(no_id)
            if not no:
                continue
            all_valid = True
            for v in no.get('validators', {}).values():
                perf = v.get('perf', {})
                assigned = perf.get('assigned', 0)
                included = perf.get('included', 0)
                if assigned == 0:
                    continue
                if included / assigned < threshold:
                    all_valid = False
                    break
            if all_valid:
                report_data = datetime.fromtimestamp(data['blockstamp']['block_timestamp'])
                report_block = data['blockstamp']['block_number']
                print(f"    {network_name} Node Operator {no_id} is eligible in performance report {report} at {report_data} (block {report_block}).")
                eligible = True
                break
            else:
                print(f"    {network_name} Node Operator {no_id} found in report {report} but does not meet performance threshold.")
    return eligible


def main(addresses: set[str]):
    """
    Run experience scoring.
    - `addresses`: set of lowercase addresses.
    """
    print(f"Your addresses: {', '.join(addresses)}")
    print("Checking addresses for Proof of Experience...")

    results: dict[str, int] = {
        "eth-staker": eth_staker_score(addresses),
        "stake-cat": stake_cat_score(addresses),
        "obol-techne": obol_techne_score(addresses),
        "ssv-verified": ssv_verified_score(addresses),
        "sdvtm-testnet/mainnet": sdvtm_score(addresses),
        "csm-testnet/mainnet": csm_score(addresses),
    }

    print("\nResults:")
    total_score = 0
    for key, score in results.items():
        print(f"    {key.replace('-', ' ').title()}: {str(score) + ' ✅' if score else '❌'}")
        if score:
            total_score += score
    print(f"Aggregate score from all sources: {total_score}")
    if total_score < MIN_SCORE:
        print(f"❌ The score is below the minimum required for this category ({MIN_SCORE}).")
        final_score = 0
    else:
        final_score = min(total_score, MAX_SCORE)
        if total_score > MAX_SCORE:
            print(f"Score exceeds the maximum allowed for the category ({MAX_SCORE}). Final score capped at {MAX_SCORE}.")
        print(f"Final Proof of Experience score: {final_score}")
    return final_score

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python main.py <address1> [<address2> ...]")
        exit(1)
    addrs = set([a.strip().lower() for a in sys.argv[1:]])
    main(addrs)
