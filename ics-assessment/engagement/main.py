# Proof of engagement
import csv
import json
import os
import sys
from datetime import datetime
from functools import lru_cache
from pathlib import Path
from typing import Any

import requests
from web3 import Web3

scores = {
    "snapshot-vote": 1,
    "aragon-vote": 2,
    "galxe-score-4-10": 4,
    "galxe-score-above-10": 5,
    "git-poap": 2,
    "high-signal-30": 2,
    "high-signal-40": 3,
    "high-signal-60": 4,
    "high-signal-80": 5,
}

MIN_SCORE = 2
MAX_SCORE = 7

SNAPSHOT_VOTE_TIMESTAMP = 1769122800
REQUIRED_SNAPSHOT_VOTES = 3
REQUIRED_SNAPSHOT_VP = 100  # 100 LDO
REQUIRED_ARAGON_VOTES = 2

HIGH_SIGNAL_START_DATE = datetime(2025, 9, 1)  # YYYY, MM, DD
HIGH_SIGNAL_END_DATE = datetime(2026, 1, 23)  # YYYY, MM, DD

current_dir = Path(__file__).parent.resolve()
CACHE_DIR = current_dir / ".cache"


@lru_cache(maxsize=None)
def _read_cache_file(filename: str) -> Any | None:
    cache_path = CACHE_DIR / filename
    if cache_path.exists():
        with cache_path.open("r", encoding="utf-8") as cache_file:
            return json.load(cache_file)
    return None


def _write_cache_file(filename: str, data: Any) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE_DIR / filename
    with cache_path.open("w", encoding="utf-8") as cache_file:
        json.dump(data, cache_file)

@lru_cache(maxsize=None)
def _read_csv_dicts_cached(path_str: str):
    with open(path_str, "r") as f:
        reader = csv.DictReader(f)
        return tuple(tuple(item.items()) for item in reader)


@lru_cache(maxsize=None)
def _read_csv_rows_cached(path_str: str):
    with open(path_str, "r") as f:
        reader = csv.reader(f)
        return tuple(tuple(row) for row in reader)


def snapshot_vote(addresses: set[str]) -> int:
    """
    Check if the address has participated in Snapshot votes.
    """
    lido_space = "lido-snapshot.eth"
    query = """
    query Votes {
      votes (
        first: %s
        where: {
          space: "%s"
          voter_in: [%s]
          vp_gt: %s
          created_lt: %s
        }
      ) {
        id
        voter
        created
        choice
        space {
          id
        }
      }
    }
    """ % (
        REQUIRED_SNAPSHOT_VOTES,
        lido_space,
        ", ".join(map(lambda x: '"' + x + '"', addresses)),
        REQUIRED_SNAPSHOT_VP,
        SNAPSHOT_VOTE_TIMESTAMP
    )
    response = requests.post("https://hub.snapshot.org/graphql", json={"query": query})
    response.raise_for_status()
    result = response.json()
    if "errors" in result:
        raise Exception(f"Error fetching Snapshot votes: {result['errors']}", query)
    votes_count = len(result["data"]["votes"])
    if votes_count >= REQUIRED_SNAPSHOT_VOTES:
        print(f"    Found {votes_count} Snapshot votes (in sum) for given addresses")
        return scores["snapshot-vote"]
    return 0


def aragon_vote(addresses: set[str]) -> int:
    """
    Check if the address has participated in Aragon votes.
    """

    rows = map(dict, _read_csv_dicts_cached(str(current_dir / "aragon_voters.csv")))
    total_votes_count = 0
    for row in rows:
        address = row["Address"].strip().lower()
        votes_count = int(row["VoteCount"])
        if address in addresses:
            total_votes_count += votes_count
            print(f"    Found {votes_count} Aragon votes for address {address}")
    if total_votes_count >= REQUIRED_ARAGON_VOTES:
        return scores["aragon-vote"]
    return 0


def galxe_scores(addresses: set[str]) -> int:
    api_url = "https://graphigo.prd.galaxy.eco/query"
    lido_space_id = 22849
    query = """
        query($spaceId: Int, $cursor: String) {
      space(id:$spaceId) {
        id
        name
        loyaltyPointsRanks(first:100,cursorAfter:$cursor)
        {
          pageInfo{
            hasNextPage
            endCursor
          }
          edges {
            node {
              points
              address {
                username
                address
              }
            }
          }
        }
      }
    }
    """

    cache_filename = "galxe_loyalty_points.json"

    def fetch_all_items() -> list[dict[str, Any]]:
        cursor = None
        all_items = []
        while True:
            variables = {"spaceId": lido_space_id, "cursor": cursor}
            response = requests.post(
                api_url,
                json={"query": query, "variables": variables},
                headers={"Content-Type": "application/json"}
            )
            response.raise_for_status()
            data = response.json()['data']['space']['loyaltyPointsRanks']

            for edge in data['edges']:
                all_items.append(edge['node'])

            page_info = data['pageInfo']
            if not page_info['hasNextPage']:
                break
            cursor = page_info['endCursor']
        return all_items

    cached_items = _read_cache_file(cache_filename)
    if cached_items is not None:
        all_items = cached_items
    else:
        all_items = fetch_all_items()
        _write_cache_file(cache_filename, all_items)
    addr_to_points = {item["address"]["address"].lower(): item["points"] for item in all_items}

    score = 0
    for address in addresses:
        point = addr_to_points.get(address, 0)
        if point > 10:
            score = scores["galxe-score-above-10"]
            # max score, no need to check further
            print(f"    Found {point} Galxe score for address {address}")
            return score
        elif 4 <= point <= 10:
            print(f"    Found {point} Galxe score for address {address}")
            score = scores["galxe-score-4-10"]
    return score


def gitpoap(addresses: set[str]) -> int:
    url = "https://public-api.gitpoap.io/v1"
    cache_filename = "gitpoap_holders.json"

    with open(current_dir / "gitpoap_events.csv", "r") as f:
        reader = csv.DictReader(f)
        gitpoap_events = {row["ID"]: row["Name"] for row in reader}
    cached_holders = _read_cache_file(cache_filename)
    if not isinstance(cached_holders, dict):
        cached_holders = {}

    final_score = 0
    session = requests.Session()
    adapter = requests.adapters.HTTPAdapter(max_retries=3)
    session.mount('https://', adapter)

    for event_id, event_name in gitpoap_events.items():
        holders = cached_holders.get(event_id)
        if holders is None:
            response = session.get(f"{url}/gitpoaps/{event_id}/addresses")
            response.raise_for_status()
            holder_set = {addr.lower() for addr in response.json().get("addresses", [])}
            holders = sorted(holder_set)
            cached_holders[event_id] = holders
        holder_set = {addr.lower() for addr in holders}
        if any(address.lower() in holder_set for address in addresses):
            print(f"    Found GitPoap for event '{event_name}'")
            final_score = scores["git-poap"]

    _write_cache_file(cache_filename, cached_holders)

    return final_score


def high_signal(addresses: set[str], score: float | None = None) -> int:
    """
    Determine High-signal points.
    - If `score` is provided, use it directly.
    - Else, if `HIGH_SIGNAL_API_KEY` is set, query the API and use the max across addresses.
    - Else, prompt the user for input.
    """
    if score is not None:
        high_signal_score = score
    else:
        high_signal_score = None

    if api_key := os.getenv("HIGH_SIGNAL_API_KEY"):
        high_signal_url = "https://app.highsignal.xyz/api/data/v1/user"
        params = {
            "apiKey": api_key,
            "project": "lido",
            "searchType": "ethereumAddress",
            "startDate": HIGH_SIGNAL_START_DATE.strftime("%Y-%m-%d"),
            "endDate": HIGH_SIGNAL_END_DATE.strftime("%Y-%m-%d"),
        }

        if high_signal_score is None:
            high_signal_score = 0
        for address in addresses:
            params["searchValue"] = Web3.to_checksum_address(address)
            response = requests.get(high_signal_url, params=params)
            if response.status_code == 404:
                continue
            response.raise_for_status()
            response = response.json()
            total_scores = response.get("totalScores", 0)
            address_score = 0
            if total_scores:
                address_score = response.get("totalScores", 0)[0]["totalScore"]

            high_signal_score = max(address_score, high_signal_score)

            if high_signal_score == 0:
                print("    No High-signal score found for the given addresses.")
                return 0
    else:
        if high_signal_score is None:
            print("    ⚠️ For taking into account high-signal score, please visit the https://app.highsignal.xyz/ and enter the given score manually")
            try:
                high_signal_score = float(input("    High-signal score (0-100): "))
            except ValueError:
                print("    Invalid input for high-signal score. Defaulting to 0.")
                return 0
    if high_signal_score < 0 or high_signal_score > 100:
        print("    Invalid input for high-signal score. Defaulting to 0.")
        return 0
    elif 30 <= high_signal_score <= 40:
        hs_points = scores["high-signal-30"]
    elif 40 < high_signal_score <= 60:
        hs_points = scores["high-signal-40"]
    elif 60 < high_signal_score <= 80:
        hs_points = scores["high-signal-60"]
    elif high_signal_score > 80:
        hs_points = scores["high-signal-80"]
    else:
        print(f"    High-signal score {high_signal_score} is below the minimum threshold (30). No additional points awarded.")
        return 0
    return hs_points


def protocol_guild(addresses: set[str]) -> float:
    """
    Check if any of the given addresses is in the Protocol Guild list.
    Always returns 0, but prints a note if present.
    """
    for row in _read_csv_rows_cached(str(current_dir / "protocol_guild.csv")):
        if row and row[0].strip().lower() in addresses:
            print(f"    🤩 Found address {row[0]} in Protocol Guild list")
            return True
    return False


def main(addresses: set[str], high_signal_score: float | None = None):
    """
    Run engagement scoring.
    - `addresses`: set of lowercase addresses.
    - `high_signal_score`: optional override for High-signal score; if None, use API or prompt.
    """
    if (current_dir / CACHE_DIR).exists():
        print(f"⚠️ Warning: found cache dir; using cached data... If you want fresh data, remove engagement/{CACHE_DIR}.")
    print(f"Your addresses: {', '.join(addresses)}")
    print("Checking addresses for Proof of Engagement...")

    results = {
        "snapshot-vote": snapshot_vote(addresses),
        "aragon-vote": aragon_vote(addresses),
        "galxe-score": galxe_scores(addresses),
        "git-poap": gitpoap(addresses),
        "high-signal": high_signal(addresses, score=high_signal_score),
    }
    is_pg = protocol_guild(addresses)

    total_score = 0
    print("\nResults:")
    for key, score in results.items():
        print(f"    {key.replace('-', ' ').title()}: {str(score) + ' ✅' if score else '❌'}")
        if score:
            total_score += int(score)
    if is_pg:
        print("    Protocol Guild: ✅ (no points awarded)")
    print(f"Aggregate score from all sources: {total_score}")
    if total_score < MIN_SCORE:
        print(f"❌ The score is below the minimum required for this category ({MIN_SCORE}).")
        final_score = 0
    else:
        final_score = min(total_score, MAX_SCORE)
        if total_score > MAX_SCORE:
            print(f"Score exceeds the maximum allowed for the category ({MAX_SCORE}). Final score capped at {MAX_SCORE}.")
        print(f"Final Proof of Engagement score: {final_score}")
    return final_score

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python main.py <address1> [<address2> ...]")
        exit(1)
    addrs = set([a.strip().lower() for a in sys.argv[1:]])
    main(addrs)
