// Custom test environment for RV32I bare-metal core simulation
// Compatible with riscv-tests rv32ui-p test suite
//
// Memory map:
//   0x00000000 - 0x00003FFF : .text (imem, 4096 words)
//   0x00000000 - 0x00000FFF : dmem mirror (loaded from same hex)
//   tohost                  : 0x00000C00 (dmem word 768)
//
// Protocol:
//   tohost == 1              → PASS
//   tohost & 1, tohost != 1  → FAIL at test# (tohost >> 1)

#ifndef _ENV_RV32I_CORE_H
#define _ENV_RV32I_CORE_H

// ── Register aliases ──────────────────────────────────────────────────────
// gp (x3) carries the current test-case number (TESTNUM).
#define TESTNUM gp

// ── RVTEST_RV32U / RVTEST_RV64U ──────────────────────────────────────────
// rv32ui tests redefine RVTEST_RV64U as RVTEST_RV32U before including the
// shared rv64ui source, so we must define both to the same thing.
#define RVTEST_RV32U  .macro init; .endm
#define RVTEST_RV64U  RVTEST_RV32U

// ── RVTEST_CODE_BEGIN ─────────────────────────────────────────────────────
// Entry point at address 0x00000000.
// Initialises TESTNUM (gp) to 0 so TEST_PASSFAIL can detect "no tests ran".
#define RVTEST_CODE_BEGIN       \
    .section .text.init;        \
    .align   2;                 \
    .globl   _start;            \
_start:                         \
    li gp, 0;

// ── RVTEST_CODE_END ───────────────────────────────────────────────────────
// No epilogue needed; RVTEST_PASS / RVTEST_FAIL spin forever.
#define RVTEST_CODE_END

// ── RVTEST_PASS ───────────────────────────────────────────────────────────
// Write 1 to tohost then spin.  Uses local label 991 (unlikely to clash
// with test-case labels that typically run 1-60).
#define RVTEST_PASS                                                     \
    li   gp, 1;                                                         \
    la   t0, tohost;                                                    \
    sw   gp, 0(t0);                                                     \
991:j    991b;

// ── RVTEST_FAIL ───────────────────────────────────────────────────────────
// Encode the failing test number: tohost = (TESTNUM << 1) | 1.
// If TESTNUM is 0 (no test ran), write 0xFFFFFFFF as a sentinel.
// Uses local labels 992, 993.
#define RVTEST_FAIL                                                     \
    beqz gp, 993f;                                                      \
    sll  gp, gp, 1;                                                     \
    ori  gp, gp, 1;                                                     \
    j    994f;                                                          \
993:li   gp, 0xffffffff;                                                \
994:la   t0, tohost;                                                    \
    sw   gp, 0(t0);                                                     \
992:j    992b;

// ── Data section wrappers ─────────────────────────────────────────────────
#define RVTEST_DATA_BEGIN   .data; .align 2;
#define RVTEST_DATA_END

#endif /* _ENV_RV32I_CORE_H */
