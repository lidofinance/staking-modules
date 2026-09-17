// Dependency-free port of remerkleable's List.key_to_static_gindex(),
// specialized for a List of 32-byte basic items (UintBigintType(32) /
// ByteVectorType(32) equivalent: type_byte_length = 32, one element
// per chunk).

// type_byte_length(UintBigintType(32)) = 32; elems_per_chunk = 32 / 32 = 1.
const ELEMS_PER_CHUNK = 1n;

// Get the depth required for a given element count.
function get_depth(elem_count) {
  if (elem_count <= 1n) return 0n;
  let n = elem_count - 1n;
  let d = 0n;
  while (n > 0n) {
    d++;
    n >>= 1n;
  }
  return d;
}

function to_gindex(index, depth) {
  const anchor = 1n << depth;
  if (index >= anchor) {
    throw new Error(`index ${index} too large for depth ${depth}`);
  }
  return anchor | index;
}

function key_to_static_gindex(key, limit) {
  if (key < 0n) throw new RangeError("key must be non-negative");
  const contents_depth = get_depth((limit + ELEMS_PER_CHUNK - 1n) / ELEMS_PER_CHUNK);
  const tree_depth = contents_depth + 1n; // 1 extra for length mix-in
  const chunk_i = key / ELEMS_PER_CHUNK;
  return to_gindex(chunk_i, tree_depth);
}

function toHex(n) {
  return "0x" + n.toString(16).padStart(64, "0");
}

const i = BigInt(process.argv[2]);
const limit = BigInt(process.argv[3]);
console.log(toHex(key_to_static_gindex(i, limit)));
