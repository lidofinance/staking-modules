#!/usr/bin/env python3
import csv
import json
import sys
from pathlib import Path
import re
import os

from ics_assessment.config import (
    BATCH_FORMS_PATH,
    BATCH_LOGS_DIR,
    BATCH_MAIN_ADDRESS_SUMMARY_PATH,
)
from ics_assessment.main import evaluate_assessment, resolve_runtime_inputs
from ics_assessment.render import render_assessment_result


def _short_addr(addr: str) -> str:
    a = addr.lower()
    return f"{a[:6]}…{a[-4:]}" if len(a) == 42 and a.startswith("0x") else a[:12]


def _parse_addresses(main_addr: str | None, additional: str | None) -> list[str]:
    addrs: list[str] = []
    if main_addr:
        m = main_addr.strip().lower()
        addrs.append(m)

    if additional:
        # Normalize separators to commas, then split on comma and whitespace.
        s = additional.replace(";", ",").replace("\n", ",").replace("|", ",")
        raw = re.split(r"[\s,]+", s)
        for r in raw:
            a = r.strip().lower()
            addrs.append(a)

    return list(dict.fromkeys(addrs))


def assess_addresses(addresses: list[str], log_path: Path, *,
                     has_discord: bool | None,
                     has_twitter: bool | None) -> tuple[int, int, int, int, str]:
    """
    Runs the three assessments and writes a full text report to log_path.

    Returns: (exp, hum, eng, total, eligibility_str)
    """
    log_path.parent.mkdir(parents=True, exist_ok=True)
    addresses_set = set(addresses)
    runtime_inputs = resolve_runtime_inputs(
        addresses_set,
        discord=has_discord,
        x=has_twitter,
        allow_prompt=False,
    )
    result = evaluate_assessment(
        addresses_set,
        runtime_inputs=runtime_inputs,
    )
    with open(log_path, "w", encoding="utf-8") as lf:
        lf.write(render_assessment_result(result) + "\n")

    exp = int(result.category("Experience").final_score)
    hum = int(result.category("Humanity").final_score)
    eng = int(result.category("Engagement").final_score)
    total = int(result.total_score)
    eligibility = "YES" if result.eligible else "NO"
    return exp, hum, eng, total, eligibility


def main():
    # Require API keys for High Signal and Human Passport
    if not os.environ.get("HIGH_SIGNAL_API_KEY"):
        print("Missing required env var: HIGH_SIGNAL_API_KEY", file=sys.stderr)
        sys.exit(1)
    if not os.environ.get("HUMAN_PASSPORT_API_KEY"):
        print("Missing required env var: HUMAN_PASSPORT_API_KEY", file=sys.stderr)
        sys.exit(1)

    # Constant file paths (no CLI args)
    input_csv: Path = BATCH_FORMS_PATH
    logs_dir: Path = BATCH_LOGS_DIR
    if not input_csv.exists():
        print(f"Input file not found: {input_csv}", file=sys.stderr)
        sys.exit(1)

    logs_dir.mkdir(parents=True, exist_ok=True)

    processed = 0
    approved_ineligible = 0
    main_addresses: list[tuple[str, str]] = []
    with open(input_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for idx, row in enumerate(reader):

            row_id = (row.get("id") or str(idx + 1)).strip()
            main_addr = (row.get("mainAddress") or "").strip()
            additional = (row.get("additionalAddresses") or "").strip()
            status = (row.get("status") or "").strip()
            twitter_link = (row.get("twitterLink") or "").strip()
            discord_link = (row.get("discordLink") or "").strip()
            twitter_comment = (row.get("twitterLinkComment") or "").strip()
            discord_comment = (row.get("discordLinkComment") or "").strip()
            if status in ("REJECTED", "REVIEW"):
                print(f"Skipping {row_id} as status is {status}")
                continue
            addresses = _parse_addresses(main_addr, additional)
            # Log file named by submission id only
            log_name = f"{row_id}.log"

            log_path = logs_dir / log_name

            exp, hum, eng, total, eligible = assess_addresses(
                addresses,
                log_path,
                has_discord=bool(discord_link) and not bool(discord_comment),
                has_twitter=bool(twitter_link) and not bool(twitter_comment),
            )

            # Human-readable one-liner for the console
            main_short = _short_addr(main_addr) if main_addr else "-"
            print(
                f"[#{row_id}] {status or '-'} | main {main_short} | addrs {len(addresses)} | "
                f"EXP {exp}, HUM {hum}, ENG {eng} | total {total} | eligible {eligible} | log {log_path.relative_to(input_csv.parent)}"
            )
            processed += 1
            main_addresses.append((row_id, main_addr.lower()))
            if status == "APPROVED" and eligible == "NO":
                print(f"⚠️ {row_id} Application is approved but not eligible with score")
                approved_ineligible += 1

    summary_path = BATCH_MAIN_ADDRESS_SUMMARY_PATH
    def _sort_row_id(item: tuple[str, str]) -> tuple[int, int | str]:
        row_id, _ = item
        try:
            return (0, int(row_id))
        except ValueError:
            return (1, row_id)

    sorted_addresses = [addr for _, addr in sorted(main_addresses, key=_sort_row_id)]
    with open(summary_path, "w", encoding="utf-8") as summary_file:
        json.dump(sorted_addresses, summary_file, indent=2)
    print(
        f"Processed {processed} application(s); found {approved_ineligible} approved submission(s) that remain ineligible. \n"
        f"Logs: {logs_dir}. \n"
        f"Main address summary: {summary_path}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
