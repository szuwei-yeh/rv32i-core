# RV32I Pipelined Processor

A synthesizable RV32I processor core implementing the full RISC-V base integer ISA in a classic 5-stage pipeline. Written in plain Verilog, verified against the official RISC-V test suite, and timed-closed at **80 MHz** on a Xilinx Artix-7 FPGA.

---

## Features

| Feature | Detail |
|---|---|
| ISA | Full RV32I (R / I / S / B / U / J formats, all 37 base instructions) |
| Pipeline | 5 stages: IF → ID → EX → MEM → WB |
| Forwarding | EX-EX (EX/MEM→EX) and MEM-EX (MEM/WB→EX), both operands simultaneously |
| Load-use hazard | 1-cycle stall + bubble insertion, detected in hazard unit |
| Branch prediction | 2-bit saturating BHT + BTB, 64 entries, direct-mapped |
| Branch resolution | Resolved in EX stage; registered flush for timing closure |
| L1 I-Cache | Direct-mapped, 64 sets × 4 words/line (1 KB), write-through |
| L1 D-Cache | Direct-mapped, 64 sets × 4 words/line (1 KB), write-back |
| FPGA target | Xilinx Artix-7 xc7a100t (Basys 3 / Nexys A7) |
| Timing closure | **80 MHz, WNS = +0.189 ns** (Vivado 2022.1) |

---

## Architecture

```
         ┌──────────────────────────────────────────────────────────────┐
         │                        core_top                               │
         │                                                               │
  clk ──►│  ┌──────┐  ┌───────┐  ┌───────┐  ┌────────┐  ┌─────────┐  │
 rst_n──►│  │  PC  │  │ IF/ID │  │ ID/EX │  │ EX/MEM │  │ MEM/WB  │  │
         │  └──┬───┘  └───┬───┘  └───┬───┘  └───┬────┘  └────┬────┘  │
         │     │          │          │           │             │        │
         │  ┌──▼──┐  ┌────▼────┐ ┌──▼──┐  ┌────▼───┐  ┌─────▼─────┐ │
         │  │ I$  │  │Decode / │ │ ALU │  │  D$    │  │  Writeback │ │
         │  │imem │  │Control /│ │     │  │  dmem  │  │  mux       │ │
         │  └─────┘  │Regfile  │ └──┬──┘  └────────┘  └───────────┘ │
         │           └─────────┘    │                                  │
         │  ┌────────────────────────────────────────────────────────┐ │
         │  │                   hazard_unit                           │ │
         │  │  • EX-EX / MEM-EX forwarding mux selects (fwd_a/b)    │ │
         │  │  • Load-use stall (pc_stall, if_id_stall, id_ex_flush) │ │
         │  │  • Branch flush (flush_r registered → if_id / id_ex)   │ │
         │  │  • D$ miss stall (freeze IF→MEM, stall MEM/WB)         │ │
         │  └────────────────────────────────────────────────────────┘ │
         │  ┌──────────────────┐                                        │
         │  │ branch_predictor │  2-bit BHT + BTB, lookup in IF        │
         │  └──────────────────┘                                        │
         └──────────────────────────────────────────────────────────────┘
```

### Pipeline Stages

| Stage | Key work |
|---|---|
| **IF** | Fetch from I-cache; branch predictor redirects PC speculatively |
| **ID** | Decode instruction; read register file; generate immediates |
| **EX** | Execute ALU op; evaluate branch condition; select forwarded operands |
| **MEM** | D-cache read/write; cache miss stalls pipeline |
| **WB** | Write result back to register file |

### Hazard Handling

**Data hazards — forwarding**  
The hazard unit computes `fwd_a` / `fwd_b` each cycle:
- `2'b10` → forward `EX/MEM.alu_result` (EX-EX, 1-cycle-old value)
- `2'b01` → forward `MEM/WB.wb_data` (MEM-EX, 2-cycle-old value)
- `2'b00` → use register file output (no hazard)

EX-EX takes priority; both operands can be forwarded simultaneously.

**Load-use hazard**  
When the instruction in EX is a load (`mem_re=1`) and its `rd` matches `rs1` or `rs2` of the instruction in ID: PC and IF/ID are held for one cycle; a bubble is inserted into ID/EX. The loaded value is then forwarded via MEM-EX in the following cycle.

**Branch misprediction**  
Branch outcome is resolved in EX. To break a critical timing path (15 logic levels, 13+ ns through forwarding→ALU→branch→flush), the correction is **registered** (`flush_r`):
- **Cycle N** (branch in EX): `any_correction` asserted combinationally
- **Cycle N+1** (`flush_r=1`): IF/ID flushed, ID/EX flushed, EX/MEM flushed, PC redirected to `correction_target_r`
- **Guard**: `flush_r <= any_correction && !flush_r` prevents a wrong-path branch reaching EX in cycle N+1 from triggering a second spurious flush

**D-cache miss**  
The entire pipeline from IF through MEM/WB is frozen; MEM/WB is stalled (not flushed) to preserve MEM→EX forwarding data across the stall.

---

## Test Results

### RISC-V Official Test Suite (rv32ui-p)

40 / 42 tests pass. The two failures are pre-existing architectural limitations unrelated to pipeline correctness:

| Result | Count | Notes |
|---|---|---|
| PASS | 40 | All integer ISA tests |
| FAIL | 2 | `fence_i` (I-fence not implemented), `ma_data` (misaligned access not supported — legal per RV32I spec) |

**Average CPI across passing tests: ~1.97**

### Corner-Case Hazard Tests

Four targeted tests that exercise specific pipeline edge cases (run via `sim/run_riscv_tests.sh` on a host with `riscv64-elf-gcc`):

| Test | What it exercises |
|---|---|
| `load_use_branch` | LW immediately followed by BEQ/BLT — load-use stall + branch resolution using forwarded load result |
| `consec_mispredict` | Back-to-back taken branches; loop with branch predictor learning then exit misprediction |
| `wrong_path_branch` | Wrong-path instruction is itself an always-taken branch or JAL — verifies the `flush_r && !flush_r` guard prevents a second spurious flush |
| `raw_chain` | 4-instruction RAW dependency chain; load→ADD forwarding; dual-operand forwarding from different stages simultaneously |

---

## Timing (Vivado 2022.1, Artix-7 –1)

| Metric | Value |
|---|---|
| Target clock | 80 MHz (12.5 ns) |
| WNS (Setup) | **+0.189 ns** ✅ |
| WHS (Hold) | +0.140 ns ✅ |
| Failing endpoints | 0 / 45,854 |
| Critical path | EX/MEM → forwarding → ALU → branch → `correction_target_r` CE |
| Critical path depth | 17 logic levels, 12.103 ns data delay |

**Key timing optimisations applied:**

1. **Registered branch correction** — `flush_r` and `correction_target_r` break the combinational forwarding→ALU→branch→PC-mux path (previously fo=235, 11.9 ns routing).
2. **Registered D-cache write-hit** — breaks `pipe_addr→CE` path.
3. **Pipelined D-cache fill** — breaks `dmem_rd_data` (fo=207) path.
4. **Removed `id_ex_kill` from `id_ex_flush`** — eliminates the last 13.1 ns path: forwarding→ALU→`any_correction`→`id_ex_flush` (fo=223). Wrong-path instructions are killed one cycle later via EX/MEM flush (functionally equivalent, same 2-cycle branch penalty).

---

## Repository Structure

```
rv32i-core/
├── rtl/
│   ├── core_top.v          top-level; wires all stages + branch predictor
│   ├── hazard_unit.v       forwarding mux selects, stall/flush control
│   ├── branch_predictor.v  2-bit BHT + BTB, 64 entries
│   ├── icache.v            direct-mapped L1 I-cache (1 KB)
│   ├── dcache.v            direct-mapped L1 D-cache (1 KB, write-back)
│   ├── alu.v               all RV32I ALU operations
│   ├── control.v           instruction decoder → control signals
│   ├── regfile.v           32×32 register file (x0 hardwired 0)
│   ├── {if_id,id_ex,ex_mem,mem_wb}_reg.v   pipeline registers
│   ├── pc_reg.v            stall-aware PC register
│   ├── imem.v / dmem.v     backing memory (simulation)
│   └── synthesis_top.v     FPGA wrapper (clock constraint binding)
├── tb/
│   ├── tb_top.v            basic pipeline smoke test
│   ├── tb_forwarding.v     EX-EX / MEM-EX / load-use forwarding tests
│   ├── tb_programs.v       Fibonacci (fib(10)=55) + bubble sort
│   └── tb_riscv_tests.v    universal harness for riscv-tests + corner tests
├── tests/
│   ├── env/                linker script + riscv_test.h macros
│   └── corner/             corner-case hazard test programs (.S)
├── sim/
│   ├── run.sh              compile + run tb_top / tb_forwarding / tb_programs
│   └── run_riscv_tests.sh  compile + run rv32ui-p suite + corner tests
└── vivado/
    └── create_project.tcl  Vivado project + implementation script
```

---

## How to Simulate

Requires [Icarus Verilog](https://bleyer.org/icarus/) (`iverilog` / `vvp`).

```bash
# Basic testbenches (no toolchain needed)
bash sim/run.sh

# Full RISC-V test suite + corner-case tests
# Requires: riscv64-elf-gcc, python3
bash sim/run_riscv_tests.sh

# Waveform dump (view with GTKWave)
bash sim/run_riscv_tests.sh +WAVE

# Run a single test by name
bash sim/run_riscv_tests.sh add
bash sim/run_riscv_tests.sh load_use_branch
```

---

## How to Implement (Vivado)

```tcl
# In Vivado Tcl Console:
source /path/to/rv32i-core/vivado/create_project.tcl
```

Or from the command line:

```bash
vivado -mode batch -source vivado/create_project.tcl
```

The script synthesises, places, and routes the design targeting `xc7a100t-csg324-1` at 80 MHz, then writes `vivado/rv32i_core/timing_summary.rpt`.
