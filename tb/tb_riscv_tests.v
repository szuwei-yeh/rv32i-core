`timescale 1ns/1ps
// ─────────────────────────────────────────────────────────────────────────────
// tb_riscv_tests.v – Universal testbench for riscv-tests rv32ui-p suite
//
// Write-back D$ note
// ──────────────────
// With write-back D$, the sw to tohost (0xC00) stays dirty in the cache.
// tohost is checked by reading dcache arrays directly in the initial block
// (hierarchical refs in procedural code work in Icarus; @* sensitivity does not
// track changes to submodule regs, so we do NOT use an always @(*) for this).
//
// Address 0xC00 cache breakdown (WAYS=1, NUM_SETS=64, LINE_WORDS=4):
//   byte addr   0xC00 = 0b...0000_1100_0000_0000
//   byte_off  = 0xC00[1:0]  = 0
//   word_off  = 0xC00[3:2]  = 0    → TOHOST_WOFF = 0
//   set_index = 0xC00[9:4]  = 0    → TOHOST_SET  = 0
//   tag       = 0xC00[31:10]= 3    → TOHOST_TAG  = 22'h3
// ─────────────────────────────────────────────────────────────────────────────

module tb_riscv_tests;

    // ── Parameters ────────────────────────────────────────────────────────
    parameter MAX_CYCLES  = 20000;
    parameter TOHOST_WORD = 768;     // dmem word index for byte addr 0xC00

    // Cache address breakdown for tohost (must match core_top parameters)
    localparam TOHOST_SET  = 0;      // 0xC00[9:4]
    localparam TOHOST_WOFF = 0;      // 0xC00[3:2]
    localparam TOHOST_TAG  = 22'h3;  // 0xC00[31:10]

    // ── Signals ───────────────────────────────────────────────────────────
    reg clk;
    reg rst_n;

    // ── DUT ───────────────────────────────────────────────────────────────
    core_top #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .debug_pc     (),   // not used in testbench
        .debug_wb_data(),
        .debug_reg_we ()
    );

    // ── Clock: 10 ns period ───────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Load test hex into imem AND dmem ─────────────────────────────────
    initial begin
        #1;
        $readmemh("sim/test.hex", dut.u_imem.mem);
        $readmemh("sim/test.hex", dut.u_dmem.mem);
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
    // Count non-bubble, non-stall cycles entering EX.
    // id_ex_stall=1 means the same instruction is frozen in ID/EX; skip it
    // to avoid double-counting during D$ miss stall cycles.
    integer instr_count;
    always @(posedge clk) begin
        if (rst_n && !dut.id_ex_flush && !dut.id_ex_stall)
            instr_count = instr_count + 1;
    end

    // ── Main test driver ──────────────────────────────────────────────────
    reg [1023:0] test_name;
    integer      cycle_count;
    reg  [31:0]  tohost_val;

    initial begin
        if (!$value$plusargs("TEST=%s", test_name))
            test_name = "unknown";

        cycle_count = 0;
        instr_count = 0;
        tohost_val  = 32'h0;

        // Reset for 4 clock cycles
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;

        // Run until tohost is written or timeout.
        // Tohost is sampled each posedge directly inside this procedural block
        // so that hierarchical references resolve correctly.  With write-back D$
        // the SW to 0xC00 stays dirty; we check the D$ arrays first.
        // Values set by NBA at posedge T are visible here from posedge T+1
        // onwards (standard Verilog delta-cycle semantics), so detection is
        // delayed at most one cycle after the SW completes.
        repeat(MAX_CYCLES) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            // Read tohost: D$ first (write-back keeps SW dirty in cache), then dmem.
            // cache_data0 holds word-offset-0, which is where 0xC00 maps (TOHOST_WOFF=0).
            if (dut.u_dcache.cache_valid[0][TOHOST_SET] &&
                    (dut.u_dcache.cache_tag[0][TOHOST_SET] == TOHOST_TAG))
                tohost_val = dut.u_dcache.cache_data0[0][TOHOST_SET];
            else
                tohost_val = dut.u_dmem.mem[TOHOST_WORD];

            if (tohost_val === 32'h1) begin
                $display("PASS  %-24s  (%0d cycles, %0d instrs, CPI=%0.2f)  I$: %0d hits / %0d misses  D$: %0d hits / %0d misses  BP: %0d branches, %0d mispred (%0.1f%%)",
                         test_name, cycle_count, instr_count,
                         $itor(cycle_count) / $itor(instr_count),
                         dut.u_icache.hit_count, dut.u_icache.miss_count,
                         dut.u_dcache.hit_count, dut.u_dcache.miss_count,
                         dut.u_bp.branch_count, dut.u_bp.mispredict_count,
                         dut.u_bp.branch_count > 0 ?
                             100.0 * $itor(dut.u_bp.mispredict_count) / $itor(dut.u_bp.branch_count) :
                             0.0);
                $finish;
            end else if (tohost_val[0] === 1'b1) begin
                $display("FAIL  %-24s  test_case=%0d  tohost=0x%08h  (%0d cycles, %0d instrs)",
                         test_name, tohost_val >> 1, tohost_val,
                         cycle_count, instr_count);
                $finish;
            end
        end

        $display("TIMEOUT %-24s  (%0d cycles, %0d instrs, tohost=0x%08h)",
                 test_name, cycle_count, instr_count, tohost_val);
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
