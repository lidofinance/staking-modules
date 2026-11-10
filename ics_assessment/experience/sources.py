import json
from dataclasses import dataclass
from pathlib import Path

from ics_assessment.data_utils import normalize_evm_addresses, read_csv_rows


@dataclass(frozen=True)
class ExperienceSources:
    data_dir: Path
    static_dir: Path
    circles_group_members_path: Path
    eligible_addresses_holesky_path: Path
    eligible_node_operators_hoodi_path: Path
    eligible_node_operators_mainnet_path: Path
    node_operator_owners_hoodi_path: Path
    node_operator_owners_mainnet_path: Path


def csv_matches(addresses: set[str], csv_file: str, base_dir: Path) -> list[str]:
    matches: list[str] = []
    for row in read_csv_rows((base_dir / csv_file).resolve()):
        if row and row[0].strip().lower() in addresses:
            matches.append(row[0].strip().lower())
    return matches


def matched_node_operator_ids(addresses: set[str], owners_path: Path) -> list[str]:
    node_operators = load_owner_map(owners_path)
    addresses = normalize_evm_addresses(addresses)
    return sorted(
        {
            no_id
            for no_id, operator_addresses in node_operators.items()
            if operator_addresses & addresses
        }
    )


def load_owner_map(owners_path: Path) -> dict[str, set[str]]:
    with owners_path.open("r", encoding="utf-8") as file:
        operators = json.load(file)
    result = {}
    for operator_id, addresses in operators.items():
        if not isinstance(addresses, list):
            raise ValueError(
                "Run 'python main.py sync node-owners' to regenerate manager and reward addresses."
            )
        result[operator_id] = normalize_evm_addresses(addresses)
    return result


def load_hoodi_eligible_ids(sources: ExperienceSources) -> set[str]:
    with sources.eligible_node_operators_hoodi_path.open("r", encoding="utf-8") as file:
        return set(json.load(file))


def load_mainnet_eligible_ids(sources: ExperienceSources) -> set[str]:
    with sources.eligible_node_operators_mainnet_path.open("r", encoding="utf-8") as file:
        return set(json.load(file))


def load_hoodi_owner_map(sources: ExperienceSources) -> dict[str, set[str]]:
    return load_owner_map(sources.node_operator_owners_hoodi_path)


def load_mainnet_owner_map(sources: ExperienceSources) -> dict[str, set[str]]:
    return load_owner_map(sources.node_operator_owners_mainnet_path)


def load_holesky_eligible_addresses(sources: ExperienceSources) -> set[str]:
    with sources.eligible_addresses_holesky_path.open("r", encoding="utf-8") as file:
        return set(json.load(file))


def circles_matches(addresses: set[str], sources: ExperienceSources) -> list[str]:
    if not sources.circles_group_members_path.exists():
        return []
    return csv_matches(
        addresses,
        sources.circles_group_members_path.name,
        base_dir=sources.circles_group_members_path.parent,
    )


def load_mainnet_owner_ids(addresses: set[str], sources: ExperienceSources) -> list[str]:
    return matched_node_operator_ids(addresses, sources.node_operator_owners_mainnet_path)


def load_hoodi_owner_ids(addresses: set[str], sources: ExperienceSources) -> list[str]:
    return matched_node_operator_ids(addresses, sources.node_operator_owners_hoodi_path)


def mainnet_owner_path(sources: ExperienceSources) -> Path:
    return sources.node_operator_owners_mainnet_path
