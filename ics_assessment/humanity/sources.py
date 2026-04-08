from dataclasses import dataclass
from pathlib import Path
import time
import math

import requests

from ics_assessment.config import HUMAN_PASSPORT_API_URL, HUMAN_PASSPORT_SCORER_ID
from ics_assessment.data_utils import read_csv_rows


@dataclass(frozen=True)
class HumanitySources:
    circle_group_members_path: Path


def circles_matches(addresses: set[str], sources: HumanitySources) -> list[str]:
    matches: list[str] = []
    for row in read_csv_rows(sources.circle_group_members_path):
        if row and row[0].strip().lower() in addresses:
            matches.append(row[0].strip().lower())
    return matches


def fetch_human_passport_max(addresses: set[str], api_key: str | None) -> tuple[float | None, str | None]:
    if not api_key:
        return None, None

    best_score = 0.0
    best_address = None
    for address in addresses:
        url = HUMAN_PASSPORT_API_URL.format(
            scorer_id=HUMAN_PASSPORT_SCORER_ID,
            address=address,
        )
        headers = {"X-API-Key": api_key}
        time.sleep(8)
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        payload = response.json() if getattr(response, "content", None) else response.json()
        score = math.floor(float(payload.get("score", 0) or 0))
        if score > best_score:
            best_score = score
            best_address = address
    return best_score, best_address
