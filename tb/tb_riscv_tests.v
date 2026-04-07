`timescale 1ns/1ps
// ─────────────────────────────────────────────────────────────────────────────
// tb_riscv_tests.v – Universal testbench for riscv-tests rv32ui-p suite
//
// How it works
// ────────────
// 1. The iverilog/vvp compile includes rtl/*.v; imem.v loads sim/program.hex
//    (its default path) at time 0.
// 2. At time #1 ps this testbench overrides both imem and dmem from
//    sim/test.hex (the test-specific unified flat image).  This gives dmem
//    the initialised .data section values that load-instruction tests need.
// 3. The test signals completion by writing to address 0x00000C00 (dmem
//    word 768):  1 → PASS,  (testnum<<1)|1 → FAIL at that test case.
// 4. Timeout after MAX_CYCLES → reported as TIMEOUT (counts as FAIL).
//
// Plusargs
// ────────
//   +TEST=<name>   Display name in the result line (default "unknown")
//   +WAVE          Dump sim/wave.vcd
//   +TRACE         Print cycle-by-cycle PC trace
// ─────────────────────────────────────────────────────────────────────────────

module tb_riscv_tests;

    // ── Parameters ────────────────────────────────────────────────────────
    parameter MAX_CYCLES  = 20000;   // generous budget for loop-heavy tests
    parameter TOHOST_WORD = 768;     // dmem word index for byte addr 0xC00

    // ── Signals ───────────────────────────────────────────────────────────
    reg clk;
    reg rst_n;

    // ── DUT ───────────────────────────────────────────────────────────────
    core_top #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // ── Clock: 10 ns period ───────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Load test hex into imem AND dmem ─────────────────────────────────
    // imem.v already ran $readmemh("sim/program.hex") at time 0.
    // We override both memories at #1 ps with the unified test image so that
    // the .data section is correctly mirrored in dmem.
    initial begin
        #1;
        $readmemh("sim/test.hex", dut.u_imem.mem);
        $readmemh("sim/test.hex", dut.u_dmem.mem);
        // Zero the tohost slot: tests with large code sections (> 0xC00 bytes,
        // e.g. ld_st) may have instruction words that fall at dmem[768].
        // Clearing it prevents a spurious FAIL before the test starts.
        dut.u_dmem.mem[TOHOST_WORD] = 32'h0;
    end

    // ── Optional waveform dump ────────────────────────────────────────────
    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/wave.vcd");
            $dumpvars(0, tb_riscv_tests);
        end
    end

    // ── Instruction counter ───────────────────────────────────────────────
    // Count every cycle where a non-bubble enters the EX stage.
    // Bubbles are indicated by id_ex_flush=1 (load-use stall or branch flush).
    // Since there is no flush after EX (ex_mem_reg flush is tied to 1'b0),
    // every non-bubble that enters EX is guaranteed to retire at WB.
    integer instr_count;
    always @(posedge clk) begin
        if (rst_n && !dut.id_ex_flush)
            instr_count = instr_count + 1;
    end

    // ── Main test driver ──────────────────────────────────────────────────
    reg [1023:0] test_name;
    integer      cycle_count;
    integer      tohost_val;

    initial begin
        if (!$value$plusargs("TEST=%s", test_name))
            test_name = "unknown";

        cycle_count = 0;
        instr_count = 0;

        // Reset for 4 clock cycles
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;

        // Run until tohost is written or timeout
        repeat(MAX_CYCLES) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            tohost_val = dut.u_dmem.mem[TOHOST_WORD];

            // Only trigger on a definite non-zero write
            if (tohost_val === 32'h1) begin
                $display("PASS  %-24s  (%0d cycles, %0d instrs, CPI=%0.2f)",
                         test_name, cycle_count, instr_count,
                         $itor(cycle_count) / $itor(instr_count));
                $finish;
            end else if (tohost_val[0] === 1'b1) begin
                // tohost = (failing_testnum << 1) | 1
                $display("FAIL  %-24s  test_case=%0d  tohost=0x%08h  (%0d cycles, %0d instrs)",
                         test_name, tohost_val >> 1, tohost_val,
                         cycle_count, instr_count);
                $finish;
            end
        end

        // Reached here → timeout
        $display("TIMEOUT %-24s  (%0d cycles, %0d instrs, tohost=0x%08h)",
                 test_name, cycle_count, instr_count, dut.u_dmem.mem[TOHOST_WORD]);
        $finish;
    end

    // ── Optional PC trace ─────────────────────────────────────────────────
    always @(posedge clk) begin
        if (rst_n && $test$plusargs("TRACE")) begin
            $display("cyc=%0d  PC=%08h  instr=%08h",
                     cycle_count,
                     dut.if_pc,
                     dut.if_instr);
        end
    end

endmodule
