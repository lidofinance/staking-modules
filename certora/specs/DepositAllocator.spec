// Conditional, bounded verification of the production allocator, without summaries.
// Allocation rules cover EXACTLY TWO operators, normalized positive X96 shares,
// positive capacities and step, and uint128 current/amount/capacity/step inputs.
// The harness bounds arithmetic so packed imbalances fit their 224-bit field.
// No arbitrary-length allocation, global fairness, or full-utilization claim is made.
methods {
    function allocateTwo(uint128, uint128, uint128, uint128, uint96, uint128, uint128) external returns (uint256, uint256, uint256) envfree;
    function quantize(uint256, uint256) external returns (uint256) envfree;
    function roundTrip(uint224, uint32) external returns (uint256, uint256) envfree;
    function popTwo(uint224, uint224) external returns (uint256, uint256, uint256, uint256) envfree;
    function popThree(uint224, uint224, uint224) external returns (uint256, uint256, uint256, uint256, uint256, uint256) envfree;
}

rule validTwoOperatorInputsDoNotRevert(uint128 c0, uint128 c1, uint128 cap0, uint128 cap1, uint96 share0, uint128 amount, uint128 step) {
    require cap0 > 0 && cap1 > 0 && share0 > 0 && step > 0;
    allocateTwo@withrevert(c0, c1, cap0, cap1, share0, amount, step);
    assert !lastReverted;
}

rule twoOperatorConservation(uint128 c0, uint128 c1, uint128 cap0, uint128 cap1, uint96 share0, uint128 amount, uint128 step) {
    require cap0 > 0 && cap1 > 0 && share0 > 0 && step > 0;
    uint256 allocated;
    uint256 a0;
    uint256 a1;
    allocated, a0, a1 = allocateTwo(c0, c1, cap0, cap1, share0, amount, step);
    assert to_mathint(allocated) == to_mathint(a0) + to_mathint(a1);
}

rule twoOperatorRequestBound(uint128 c0, uint128 c1, uint128 cap0, uint128 cap1, uint96 share0, uint128 amount, uint128 step) {
    require cap0 > 0 && cap1 > 0 && share0 > 0 && step > 0;
    uint256 allocated;
    uint256 a0;
    uint256 a1;
    allocated, a0, a1 = allocateTwo(c0, c1, cap0, cap1, share0, amount, step);
    assert allocated <= quantize(amount, step);
}

rule twoOperatorCapacityBounds(uint128 c0, uint128 c1, uint128 cap0, uint128 cap1, uint96 share0, uint128 amount, uint128 step) {
    require cap0 > 0 && cap1 > 0 && share0 > 0 && step > 0;
    uint256 allocated;
    uint256 a0;
    uint256 a1;
    allocated, a0, a1 = allocateTwo(c0, c1, cap0, cap1, share0, amount, step);
    assert a0 <= cap0 && a1 <= cap1;
}

rule twoOperatorQuantization(uint128 c0, uint128 c1, uint128 cap0, uint128 cap1, uint96 share0, uint128 amount, uint128 step) {
    require cap0 > 0 && cap1 > 0 && share0 > 0 && step > 0;
    uint256 allocated;
    uint256 a0;
    uint256 a1;
    allocated, a0, a1 = allocateTwo(c0, c1, cap0, cap1, share0, amount, step);
    assert a0 % step == 0 && a1 % step == 0 && allocated % step == 0;
}

rule zeroRequest(uint128 c0, uint128 c1, uint128 cap0, uint128 cap1, uint96 share0, uint128 step) {
    require cap0 > 0 && cap1 > 0 && share0 > 0 && step > 0;
    uint256 allocated;
    uint256 a0;
    uint256 a1;
    allocated, a0, a1 = allocateTwo(c0, c1, cap0, cap1, share0, 0, step);
    assert allocated == 0 && a0 == 0 && a1 == 0;
}

rule positiveAllocationReachable() {
    uint256 allocated;
    uint256 a0;
    uint256 a1;
    allocated, a0, a1 = allocateTwo(0, 0, 100, 100, 39614081257132168796771975168, 100, 1);
    assert true;
    satisfy allocated == 100 && a0 == 50 && a1 == 50;
}

rule quantizationBounds(uint256 value, uint256 step) {
    uint256 result = quantize(value, step);
    assert result <= value;
    assert step < 2 => result == value;
    assert step >= 2 => result % step == 0;
    assert step >= 2 => to_mathint(value) - to_mathint(result) < step;
}

rule quantizationIdempotent(uint256 value, uint256 step) {
    uint256 result = quantize(value, step);
    assert quantize(result, step) == result;
}

rule packingRoundTrip(uint224 imbalance, uint32 index) {
    uint256 actualImbalance;
    uint256 actualIndex;
    actualImbalance, actualIndex = roundTrip(imbalance, index);
    assert actualImbalance == imbalance && actualIndex == index;
}

rule heapOrderingAndPermutation(uint224 imbalance0, uint224 imbalance1) {
    uint256 first;
    uint256 second;
    uint256 firstImbalance;
    uint256 secondImbalance;
    first, second, firstImbalance, secondImbalance = popTwo(imbalance0, imbalance1);
    assert firstImbalance >= secondImbalance;
    assert first != second && first <= 1 && second <= 1;
    assert first == 0 => firstImbalance == imbalance0 && secondImbalance == imbalance1;
    assert first == 1 => firstImbalance == imbalance1 && secondImbalance == imbalance0;
}

rule heapTieBreak(uint224 imbalance) {
    uint256 first;
    uint256 second;
    uint256 firstImbalance;
    uint256 secondImbalance;
    first, second, firstImbalance, secondImbalance = popTwo(imbalance, imbalance);
    assert first == 0 && second == 1;
}

rule threeKeyHeapOrderingAndPermutation(uint224 imbalance0, uint224 imbalance1, uint224 imbalance2) {
    uint256 first;
    uint256 second;
    uint256 third;
    uint256 firstImbalance;
    uint256 secondImbalance;
    uint256 thirdImbalance;
    first, second, third, firstImbalance, secondImbalance, thirdImbalance = popThree(imbalance0, imbalance1, imbalance2);
    assert firstImbalance >= secondImbalance && secondImbalance >= thirdImbalance;
    assert first <= 2 && second <= 2 && third <= 2;
    assert first != second && first != third && second != third;
    assert firstImbalance == (first == 0 ? imbalance0 : (first == 1 ? imbalance1 : imbalance2));
    assert secondImbalance == (second == 0 ? imbalance0 : (second == 1 ? imbalance1 : imbalance2));
    assert thirdImbalance == (third == 0 ? imbalance0 : (third == 1 ? imbalance1 : imbalance2));
}

rule threeKeyHeapTieBreak(uint224 imbalance) {
    uint256 first;
    uint256 second;
    uint256 third;
    uint256 firstImbalance;
    uint256 secondImbalance;
    uint256 thirdImbalance;
    first, second, third, firstImbalance, secondImbalance, thirdImbalance = popThree(imbalance, imbalance, imbalance);
    assert first == 0 && second == 1 && third == 2;
}
