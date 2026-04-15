import csv
from pathlib import Path


def read_csv_dicts(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8") as file:
        return list(csv.DictReader(file))


def read_csv_rows(path: Path) -> list[list[str]]:
    with path.open("r", encoding="utf-8") as file:
        return list(csv.reader(file))


def truncate(values: list[str], limit: int = 3) -> str:
    shown = values[:limit]
    if len(values) > limit:
        shown.append(f"+{len(values) - limit} more")
    return ", ".join(shown)
