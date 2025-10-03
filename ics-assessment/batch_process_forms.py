#!/usr/bin/env python3
import csv
import sys
import traceback
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path
import re
import os

# Import local assessment entrypoints
from engagement.main import main as engagement_main
from experience.main import main as experience_main
from humanity.main import main as humanity_main


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

    return list(set(addrs))


def _parse_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    v = value.strip().lower()
    if not v:
        return None
    if v in {"true", "yes", "1"}:
        return True
    if v in {"false", "no", "0"}:
        return False
    return None


def assess_addresses(addresses: list[str], log_path: Path, *,
                     has_discord: bool | None,
                     has_twitter: bool | None) -> tuple[int, int, int, int, str]:
    """
    Runs the three assessments with stdout/stderr captured into log_path.

    Returns: (exp, hum, eng, total, eligibility_str)
    """
    log_path.parent.mkdir(parents=True, exist_ok=True)
    exp = hum = eng = 0
    eligibility = "NO"

    with open(log_path, "w", encoding="utf-8") as lf, redirect_stdout(lf), redirect_stderr(lf):
        print(f"=== ICS Assessment Log ===")
        print(f"Addresses: {', '.join(addresses) if addresses else '(none)'}")
        print()
        try:
            print("==== Proof of Experience ====")
            exp = int(experience_main(set(addresses)))
            print("\n==== Proof of Humanity ====")
            # Pass flags based on links presence from the CSV; API key is required
            hum = int(humanity_main(set(addresses), discord=has_discord, x=has_twitter))
            print("\n==== Proof of Engagement ====")
            # API key is required; no manual override
            eng = int(engagement_main(set(addresses)))
        except SystemExit as e:
            # In case any sub-main() tries to exit
            print(f"[ERROR] Subprocess attempted to exit: {e}")
            traceback.print_exc()
        except Exception as e:  # noqa: BLE001
            print(f"[ERROR] Exception during assessment: {e}")
            traceback.print_exc()
        finally:
            total = int(exp) + int(hum) + int(eng)
            eligibility = "YES" if (exp > 0 and hum > 0 and eng > 0) else "NO"
            print("\n==== Assessment Completed ====")
            print(f"Experience Score: {exp}")
            print(f"Humanity Score:  {hum}")
            print(f"Engagement Score: {eng}")
            print(f"Total: {total}")
            print(f"Eligible: {eligibility}")

    total = int(exp) + int(hum) + int(eng)
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
    script_dir = Path(__file__).parent.resolve()
    input_csv: Path = script_dir / "ics-forms.csv"
    logs_dir: Path = script_dir / "logs"
    if not input_csv.exists():
        print(f"Input file not found: {input_csv}", file=sys.stderr)
        sys.exit(1)

    logs_dir.mkdir(parents=True, exist_ok=True)

    processed = 0
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

            exp = hum = eng = total = 0
            eligible = "NO"
            try:
                exp, hum, eng, total, eligible = assess_addresses(
                    addresses,
                    log_path,
                    has_discord=bool(discord_link) and not bool(discord_comment),
                    has_twitter=bool(twitter_link) and not bool(twitter_comment),
                )
            except Exception as e:  # noqa: BLE001
                # As a fallback, ensure we at least note the error in a minimal log
                with open(log_path, "a", encoding="utf-8") as lf:
                    lf.write("\n[ERROR] Batch-level exception while assessing submission.\n")
                    lf.write(str(e) + "\n")
                    lf.write(traceback.format_exc() + "\n")

            # Human-readable one-liner for the console
            main_short = _short_addr(main_addr) if main_addr else "-"
            print(
                f"[#{row_id}] {status or '-'} | main {main_short} | addrs {len(addresses)} | "
                f"EXP {exp}, HUM {hum}, ENG {eng} | total {total} | eligible {eligible} | log {log_path.relative_to(input_csv.parent)}"
            )
            processed += 1

    print(f"Processed {processed} submission(s). Logs: {logs_dir}", file=sys.stderr)


if __name__ == "__main__":
    main()
