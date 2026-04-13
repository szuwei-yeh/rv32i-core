`timescale 1ns/1ps
// Register File — 32×32 registers, x0 hardwired to 0
// Synchronous write, asynchronous read
module regfile #(
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  we,
    input  wire [4:0]            rs1,
    input  wire [4:0]            rs2,
    input  wire [4:0]            rd,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire [DATA_WIDTH-1:0] rd1,
    output wire [DATA_WIDTH-1:0] rd2
);
    reg [DATA_WIDTH-1:0] regs [1:31]; // x0 not stored

    // synthesis translate_off
    integer i;
    initial begin
        for (i = 1; i < 32; i = i + 1)
            regs[i] = {DATA_WIDTH{1'b0}};
    end
    // synthesis translate_on

    // Synchronous write (x0 write is silently discarded)
    always @(posedge clk) begin
        if (we && rd != 5'b0)
            regs[rd] <= wr_data;
    end

    // Asynchronous read — x0 always returns 0
    // WB bypass: if WB is writing the same register this cycle, forward wr_data
    // (handles the case where WB writes at the same posedge that ID reads)
    assign rd1 = (rs1 == 5'b0)             ? {DATA_WIDTH{1'b0}} :
                 (we && rd == rs1)          ? wr_data            :
                 regs[rs1];
    assign rd2 = (rs2 == 5'b0)             ? {DATA_WIDTH{1'b0}} :
                 (we && rd == rs2)          ? wr_data            :
                 regs[rs2];
endmodule
