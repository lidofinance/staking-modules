import pytest

from ics_assessment.sync import _fetch_logs as fetch_logs


def entry(block, index=0):
    return {
        "blockNumber": block,
        "logIndex": index,
        "blockHash": block.to_bytes(32, "big"),
        "transactionHash": (block + 1).to_bytes(32, "big"),
    }


@pytest.mark.parametrize("start,end", [(0, 0), (0, 9), (7, 21), (10, 19)])
@pytest.mark.parametrize("size", [1, 2, 5, 10, 11])
def test_inclusive_range_partition_has_no_gaps_or_duplicate_boundaries(
    start, end, size
):
    ranges = []

    def fetch(first, last):
        ranges.append((first, last))
        return [entry(block) for block in range(first, last + 1)]

    assert [
        log["blockNumber"] for log in fetch_logs(fetch, start, end, "test", size)
    ] == list(range(start, end + 1))
    assert ranges[0][0] == start and ranges[-1][1] == end
    assert all(last - first + 1 <= size for first, last in ranges)
