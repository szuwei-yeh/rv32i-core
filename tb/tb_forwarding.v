// Forwarding / Hazard Testbench
// Verifies all four forwarding / stall scenarios:
//   Test 1 — EX-EX:        x2 = x1 + 3  (x1 produced one cycle earlier)
//   Test 2 — MEM-EX:       x5 = x1 + 5  (x1 produced two cycles earlier)
//   Test 3 — Double fwd:   x2 = x1 + x1 (both ALU operands forwarded)
//   Test 4 — Load-use:     lw x2; addi x3,x2,0  (1-cycle stall + MEM-EX fwd)
//
// The program stores 1 → dmem word[2] (byte addr 8) on PASS, 0 on FAIL.

`timescale 1ns/1ps

module tb_forwarding;
    reg clk, rst_n;
    integer cyc;

    core_top #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) dut (
        .clk  (clk),
        .rst_n(rst_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Load the forwarding test program AFTER imem's own initial block runs
    initial begin
        #1;
        $readmemh("sim/fwd_test.hex", dut.u_imem.mem);
    end

    // Optional waveform dump
    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/fwd_wave.vcd");
            $dumpvars(0, tb_forwarding);
        end
    end

    initial begin
        rst_n = 0;
        cyc   = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;

        // The program has no loops; 100 cycles is ample.
        repeat(100) begin
            @(posedge clk);
            cyc = cyc + 1;
        end

        check_all();
        $finish;
    end

    // Cycle trace
    always @(posedge clk) begin
        if (rst_n && $test$plusargs("TRACE"))
            $display("cyc=%0d PC=%08h instr=%08h",
                     cyc, dut.u_if_id.id_pc, dut.u_if_id.id_instr);
    end

    task check_all;
        reg [31:0] result;
        begin
            result = dut.u_dmem.mem[2]; // byte addr 8

            if (result === 32'h1) begin
                $display("PASS: tb_forwarding — all 4 forwarding/stall checks (EX-EX, MEM-EX, double-fwd, load-use) after %0d cycles", cyc);
            end else begin
                // Decode which test failed based on known FAIL address in the program.
                // If dmem[2] is still 0 (default), program took the FAIL path.
                $display("FAIL: tb_forwarding — dmem[8]=%0h (expected 1) after %0d cycles", result, cyc);
            end
        end
    endtask

endmodule
