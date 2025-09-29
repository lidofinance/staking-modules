import { ListUintNum64Type } from "@chainsafe/ssz/lib/type/listUintNum64.js";
import { ProofType } from "@chainsafe/persistent-merkle-tree";

// It's equivalent to BeaconState.balances but with limit of 16 items for more compact proofs.
const List = new ListUintNum64Type(16);
const e = List.defaultView();

e.push(32014202259); // 0
e.push(32052509916); // 1
e.push(32052509917); // 2
e.push(32005726474); // 3
e.push(32005724899); // 4
e.push(0); // 5
e.push(0); // 6
e.push(32005693473); // 7
e.push(32005705994); // 8
e.push(32005732380); // 9

const gI = List.getPropertyGindex(5);
console.log("gI:", gI);
const proof = e.tree.getProof({ type: ProofType.single, gindex: gI });
console.log({
  root: toHex(e.hashTreeRoot()),
  leaf: toHex(proof.leaf),
  proof: proof.witnesses.map(toHex),
});

function toHex(t) {
  return "0x" + Buffer.from(t).toString("hex");
}
