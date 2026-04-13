// raw_chain.S — RAW dependency chain forwarding
//
// Exercises EX-EX and MEM-EX forwarding paths with chains of dependent
// instructions, including the case where both ALU operands come from
// different forwarding stages simultaneously.
//
// Four sub-cases:
//   1: 4-instruction RAW chain (EX-EX on each adjacent pair)
//   2: Load-use stall then immediate ADD of loaded value (MEM-EX from load)
//   3: Both ALU operands forwarded from different stages (EX-EX + MEM-EX)
//   4: MEM-EX forwarding from WB stage (2-instruction gap)

#include "riscv_test.h"

RVTEST_CODE_BEGIN

    // ── Test 1: 4-instruction RAW chain ───────────────────────────────────
    // t0=1 → t1=2 → t2=3 → t3=5, each reading the result of the previous.
    li   TESTNUM, 1
    li   t0, 1
    add  t1, t0, t0           // t1 = 2  (EX-EX: t0 forwarded)
    add  t2, t1, t0           // t2 = 3  (EX-EX: t1; MEM-EX: t0)
    add  t3, t2, t1           // t3 = 5  (EX-EX: t2; MEM-EX: t1)
    li   t4, 5
    bne  t3, t4, fail

    // ── Test 2: Load-use stall + EX-EX forward of loaded value ────────────
    li   TESTNUM, 2
    li   t0, 0x42
    sw   t0, 512(x0)
    lw   t1, 512(x0)          // t1 = 0x42  (load, 1-cycle stall)
    add  t2, t1, t1           // t2 = 0x84  (MEM-EX fwd from load result)
    li   t3, 0x84
    bne  t2, t3, fail

    // ── Test 3: Both operands forwarded from different stages ──────────────
    li   TESTNUM, 3
    li   t0, 10
    addi t1, t0, 5            // t1 = 15  (EX-EX: t0)
    add  t2, t1, t0           // t2 = 25  (EX-EX: t1 from prev; MEM-EX: t0)
    li   t3, 25
    bne  t2, t3, fail

    // ── Test 4: MEM-EX forward (value produced 2 instructions ago) ─────────
    li   TESTNUM, 4
    li   t0, 100
    add  t1, t0, x0           // t1 = 100  (EX-EX: t0)
    add  t2, x0,  x0          // t2 = 0    (independent, clears EX-EX path for t1)
    add  t3, t1,  x0          // t3 = 100  (MEM-EX: t1 from 2 instrs ago)
    li   t4, 100
    bne  t3, t4, fail

    RVTEST_PASS

fail:
    RVTEST_FAIL

RVTEST_DATA_BEGIN
RVTEST_DATA_END

RVTEST_CODE_END
