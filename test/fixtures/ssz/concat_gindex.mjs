// Concatenate two generalized indices.
//
// A generalized index encodes a tree path in binary: the leading "1"
// marks the root, and each lower bit selects left (0) or right (1).
// Concatenating two paths means appending rhs's path bits (everything
// below its leading "1") onto lhs's path.
//
// Reference: https://github.com/protolambda/remerkleable/blob/91ed092d08ef0ba5ab076f0a34b0b371623db728/remerkleable/tree.py#L46

/**
 * @param {bigint} lhs
 * @param {bigint} rhs
 * @returns {bigint}
 */
function concat(lhs, rhs) {
  if (lhs <= 0n || rhs <= 0n) {
    throw new RangeError("gindex must be positive");
  }

  // Path length of rhs = bits below its leading "1".
  const rhsDepth = BigInt(rhs.toString(2).length - 1);

  // Shift lhs up to make room for rhs's path bits, then OR them in
  // (rhs with its leading "1" cleared).
  return (lhs << rhsDepth) | (rhs ^ (1n << rhsDepth));
}

/**
 * @param {bigint} n
 * @returns {string}
 */
function toHex(n) {
  return "0x" + n.toString(16).padStart(64, "0");
}

// Usage: node concat_gindex.mjs <gindex> [<gindex> ...]
// Each arg may be decimal ("42") or hex ("0x2a"); BigInt accepts both.
// Concatenation is left-associative: concat(a, b, c) === concat(concat(a, b), c).
const args = process.argv.slice(2);
if (args.length === 0) {
  throw new RangeError("at least one gindex is required");
}
console.log(toHex(args.map(BigInt).reduce(concat)));
