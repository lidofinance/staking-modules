import argparse
import os
import sys
import csv
import json
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

INPUT_CSV = Path(__file__).parent / "dvt-forms.csv"
INPUT_CSV_NEW_ROUND = Path(__file__).parent / "dvt-forms-new-round.csv"
OUTPUT_JSON = Path(__file__).parent / "artifacts/idvtc-used.json"
OUTPUT_JSON_NEW_ROUND = Path(__file__).parent / "idvtc-used-new-round.json"
ICS_CSV = Path(__file__).parent.parent / "artifacts/mainnet/ics/ics.csv"

def _prompt_bool(prompt: str) -> bool:
    while True:
        answer = input(f"{prompt} (yes/no): ").strip().lower()
        if answer in {"yes", "y"}:
            return True
        if answer in {"no", "n"}:
            return False
        print("Invalid input. Please enter 'yes' or 'no'.")

def _get_approved_clusters() -> list[dict]:
    if not os.path.exists(OUTPUT_JSON):
        print(f"🚨 Output JSON file {OUTPUT_JSON} does not exist. Please run the update command first.")
        return []
    with open(OUTPUT_JSON, "r") as f:
        approved_clusters = json.load(f)
    return approved_clusters

def _get_ics_addresses() -> set[str]:
    if not os.path.exists(ICS_CSV):
        print(f"🚨 ICS CSV file {ICS_CSV} does not exist. Make sure ics.csv is present in the artifacts/mainnet/ics directory.")
        return set()
    with open(ICS_CSV, newline='') as csvfile:
        reader = csv.reader(csvfile)
        ics_addresses = {row[0].strip().lower() for row in reader}
    return ics_addresses

def _update() -> int:
    approved_clusters = []
    if not os.path.exists(INPUT_CSV):
        print(f"Input CSV file {INPUT_CSV} does not exist.")
        return 1
    with open(INPUT_CSV, newline='') as csvfile:
        reader = csv.DictReader(csvfile)
        addresses = set()
        for row in reader:
            addresses.clear()
            addresses.add(row["clusterMember1Address"].strip())
            addresses.add(row["clusterMember2Address"].strip())
            addresses.add(row["clusterMember3Address"].strip())
            addresses.add(row["clusterMember4Address"].strip())
            main_address = row["mainAddress"].strip()
            approved = row["status"].strip() == "APPROVED"
            if approved:
                assert len(set(addresses)) == 4, f"Expected 4 unique addresses, got {len(addresses)}: {addresses}"
                approved_clusters.append({"main_address": main_address.lower(), "addresses": sorted(addr.lower() for addr in addresses)})

    with open(OUTPUT_JSON, "w") as f:
        json.dump(approved_clusters, f, indent=2)
    print(f"Wrote {len(approved_clusters)} clusters to {OUTPUT_JSON}")
    return 0

def _check(main_address: str, members: list[str], suggest_update: bool = True) -> int:
    members = {member.lower() for member in members}
    main_address = main_address.lower()

    approved_clusters = _get_approved_clusters()
    ics_addresses = _get_ics_addresses()

    eligible = _check_idvtc_application(main_address, members, approved_clusters, ics_addresses)

    if eligible and suggest_update and _prompt_bool("Update the approved clusters JSON file with this new cluster?"):
        approved_clusters.append({"main_address": main_address, "addresses": list(members)})
        with open(OUTPUT_JSON, "w") as f:
            json.dump(approved_clusters, f, indent=2)
        print(f"✅ Updated {OUTPUT_JSON} with new cluster")
    
    return 0 if eligible else 1

def _check_idvtc_application(main_address: str, members: list[str], approved_clusters: list[dict], ics_addresses: set[str]) -> bool:
    print(f"Checking IDVTC application\nMain address: {main_address}\nMembers {members}...")

    if len(set(members)) != 4:
        print(f"🚨 Expected 4 unique member addresses, got {len(members)}: {members}")
        return False
    
    for member in members:
        if member not in ics_addresses:
            print(f"🚨 Member address {member} is not in the ICS list.")
            return False

    for cluster in approved_clusters:
        if cluster["main_address"] == main_address:
            print(f"🚨 Main address {main_address} is already approved.")
            return False
        for member in members:
            if member in cluster["addresses"]:
                print(f"🚨 Member address {member} is already part of an approved cluster.")
                return False
    
    print(f"✅ Cluster eligible for approval.")

    return True

def _batch_process():
    if not os.path.exists(INPUT_CSV_NEW_ROUND):
        print(f"Input CSV file {INPUT_CSV_NEW_ROUND} does not exist.")
        return 1
    
    approved_clusters = _get_approved_clusters()
    ics_addresses = _get_ics_addresses()
    main_addresses = set()
    has_errors = False

    with open(INPUT_CSV_NEW_ROUND, newline='') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            main_address = row["mainAddress"].strip().lower()
            members = [
                row["clusterMember1Address"].strip().lower(),
                row["clusterMember2Address"].strip().lower(),
                row["clusterMember3Address"].strip().lower(),
                row["clusterMember4Address"].strip().lower(),
            ]
            id = row["id"].strip()
            approved = row["status"].strip() == "APPROVED"
            if approved:
                eligible = _check_idvtc_application(main_address, members, approved_clusters, ics_addresses)
                if eligible:
                    approved_clusters.append({"main_address": main_address, "addresses": sorted(set(members))})
                    main_addresses.add(main_address)
                else:
                    has_errors = True
            else:
                print(f"Skipping application ID {id} as it is not marked as APPROVED.")

    if not has_errors:
        print("✅ All APPROVED applications in the new round are assessed successfully.")
        with open(OUTPUT_JSON_NEW_ROUND, "w") as f:
            json.dump(list(main_addresses), f, indent=2)
        print(f"Main addresses written to {OUTPUT_JSON_NEW_ROUND}")
        return 0
    else:
        print("🚨 Some APPROVED applications in the new round are not eligible for approval.")
        return 1


def main(argv: list[str] | None = None):
    args = list(sys.argv[1:] if argv is None else argv)

    parser = argparse.ArgumentParser(description="IDVTC assessment entrypoint.")
    subparsers = parser.add_subparsers(dest="command")

    assess_parser = subparsers.add_parser("check", help="Check IDVTC application for eligibility")
    assess_parser.add_argument("main_address")
    assess_parser.add_argument("members", nargs="+")

    subparsers.add_parser("update", help="Update approved IDVTC applications data")

    subparsers.add_parser("batch", help="Batch process IDVTC applications from CSV file")

    parsed = parser.parse_args(args)

    if parsed.command == "check":
        return _check(parsed.main_address, parsed.members)
    if parsed.command == "update":
        return _update()
    if parsed.command == "batch":
        return _batch_process()

    parser.print_help()
    return 1

if __name__ == "__main__":
    raise SystemExit(main())
