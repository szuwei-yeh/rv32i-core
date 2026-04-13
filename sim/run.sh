#!/usr/bin/env bash
# Compile and simulate all RV32I testbenches with Icarus Verilog.
# Usage: bash sim/run.sh [+WAVE] [+TRACE]
#   +WAVE  — dump VCD files per testbench
#   +TRACE — print cycle-by-cycle PC trace

set -euo pipefail
cd "$(dirname "$0")/.."          # always run from project root

RTL=$(echo rtl/*.v)
PASS_COUNT=0
FAIL_COUNT=0
declare -a SUMMARY

# ── Helper: compile + run one testbench, capture PASS/FAIL line ────────────
run_tb() {
    local name="$1"
    local tb="$2"
    shift 2
    local vvp_args=("$@")

    echo ""
    echo "━━━ $name ━━━"

    # Compile (use -s to explicitly name the top module so iverilog ignores
    # synthesis-only top modules like axi_top that live in rtl/)
    local compile_log
    if ! compile_log=$(iverilog -g2005 -s "$name" -o "sim/${name}.vvp" $RTL "$tb" 2>&1); then
        echo "$compile_log"
        echo "FAIL: $name — compilation error"
        SUMMARY+=("FAIL: $name (compile error)")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi
    # Show any warnings (non-fatal)
    [ -n "$compile_log" ] && echo "$compile_log"

    # Simulate and capture output
    local out
    out=$(vvp "sim/${name}.vvp" "${vvp_args[@]+"${vvp_args[@]}"}" 2>&1)
    echo "$out"

    # Determine pass/fail from the last PASS/FAIL line printed by the TB
    local verdict
    verdict=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)' | tail -1)

    if printf '%s\n' "$verdict" | grep -q '^PASS'; then
        SUMMARY+=("PASS: $name")
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        SUMMARY+=("FAIL: $name")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ── Run all testbenches ────────────────────────────────────────────────────
run_tb tb_top        tb/tb_top.v        "$@"
run_tb tb_forwarding tb/tb_forwarding.v "$@"
run_tb tb_programs   tb/tb_programs.v   "$@"

# ── Summary ───────────────────────────────────────────────────────────────
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "━━━ Summary ━━━"
for line in "${SUMMARY[@]}"; do
    echo "  $line"
done

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "ALL PASS ($PASS_COUNT/$TOTAL)"
    exit 0
else
    echo "FAILED ($FAIL_COUNT/$TOTAL)"
    exit 1
fi
