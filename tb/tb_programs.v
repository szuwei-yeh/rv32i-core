// Program Testbench — two sub-tests run sequentially:
//
//  Sub-test 1: Fibonacci
//    Computes fib(0..10) with accumulator loop (9 iterations).
//    Expected: fib(10) = 55.  Pass flag: dmem word[1] (byte addr 4) = 1.
//
//  Sub-test 2: Bubble Sort (ascending)
//    Initialises dmem[0..7] = {5,3,8,1,7,2,9,4}.
//    Sorts with O(n^2) bubble sort (outer=7..1, inner=0..outer-1).
//    Verifies exact result {1,2,3,4,5,7,8,9}.
//    Pass flag: dmem word[16] (byte addr 64) = 1.

`timescale 1ns/1ps

module tb_programs;
    reg clk, rst_n;
    integer cyc, pass_cnt, fail_cnt, i;

    core_top #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) dut (
        .clk  (clk),
        .rst_n(rst_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/prog_wave.vcd");
            $dumpvars(0, tb_programs);
        end
    end

    // Cycle trace (shared counter — resets between sub-tests)
    always @(posedge clk) begin
        if (rst_n && $test$plusargs("TRACE"))
            $display("cyc=%0d PC=%08h instr=%08h",
                     cyc, dut.u_if_id.id_pc, dut.u_if_id.id_instr);
    end

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        // ──────────────────────────────────────────────────────────────────
        // Sub-test 1: Fibonacci  (fib(10) = 55)
        // ──────────────────────────────────────────────────────────────────
        // Hold reset, load program, then release
        rst_n = 0;
        cyc   = 0;
        #1; $readmemh("sim/fib.hex", dut.u_imem.mem);
        repeat(4) @(posedge clk);
        rst_n = 1;

        // The fib loop runs 9 iterations (~5 cy each) + pipeline fill + check
        repeat(200) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        rst_n = 0; // hold for cleanup

        run_check("fibonacci  (fib(10)=55)", dut.u_dmem.mem[1], 32'h1,
                  "dmem[4]");

        // ──────────────────────────────────────────────────────────────────
        // Sub-test 2: Bubble sort
        // ──────────────────────────────────────────────────────────────────
        // Clear the dmem pass-flag cell used by this sub-test
        // (fib did not write to word[16], but be explicit for clarity)
        dut.u_dmem.mem[16] = 32'h0;

        rst_n = 0;
        cyc   = 0;
        #1; $readmemh("sim/sort.hex", dut.u_imem.mem);
        repeat(4) @(posedge clk);
        rst_n = 1;

        // Sort: 57 instr + load-use stalls in inner loop + branch flushes
        // 28 inner-loop iterations × ~10 cy + overhead ≈ 400 cy; use 1000.
        repeat(1000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        rst_n = 0;

        run_check("bubble sort ({5,3,8,1,7,2,9,4}→{1,2,3,4,5,7,8,9})",
                  dut.u_dmem.mem[16], 32'h1, "dmem[64]");

        // ──────────────────────────────────────────────────────────────────
        // Summary
        // ──────────────────────────────────────────────────────────────────
        if (fail_cnt == 0)
            $display("PASS: tb_programs — %0d/%0d sub-tests passed",
                     pass_cnt, pass_cnt + fail_cnt);
        else
            $display("FAIL: tb_programs — %0d/%0d sub-tests failed",
                     fail_cnt, pass_cnt + fail_cnt);

        $finish;
    end

    // Helper task — checks one result cell and updates counters
    task run_check;
        input [255:0] label;   // test name (string-in-reg, for display)
        input [31:0]  actual;
        input [31:0]  expected;
        input [63:0]  cell_name;
        begin
            if (actual === expected) begin
                $display("  pass: %0s — %0s = %0h", label, cell_name, actual);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL: %0s — %0s = %0h (expected %0h)",
                         label, cell_name, actual, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

endmodule
