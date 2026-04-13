// load_use_branch.S — Load-use hazard immediately followed by a branch
//
// Verifies that a 1-cycle load-use stall interacts correctly with branch
// resolution.  Three sub-cases:
//   1: LW → BEQ taken      (stall + forwarded value satisfies branch)
//   2: LW → BEQ not-taken  (stall + forwarded value fails branch)
//   3: LW → BLT taken      (stall + BLT with forwarded value)

#include "riscv_test.h"

RVTEST_CODE_BEGIN

    // ── Test 1: LW → BEQ taken ────────────────────────────────────────────
    li   TESTNUM, 1
    li   t0, 0x42
    sw   t0, 512(x0)          // mem[128] = 0x42
    lw   t1, 512(x0)          // t1 = 0x42  ← load
    beq  t1, t0,  1f          // load-use stall; t1==t0 → taken
    j    fail
1:

    // ── Test 2: LW → BEQ not-taken ────────────────────────────────────────
    li   TESTNUM, 2
    li   t0, 0x42
    li   t2, 0x99             // different value
    sw   t0, 516(x0)
    lw   t1, 516(x0)          // t1 = 0x42  ← load
    beq  t1, t2, fail         // t1 != t2 → NOT taken (falls through)

    // ── Test 3: LW → BLT taken ────────────────────────────────────────────
    li   TESTNUM, 3
    li   t0, 20               // upper bound
    li   t2, 7
    sw   t2, 520(x0)
    lw   t1, 520(x0)          // t1 = 7  ← load
    blt  t1, t0, 3f           // load-use stall; 7 < 20 → taken
    j    fail
3:

    RVTEST_PASS

fail:
    RVTEST_FAIL

RVTEST_DATA_BEGIN
RVTEST_DATA_END

RVTEST_CODE_END
