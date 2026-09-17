// The script can be used to get `BeaconState.balances` proofs for the Verifier tests.

import { ProgressiveListBasicType, UintBigintType } from "@chainsafe/ssz";
import {
  createProof,
  ProofType,
  Tree,
  concatGindices,
  zeroNode,
} from "@chainsafe/persistent-merkle-tree";

// It's equivalent to `BeaconState.balances` in the Gloas state.
const List = new ProgressiveListBasicType(new UintBigintType(8));

// `BeaconState.balances` gindex in the Gloas state, @see src/lib/GIndices.sol.
const GI_BALANCES = 0x167n;

const e = List.defaultViewDU();

e.push(32014202259n); // 0
e.push(32052509916n); // 1
e.push(32052509917n); // 2
e.push(32005726474n); // 3
e.push(32005724899n); // 4
e.push(0n); // 5
e.push(0n); // 6
e.push(32005693473n); // 7
e.push(32005705994n); // 8
e.push(32005732380n); // 9
e.push(18446744073709551615n); // 10
e.commit();

// The list is put in an otherwise empty state to get the proofs the verifier expects.
const state = new Tree(zeroNode(GI_BALANCES.toString(2).length - 1));
state.setNode(GI_BALANCES, e.node);

console.log("stateRoot:", toHex(state.root));

for (const index of [0, 1, 5, 7, 10]) {
  const gI = concatGindices([GI_BALANCES, List.getPropertyGindex(index)]);
  const proof = createProof(state.rootNode, { type: ProofType.single, gindex: gI });

  console.log({
    index,
    gI: "0x" + gI.toString(16),
    leaf: toHex(proof.leaf),
    proof: proof.witnesses.map(toHex),
  });
}

function toHex(t) {
  return "0x" + Buffer.from(t).toString("hex");
}
