import pytest

from ics_assessment.data_utils import read_csv_rows


def test_read_csv_rows_warns_on_header_like_first_row(tmp_path):
    path = tmp_path / "addresses.csv"
    path.write_text(
        "Address\n"
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
        encoding="utf-8",
    )

    with pytest.warns(RuntimeWarning, match="unexpected header"):
        rows = read_csv_rows(path)

    assert rows[0] == ["Address"]
