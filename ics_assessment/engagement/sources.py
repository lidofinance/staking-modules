from dataclasses import dataclass
from pathlib import Path

import requests
from web3 import Web3

from ics_assessment.config import HIGH_SIGNAL_END_DATE, HIGH_SIGNAL_START_DATE
from ics_assessment.data_utils import read_csv_dicts, read_csv_rows


@dataclass(frozen=True)
class EngagementSources:
    aragon_voters_path: Path
    snapshot_voters_path: Path
    galxe_loyalty_points_path: Path
    gitpoap_holders_path: Path
    protocol_guild_path: Path


def snapshot_votes_for_addresses(
    addresses: set[str],
    sources: EngagementSources,
) -> tuple[int, list[str]]:
    total_votes_count = 0
    matched_addresses: list[str] = []
    for row in read_csv_dicts(sources.snapshot_voters_path):
        address = row["Address"].strip().lower()
        votes_count = int(row["VoteCount"])
        if address in addresses:
            total_votes_count += votes_count
            matched_addresses.append(f"{address}={votes_count}")
    return total_votes_count, matched_addresses


def aragon_votes_for_addresses(
    addresses: set[str],
    sources: EngagementSources,
) -> tuple[int, list[str]]:
    total_votes_count = 0
    matched_addresses: list[str] = []
    for row in read_csv_dicts(sources.aragon_voters_path):
        address = row["Address"].strip().lower()
        votes_count = int(row["VoteCount"])
        if address in addresses:
            total_votes_count += votes_count
            matched_addresses.append(f"{address}={votes_count}")
    return total_votes_count, matched_addresses


def galxe_points_by_address(sources: EngagementSources) -> dict[str, int]:
    return {
        row["Address"].strip().lower(): int(row["Points"])
        for row in read_csv_dicts(sources.galxe_loyalty_points_path)
    }


def gitpoap_matches(addresses: set[str], sources: EngagementSources) -> list[str]:
    matched_events: list[str] = []
    for row in read_csv_dicts(sources.gitpoap_holders_path):
        address = row["Address"].strip().lower()
        if address in addresses:
            matched_events.append(f"{address}:{row['EventName']}")
    return matched_events


def protocol_guild_matches(addresses: set[str], sources: EngagementSources) -> list[str]:
    matched_addresses: list[str] = []
    for row in read_csv_rows(sources.protocol_guild_path):
        if row and row[0].strip().lower() in addresses:
            matched_addresses.append(row[0].strip().lower())
    return matched_addresses


def fetch_high_signal_max(addresses: set[str], api_key: str | None) -> tuple[float | None, str | None]:
    if not api_key:
        return None, None

    high_signal_url = "https://app.highsignal.xyz/api/data/v1/user"
    params = {
        "apiKey": api_key,
        "project": "lido",
        "searchType": "ethereumAddress",
        "startDate": HIGH_SIGNAL_START_DATE.strftime("%Y-%m-%d"),
        "endDate": HIGH_SIGNAL_END_DATE.strftime("%Y-%m-%d"),
    }
    best_score = 0.0
    best_address = None
    for address in addresses:
        params["searchValue"] = Web3.to_checksum_address(address)
        response = requests.get(high_signal_url, params=params)
        if response.status_code == 404:
            continue
        response.raise_for_status()
        payload = response.json()
        total_scores = payload.get("totalScores", 0)
        address_score = 0.0
        if total_scores:
            address_score = float(total_scores[0]["totalScore"])
        if address_score >= best_score:
            best_score = address_score
            best_address = address
    return best_score, best_address
