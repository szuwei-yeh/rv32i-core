#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# sim/run_riscv_tests.sh
#
# Build and run the full riscv-tests rv32ui-p suite against the RV32I core.
#
# Usage:
#   bash sim/run_riscv_tests.sh              # run all tests
#   bash sim/run_riscv_tests.sh add addi     # run specific tests by name
#   bash sim/run_riscv_tests.sh +WAVE        # dump VCD for every test
#   bash sim/run_riscv_tests.sh +TRACE       # print cycle-by-cycle PC
#
# Requirements:
#   - riscv64-elf-gcc / riscv64-elf-objcopy in PATH
#   - iverilog / vvp in PATH
#   - python3 in PATH
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")/.."          # project root

# ── Paths ─────────────────────────────────────────────────────────────────
RISCV_TESTS="riscv-tests"
ISA="$RISCV_TESTS/isa"
MACROS="$ISA/macros/scalar"
ENV="tests/env"
OUT_DIR="tests/out"              # ELF / hex artefacts
VVP="sim/tb_riscv.vvp"
SCRIPT="scripts/elf2hex.py"

CC="riscv64-elf-gcc"
OBJCOPY="riscv64-elf-objcopy"

# Compiler flags for RV32I bare-metal assembly
CFLAGS="-march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -static"
CFLAGS="$CFLAGS -Wl,--no-relax -T $ENV/link.ld"
CFLAGS="$CFLAGS -I $MACROS -I $ENV -DXLEN=32"

# ── Separate test names and vvp plusargs from script arguments ─────────────
declare -a VVP_ARGS=()
declare -a SELECTED=()

for arg in "$@"; do
    case "$arg" in
        +*) VVP_ARGS+=("$arg") ;;
        *)  SELECTED+=("$arg") ;;
    esac
done

# ── Check dependencies ─────────────────────────────────────────────────────
for tool in "$CC" "$OBJCOPY" iverilog vvp python3; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: '$tool' not found in PATH" >&2
        exit 1
    fi
done

if [ ! -d "$RISCV_TESTS" ]; then
    echo "ERROR: riscv-tests directory not found. Run:" >&2
    echo "  git clone https://github.com/riscv-software-src/riscv-tests.git" >&2
    exit 1
fi

# ── Create output directory ────────────────────────────────────────────────
mkdir -p "$OUT_DIR"

# ── Compile the testbench (once) ──────────────────────────────────────────
echo "━━━ Compiling testbench ━━━"
if ! iverilog -g2005 -o "$VVP" rtl/*.v tb/tb_riscv_tests.v 2>&1; then
    echo "ERROR: testbench compilation failed" >&2
    exit 1
fi
echo "  → $VVP"
echo ""

# ── Discover which tests to run ───────────────────────────────────────────
ALL_TESTS=()
for src in "$ISA"/rv32ui/*.S; do
    name=$(basename "$src" .S)
    ALL_TESTS+=("$name")
done

if [ "${#SELECTED[@]}" -gt 0 ]; then
    TESTS=("${SELECTED[@]}")
else
    TESTS=("${ALL_TESTS[@]}")
fi

TOTAL=${#TESTS[@]}

# ── Run each test ─────────────────────────────────────────────────────────
PASS=0
FAIL=0
SKIP=0
declare -a RESULTS=()
total_cycles=0
total_instrs=0

for name in "${TESTS[@]}"; do
    src="$ISA/rv32ui/${name}.S"
    elf="$OUT_DIR/${name}.elf"
    hex="$OUT_DIR/${name}.hex"

    # Check source exists
    if [ ! -f "$src" ]; then
        echo "SKIP  $name  (source not found: $src)"
        RESULTS+=("SKIP  $name")
        SKIP=$((SKIP + 1))
        continue
    fi

    # ── 1. Compile ────────────────────────────────────────────────────────
    compile_err=0
    compile_log=$($CC $CFLAGS -o "$elf" "$src" 2>&1) || compile_err=$?
    if [ $compile_err -ne 0 ]; then
        echo "FAIL  ${name}  (compile error)"
        echo "      $compile_log"
        RESULTS+=("FAIL  $name  [compile error]")
        FAIL=$((FAIL + 1))
        continue
    fi

    # ── 2. Convert ELF → flat hex ─────────────────────────────────────────
    python3 "$SCRIPT" "$elf" "$hex" 4096

    # ── 3. Copy hex to sim/test.hex (imem/dmem load from this path) ───────
    cp "$hex" sim/test.hex

    # ── 4. Simulate ───────────────────────────────────────────────────────
    result=$(vvp "$VVP" "+TEST=$name" "${VVP_ARGS[@]+"${VVP_ARGS[@]}"}" 2>&1)
    echo "$result"

    # Parse verdict: look for first line starting with PASS, FAIL, or TIMEOUT
    # (vvp may print WARNING lines before the actual result)
    verdict=$(echo "$result" | grep -E '^(PASS|FAIL|TIMEOUT)' | head -1 | awk '{print $1}')
    [ -z "$verdict" ] && verdict="UNKNOWN"

    case "$verdict" in
        PASS)
            RESULTS+=("PASS  $name")
            PASS=$((PASS + 1))
            cyc=$(echo "$result" | grep -E '^PASS' | grep -oE '[0-9]+ cycles' | awk '{print $1}')
            ins=$(echo "$result" | grep -E '^PASS' | grep -oE '[0-9]+ instrs'  | awk '{print $1}')
            [[ -n "$cyc" ]] && total_cycles=$((total_cycles + cyc))
            [[ -n "$ins" ]] && total_instrs=$((total_instrs + ins))
            ;;
        FAIL)
            RESULTS+=("FAIL  $name")
            FAIL=$((FAIL + 1))
            ;;
        TIMEOUT)
            RESULTS+=("TIMEOUT  $name")
            FAIL=$((FAIL + 1))
            ;;
        *)
            RESULTS+=("FAIL  $name  [no verdict]")
            FAIL=$((FAIL + 1))
            ;;
    esac
done

# ── Summary: riscv-tests ──────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " riscv-tests rv32ui-p results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PASS: $PASS / $TOTAL   FAIL: $FAIL   SKIP: $SKIP"
if [ "$total_instrs" -gt 0 ]; then
    avg_cpi=$(awk "BEGIN{printf \"%.3f\", $total_cycles / $total_instrs}")
    echo "  Avg CPI (PASS only): $avg_cpi  ($total_cycles cycles / $total_instrs instrs)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ISA_FAIL=$FAIL

# ── Corner-case tests ─────────────────────────────────────────────────────
# Same toolchain / linker / testbench as rv32ui-p; sources live in tests/corner/.
CORNER_DIR="tests/corner"
CORNER_PASS=0
CORNER_FAIL=0
CORNER_SKIP=0
declare -a CORNER_RESULTS=()

if [ -d "$CORNER_DIR" ] && [ "${#SELECTED[@]}" -eq 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Corner-case hazard tests"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for src in "$CORNER_DIR"/*.S; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .S)
        elf="$OUT_DIR/corner_${name}.elf"
        hex="$OUT_DIR/corner_${name}.hex"

        compile_err=0
        compile_log=$($CC $CFLAGS -o "$elf" "$src" 2>&1) || compile_err=$?
        if [ $compile_err -ne 0 ]; then
            echo "FAIL  corner/$name  (compile error)"
            echo "      $compile_log"
            CORNER_RESULTS+=("FAIL  corner/$name  [compile error]")
            CORNER_FAIL=$((CORNER_FAIL + 1))
            continue
        fi

        python3 "$SCRIPT" "$elf" "$hex" 4096
        cp "$hex" sim/test.hex

        result=$(vvp "$VVP" "+TEST=corner/$name" "${VVP_ARGS[@]+"${VVP_ARGS[@]}"}" 2>&1)
        echo "$result"

        verdict=$(echo "$result" | grep -E '^(PASS|FAIL|TIMEOUT)' | head -1 | awk '{print $1}')
        [ -z "$verdict" ] && verdict="UNKNOWN"

        case "$verdict" in
            PASS)
                CORNER_RESULTS+=("PASS  corner/$name")
                CORNER_PASS=$((CORNER_PASS + 1))
                ;;
            FAIL)
                CORNER_RESULTS+=("FAIL  corner/$name")
                CORNER_FAIL=$((CORNER_FAIL + 1))
                ;;
            TIMEOUT)
                CORNER_RESULTS+=("TIMEOUT  corner/$name")
                CORNER_FAIL=$((CORNER_FAIL + 1))
                ;;
            *)
                CORNER_RESULTS+=("FAIL  corner/$name  [no verdict]")
                CORNER_FAIL=$((CORNER_FAIL + 1))
                ;;
        esac
    done

    CORNER_TOTAL=$((CORNER_PASS + CORNER_FAIL + CORNER_SKIP))
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for r in "${CORNER_RESULTS[@]}"; do echo "  $r"; done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  PASS: $CORNER_PASS / $CORNER_TOTAL   FAIL: $CORNER_FAIL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

if [ "$ISA_FAIL" -eq 0 ] && [ "$CORNER_FAIL" -eq 0 ]; then
    echo "  ALL PASS"
    exit 0
else
    exit 1
fi
