// consec_mispredict.S — Consecutive branch mispredictions
//
// Tests that the pipeline handles multiple mispredictions in sequence without
// corrupting architectural state or getting stuck.  Three sub-cases:
//   1: Two back-to-back taken branches (cold predictor: both mispredict)
//   2: Three consecutive taken branches with intermediate computations
//   3: 5-iteration loop — predictor learns "taken", then exit mispredicts

#include "riscv_test.h"

RVTEST_CODE_BEGIN

    // ── Test 1: Two consecutive taken branches ─────────────────────────────
    li   TESTNUM, 1
    li   t0, 5
    beq  t0, t0, 1f           // taken (cold predictor → mispredict)
    j    fail
1:
    beq  t0, t0, 2f           // taken (predictor may still mispredict)
    j    fail
2:
    li   t1, 5
    bne  t0, t1, fail         // t0 must still be 5

    // ── Test 2: Three back-to-back taken branches with side effects ─────────
    li   TESTNUM, 2
    li   a0, 0
    beq  a0, a0, 3f           // taken
    j    fail
3:
    addi a0, a0, 1            // a0 = 1
    beq  a0, a0, 4f           // taken (a0 == a0 is always true)
    j    fail
4:
    addi a0, a0, 1            // a0 = 2
    beq  a0, a0, 5f           // taken
    j    fail
5:
    addi a0, a0, 1            // a0 = 3
    li   t0, 3
    bne  a0, t0, fail         // verify a0 accumulated correctly through flushes

    // ── Test 3: Loop — predictor learns "taken", exit branch mispredicts ───
    li   TESTNUM, 3
    li   a0, 0                // loop counter
    li   a1, 5                // limit
loop3:
    addi a0, a0, 1
    blt  a0, a1, loop3        // taken 4× (predictor → strongly taken),
                              // then not-taken on exit (mispredict)
    li   t0, 5
    bne  a0, t0, fail         // counter must equal 5 after loop

    RVTEST_PASS

fail:
    RVTEST_FAIL

RVTEST_DATA_BEGIN
RVTEST_DATA_END

RVTEST_CODE_END
