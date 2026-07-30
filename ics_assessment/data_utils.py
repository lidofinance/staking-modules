import csv
import warnings
from collections.abc import Iterable
from pathlib import Path

from web3 import Web3


def read_csv_dicts(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8") as file:
        return list(csv.DictReader(file))


def _is_evm_address(value: str) -> bool:
    try:
        Web3.to_checksum_address(value.strip())
        return True
    except (TypeError, ValueError):
        return False


def read_csv_rows(path: Path) -> list[list[str]]:
    with path.open("r", encoding="utf-8") as file:
        rows = list(csv.reader(file))
    if rows and rows[0] and not _is_evm_address(rows[0][0]):
        warnings.warn(
            f"{path}: first CSV row does not look like an EVM address; "
            "the file may contain an unexpected header",
            RuntimeWarning,
            stacklevel=2,
        )
    return rows


def truncate(values: list[str], limit: int = 3) -> str:
    shown = values[:limit]
    if len(values) > limit:
        shown.append(f"+{len(values) - limit} more")
    return ", ".join(shown)


def normalize_evm_address(value: str) -> str:
    return Web3.to_checksum_address(value.strip()).lower()


def normalize_evm_addresses(values: Iterable[str]) -> set[str]:
    return {normalize_evm_address(value) for value in values}
