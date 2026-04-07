# RV32I 5-Stage Pipelined Processor

A complete, synthesizable implementation of the RISC-V RV32I ISA in a classic
5-stage pipeline (IF → ID → EX → MEM → WB), written in plain Verilog and
verified with Icarus Verilog.

---

## Features

| Feature | Detail |
|---|---|
| ISA | Full RV32I (all R/I/S/B/U/J formats) |
| Pipeline | 5 stages: IF, ID, EX, MEM, WB |
| Forwarding | EX→EX (EX/MEM) and MEM→EX (MEM/WB) paths |
| Load-use hazard | 1-cycle stall with pipeline bubble insertion |
| Branch strategy | Predict-not-taken; resolved in EX; 2-stage flush on misprediction |
| Jumps | JAL (PC-relative) and JALR (register-indirect) |
| Memory | Byte/halfword/word loads (signed + unsigned) and stores |
| Parameters | `DATA_WIDTH=32`, `ADDR_WIDTH=32` on every module |
| Simulator | Icarus Verilog (`iverilog` + `vvp`) |

### Supported Instructions

**R-type:** ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND  
**I-type ALU:** ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI  
**Loads:** LB, LH, LW, LBU, LHU  
**Stores:** SB, SH, SW  
**Branches:** BEQ, BNE, BLT, BGE, BLTU, BGEU  
**Jumps:** JAL, JALR  
**Upper-immediate:** LUI, AUIPC  

---

## Project Layout

```
rv32i-core/
├── rtl/
│   ├── pc_reg.v        — Program counter register (stall-aware)
│   ├── imem.v          — Instruction memory (ROM, init from hex)
│   ├── dmem.v          — Data memory (byte/half/word R/W)
│   ├── regfile.v       — 32×32 register file (x0 hardwired 0)
│   ├── alu.v           — ALU (all RV32I ops)
│   ├── control.v       — Main decoder (opcode → control signals)
│   ├── hazard_unit.v   — Forwarding + load-use stall + branch flush
│   ├── if_id_reg.v     — IF/ID pipeline register
│   ├── id_ex_reg.v     — ID/EX pipeline register
│   ├── ex_mem_reg.v    — EX/MEM pipeline register
│   ├── mem_wb_reg.v    — MEM/WB pipeline register
│   └── core_top.v      — Top-level, wires all stages together
├── tb/
│   └── tb_top.v        — Self-checking testbench
├── sim/
│   ├── run.sh          — One-command compile + simulate
│   └── program.hex     — Test program (hex words, one per line)
└── README.md
```

---

## Quick Start

Requires [Icarus Verilog](https://bleyer.org/icarus/) (`iverilog`/`vvp`).

```bash
# Run from the project root
bash sim/run.sh
```

Expected output:
```
=== Compiling ===
=== Simulating ===
PASS — dmem[4] = 1 after 200 cycles
```

### Optional flags

```bash
bash sim/run.sh +WAVE    # dump sim/wave.vcd (view with GTKWave)
bash sim/run.sh +TRACE   # print PC + instruction each cycle
bash sim/run.sh +WAVE +TRACE
```

---

## Test Program

The program in `sim/program.hex` exercises ADD, ADDI, SW, LW, and BEQ:

```asm
addi x1, x0, 10       # x1 = 10
addi x2, x0, 20       # x2 = 20
add  x3, x1, x2       # x3 = 30  (tests forwarding)
sw   x3, 0(x0)        # dmem[0] = 30
lw   x4, 0(x0)        # x4 = 30  (load-use stall exercised)
addi x5, x0, 30       # x5 = 30
beq  x4, x5, pass     # branch taken — tests flush logic
sw   x0, 4(x0)        # FAIL path: dmem[1] = 0
jal  x0, done
pass:
addi x6, x0, 1
sw   x6, 4(x0)        # PASS path: dmem[1] = 1
done:
jal  x0, done         # spin
```

The testbench reads `dmem[1]` (byte address 4) after 200 cycles and prints
`PASS` if it equals 1, `FAIL` otherwise.

---

## Pipeline Architecture

```
      ┌────┐  ┌────────┐  ┌────────┐  ┌─────────┐  ┌──────────┐
 clk ─┤ PC ├──┤ IF/ID  ├──┤ ID/EX  ├──┤ EX/MEM  ├──┤ MEM/WB   │
      └──┬─┘  └───┬────┘  └───┬────┘  └────┬────┘  └────┬─────┘
         │   IMEM │     RF/   │      ALU /  │  DMEM  │   │  WB
         │        │   Decode  │    Branch   │        │   │
         └────────┴───────────┴─────────────┴────────┴───┘
                        ▲ Forwarding (hazard_unit)
```

### Hazard Handling Details

**Forwarding** (`hazard_unit.v`):
- `fwd_a/b == 2'b10`: forward EX/MEM `alu_result` → EX stage operand (EX-EX)
- `fwd_a/b == 2'b01`: forward MEM/WB `wb_data` → EX stage operand (MEM-EX)
- EX/MEM forwarding takes priority over MEM/WB

**Load-use stall**:  
If the instruction in EX is a load and its `rd` matches `rs1` or `rs2` of the
instruction currently in ID: PC and IF/ID are held, ID/EX receives a bubble.

**Branch misprediction flush**:  
Branch condition evaluated in EX. On taken branch or any jump (JAL/JALR):
IF/ID and ID/EX are flushed (2 pipeline bubbles inserted), PC redirected.

---

## Replacing the Test Program

Assemble your RV32I program to a hex file where each line is one 32-bit
instruction word in big-endian hex (e.g., `00A00093`). Pad to 64 lines with
`00000013` (NOP). Place it at `sim/program.hex` and re-run `sim/run.sh`.
