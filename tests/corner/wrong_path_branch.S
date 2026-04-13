// wrong_path_branch.S — Wrong-path instruction is itself a branch
//
// Without the `flush_r <= any_correction && !flush_r` guard added in
// core_top.v, a wrong-path branch sitting in EX during the correction cycle
// would re-trigger flush_r with the wrong target, sending the PC to the
// wrong-path branch's destination instead of the original correction target.
//
// This test verifies the guard works: the pipeline must land at the correct
// branch target even when the immediately-following (wrong-path) instruction
// is an always-taken branch or JAL.
//
// Two sub-cases:
//   1: Wrong-path instruction is an always-taken BEQ (x0 == x0)
//   2: Wrong-path instruction is an unconditional JAL

#include "riscv_test.h"

RVTEST_CODE_BEGIN

    // ── Test 1: Wrong-path instruction is always-taken BEQ ────────────────
    // B1 (beq a0, a1, target1) is taken but cold predictor says not-taken
    // → misprediction → correction cycle.
    // In the correction cycle the wrong-path instruction in EX is:
    //   beq x0, x0, bad1    (always taken, always "mispredicted" by cold BTB)
    // Without fix: this re-fires flush_r with target = bad1 → a0 corrupted.
    // With    fix: flush_r gated by !flush_r → bad1 never executes.
    li   TESTNUM, 1
    li   a0, 7
    li   a1, 7

    beq  a0, a1, target1      // B1: taken, mispredicted (cold predictor)
    beq  x0, x0, bad1         // wrong-path: always taken — must be killed
    j    bad1
bad1:
    li   a0, 0                // sentinel: must never execute
    j    fail

target1:
    li   t0, 7
    bne  a0, t0, fail         // a0 must still be 7 (bad1 never ran)

    // ── Test 2: Wrong-path instruction is an unconditional JAL ────────────
    li   TESTNUM, 2
    li   a0, 13
    li   a1, 13

    beq  a0, a1, target2      // taken, mispredicted
    jal  x0, bad2             // wrong-path JAL — must be killed
bad2:
    li   a0, 0                // must never execute
    j    fail

target2:
    li   t0, 13
    bne  a0, t0, fail         // a0 must still be 13

    RVTEST_PASS

fail:
    RVTEST_FAIL

RVTEST_DATA_BEGIN
RVTEST_DATA_END

RVTEST_CODE_END
