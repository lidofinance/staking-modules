# Python port of remerkleable's to_gindex_progressive(), specialized
# for ProgressiveList items where each element occupies a full 32-byte
# chunk (i.e. one element per chunk, no packing).
#
# Reference: https://github.com/ethereum/remerkleable/blob/9ada4b5fa4a570663793972e41d7ea4a60de68c0/remerkleable/progressive.py#L48
#
# The returned gindex is relative to the ProgressiveList root node
# (the pair node that mixes the data subtree with the list length).

import sys

LEFT_GINDEX = 2


def progressive_list_item_gindex(i: int) -> int:
    """Generalized index of the i-th item in a progressive list of
    32-byte elements. ``i`` is a zero-based, non-negative item index."""
    chunk_i = i
    if chunk_i < 0:
        raise ValueError("i must be non-negative")

    depth = 0
    gindex = LEFT_GINDEX
    # Walk progressive subtrees: at each level peel off a complete binary
    # base subtree of size (1 << depth); if the index lies inside it,
    # descend into that subtree, otherwise continue right.
    while True:
        base_size = 1 << depth
        if chunk_i < base_size:
            return ((gindex << 1) << depth) + chunk_i
        chunk_i -= base_size
        depth += 2
        gindex = (gindex << 1) + 1


def to_hex(n: int) -> str:
    return "0x" + format(n, "064x")


if __name__ == "__main__":
    chunk_i = int(sys.argv[1])
    print(to_hex(progressive_list_item_gindex(chunk_i)))
