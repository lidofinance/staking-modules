import csv
import os
import sys
import time
from pathlib import Path

import requests
from functools import lru_cache

scores = {
    "human-passport-min": 3,
    "human-passport-max": 8,
    "circles-verified": 4,
    "discord-account": 2,
    "x-account": 1
}

MIN_SCORE = 4
MAX_SCORE = 8

HUMAN_PASSPORT_SCORER_ID = 11737
HUMAN_PASSPORT_API_URL = "https://api.passport.xyz/v2/stamps/{scorer_id}/score/{address}"


current_dir = Path(__file__).parent.resolve()

@lru_cache(maxsize=None)
def _read_csv_rows_cached(path_str: str):
    with open(path_str, "r") as f:
        reader = csv.reader(f)
        return tuple(tuple(row) for row in reader)

def human_passport_score(addresses: set[str], score: float | None = None) -> int:
    """
    Determine Human Passport score.
    - If `score` provided, use it directly.
    - Else, if `HUMAN_PASSPORT_API_KEY` is set, fetch max score across addresses.
    - Else, prompt the user for manual input.
    """
    if score is not None:
        final_score = score
    else:
        api_key = os.getenv("HUMAN_PASSPORT_API_KEY", None)
        if not api_key:
            print("    ⚠️ For taking into account Human Passport score, please visit the https://app.passport.xyz/#/lido_csm/ and enter the given score manually")
            try:
                final_score = float(input("    Human Passport score (0-20): "))
            except ValueError:
                print("    Invalid input for Human Passport score. Defaulting to 0.")
                return 0
        else:
            final_score = 0
            for address in addresses:
                url = HUMAN_PASSPORT_API_URL.format(
                    scorer_id=HUMAN_PASSPORT_SCORER_ID, address=address
                )
                headers = {"X-API-Key": api_key}
                time.sleep(8)  # sleep 8 sec to not hit rate limit of 125 requests per 15 minutes
                resp = requests.get(url, headers=headers)
                resp.raise_for_status()
                data = resp.json() if getattr(resp, "content", None) else resp.json()
                s_val = float(data.get("score", 0) or 0)
                if s_val:
                    print(f"    Found Human Passport score {s_val} for address {address}")
                if s_val > final_score:
                    final_score = s_val
    if final_score and final_score < scores["human-passport-min"]:
        print(f"    Human Passport score {final_score} is below the minimum required ({scores['human-passport-min']}).")
        return 0
    if final_score > scores["human-passport-max"]:
        print(f"    Human Passport score {final_score} exceeds the maximum allowed ({scores['human-passport-max']}). Capping to {scores['human-passport-max']}.")
        return scores["human-passport-max"]
    return final_score


def circles_verified_score(addresses: set[str]) -> int:
    for row in _read_csv_rows_cached(str(current_dir / "circle_group_members.csv")):
        if row and row[0].strip().lower() in addresses:
            print(f"    Found address {row[0]} in Circles group members")
            return scores["circles-verified"]


def discord_account_score(provided: bool | None = None) -> int:
    """
    Return Discord score.
    - If `provided` is True/False, use it.
    - If None, prompt interactively.
    """
    if provided is None:
        has_discord = input("⚠️ Discord account provided? (yes/no): ").strip().lower()
        if has_discord in ["yes", "y"]:
            return scores["discord-account"]
        elif has_discord in ["no", "n"]:
            print("No Discord handle provided. Returning score of 0.")
            return 0
        else:
            print("Invalid input. Please enter 'yes' or 'no'.")
            return discord_account_score()
    return scores["discord-account"] if provided else 0


def x_account_score(provided: bool | None = None) -> int:
    """
    Return X(Twitter) score.
    - If `provided` is True/False, use it.
    - If None, prompt interactively.
    """
    if provided is None:
        has_x = input("⚠️ X account provided? (yes/no): ").strip().lower()
        if has_x in ["yes", "y"]:
            return scores["x-account"]
        elif has_x in ["no", "n"]:
            print("No X handle provided. Returning score of 0.")
            return 0
        else:
            print("Invalid input. Please enter 'yes' or 'no'.")
            return x_account_score()
    return scores["x-account"] if provided else 0


def main(
    addresses: set[str],
    discord: bool | None = None,
    x: bool | None = None,
    human_passport_score_override: float | None = None,
):
    """
    Run humanity scoring.
    - `addresses`: set of lowercase addresses.
    - `discord`: optional bool indicating Discord handle provided.
    - `x`: optional bool indicating X handle provided.
    - `human_passport_score_override`: optional float to bypass API/prompt.
    """
    print(f"Your addresses: {', '.join(addresses)}")
    print("Checking addresses for Proof of Humanity...")

    results = {
        "human-passport": human_passport_score(addresses, score=human_passport_score_override),
        "circles-verified": circles_verified_score(addresses),
        "discord-account": discord_account_score(discord),
        "x-account": x_account_score(x)
    }

    total_score = 0
    print("\nResults:")
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
        print(f"Final Proof of Humanity score: {final_score}")
    return final_score

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python main.py <address1> [<address2> ...]")
        exit(1)
    addrs = set([a.strip().lower() for a in sys.argv[1:]])
    main(addrs)
