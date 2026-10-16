// JavaScript port of remerkleable's to_gindex_progressive(), specialized
// for ProgressiveList items where each element occupies a full 32-byte
// chunk (i.e. one element per chunk, no packing).
//
// Reference: https://github.com/ethereum/remerkleable/blob/9ada4b5fa4a570663793972e41d7ea4a60de68c0/remerkleable/progressive.py#L48
//
// The returned gindex is relative to the ProgressiveList root node
// (the pair node that mixes the data subtree with the list length).

const LEFT_GINDEX = 2n;

/**
 * Generalized index of the i-th item in a progressive list of 32-byte
 * elements.
 *
 * @param {bigint} i  zero-based item index (non-negative)
 * @returns {bigint} generalized index
 */
function progressiveListItemGindex(chunkI) {
  if (chunkI < 0n) throw new RangeError("item index must be non-negative");

  let depth = 0n;
  let gindex = LEFT_GINDEX;
  // Walk progressive subtrees: at each level peel off a complete binary
  // base subtree of size (1 << depth); if the index lies inside it,
  // descend into that subtree, otherwise continue right.
  for (;;) {
    const baseSize = 1n << depth;
    if (chunkI < baseSize) {
      return ((gindex << 1n) << depth) + chunkI;
    }
    chunkI -= baseSize;
    depth += 2n;
    gindex = (gindex << 1n) + 1n;
  }
}

/**
 * @param {bigint} n
 * @returns {string}
 */
function toHex(n) {
  return "0x" + n.toString(16).padStart(64, "0");
}

const chunkI = BigInt(process.argv[2]);
const gI = progressiveListItemGindex(chunkI);
console.log(toHex(gI));
