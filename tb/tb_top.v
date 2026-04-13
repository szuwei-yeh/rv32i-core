// Self-checking testbench for RV32I 5-stage pipeline
//
// Test program (sim/program.hex):
//   addi x1, x0, 10       # x1 = 10
//   addi x2, x0, 20       # x2 = 20
//   add  x3, x1, x2       # x3 = 30
//   sw   x3, 0(x0)        # dmem[0] = 30
//   lw   x4, 0(x0)        # x4 = dmem[0] = 30
//   addi x5, x0, 30       # x5 = 30 (expected)
//   beq  x4, x5, pass     # if x4==x5 jump to pass
//   sw   x0, 4(x0)        # FAIL: dmem[1] = 0
//   jal  x0, done
// pass:
//   addi x6, x0, 1
//   sw   x6, 4(x0)        # PASS: dmem[1] = 1
// done:
//   jal  x0, done         # spin forever
//
// Pass condition: dmem word[1] (byte address 4) == 1 after enough cycles.

`timescale 1ns/1ps

module tb_top;
    // Clock and reset
    reg clk;
    reg rst_n;

    // DUT
    core_top #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // 10 ns clock period
    initial clk = 0;
    always #5 clk = ~clk;

    // Timeout watchdog
    integer cycle_count;
    parameter MAX_CYCLES = 200;

    initial begin
        cycle_count = 0;
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;

        // Run until the spin loop at 'done' is reached, or timeout
        // The program writes dmem[1] and then spins; allow enough cycles.
        repeat(MAX_CYCLES) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        // Check result
        check_result();
        $finish;
    end

    task check_result;
        reg [31:0] result;
        begin
            result = dut.u_dmem.mem[1]; // byte address 4 = word index 1
            if (result === 32'h1) begin
                $display("PASS — dmem[4] = %0d after %0d cycles", result, cycle_count);
            end else begin
                $display("FAIL — dmem[4] = %0h (expected 1) after %0d cycles", result, cycle_count);
            end
        end
    endtask

    // Optional: dump waveforms for debugging
    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/wave.vcd");
            $dumpvars(0, tb_top);
        end
    end

    // Optional: cycle-by-cycle PC trace
    always @(posedge clk) begin
        if (rst_n && $test$plusargs("TRACE")) begin
            $display("cyc=%0d  PC=%08h  instr=%08h",
                     cycle_count,
                     dut.u_if_id.id_pc,
                     dut.u_if_id.id_instr);
        end
    end

endmodule
