from dataclasses import dataclass
from pathlib import Path
from typing import Any

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


def _fetch_high_signal_user(params: dict[str, str]) -> dict[str, Any] | None:
    response = requests.get(
        "https://app.highsignal.xyz/api/data/v1/user",
        params=params,
        timeout=20,
    )
    if response.status_code == 404:
        return None
    response.raise_for_status()
    return response.json()


def _latest_total_score(payload: dict[str, Any] | None) -> float:
    if not payload:
        return 0.0
    total_scores = payload.get("totalScores", [])
    if not total_scores:
        return 0.0
    return float(total_scores[0].get("totalScore", 0) or 0)


def fetch_high_signal_max(
    addresses: set[str],
    api_key: str | None,
) -> tuple[float | None, str | None, str | None, str | None]:
    if not api_key:
        return None, None, None, None

    base_params = {
        "apiKey": api_key,
        "project": "lido",
        "searchType": "ethereumAddress",
        "startDate": HIGH_SIGNAL_START_DATE.strftime("%Y-%m-%d"),
        "endDate": HIGH_SIGNAL_END_DATE.strftime("%Y-%m-%d"),
    }
    best_score = 0.0
    best_address = None
    best_username = None
    best_project = None
    for address in addresses:
        lido_params = base_params | {"searchValue": Web3.to_checksum_address(address)}
        lido_payload = _fetch_high_signal_user(lido_params)
        username = (lido_payload or {}).get("username")
        for project, score in (
            ("lido", _latest_total_score(lido_payload)),
            ("ssv", _fetch_ssv_high_signal_score(username)),
        ):
            if score > best_score:
                best_score = score
                best_address = address
                best_username = username
                best_project = project
    return best_score, best_address, best_username, best_project


def _fetch_ssv_high_signal_score(username: str | None) -> float:
    if not username:
        return 0.0
    params = {
        "project": "ssv",
        "searchType": "highSignalUsername",
        "searchValue": username,
        "startDate": HIGH_SIGNAL_START_DATE.strftime("%Y-%m-%d"),
        "endDate": HIGH_SIGNAL_END_DATE.strftime("%Y-%m-%d"),
    }
    return _latest_total_score(_fetch_high_signal_user(params))
