`timescale 1ns/1ps
// IF/ID Pipeline Register
module if_id_reg #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  stall,   // hold current value
    input  wire                  flush,   // insert NOP bubble

    // Inputs from IF stage
    input  wire [ADDR_WIDTH-1:0] if_pc,
    input  wire [ADDR_WIDTH-1:0] if_pc4,
    input  wire [DATA_WIDTH-1:0] if_instr,

    // Outputs to ID stage
    output reg  [ADDR_WIDTH-1:0] id_pc,
    output reg  [ADDR_WIDTH-1:0] id_pc4,
    output reg  [DATA_WIDTH-1:0] id_instr
);
    localparam NOP = 32'h00000013; // ADDI x0, x0, 0

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc    <= {ADDR_WIDTH{1'b0}};
            id_pc4   <= {ADDR_WIDTH{1'b0}};
            id_instr <= NOP;
        end else if (flush) begin
            id_pc    <= {ADDR_WIDTH{1'b0}};
            id_pc4   <= {ADDR_WIDTH{1'b0}};
            id_instr <= NOP;
        end else if (!stall) begin
            id_pc    <= if_pc;
            id_pc4   <= if_pc4;
            id_instr <= if_instr;
        end
        // stall: retain current values (no else branch needed)
    end
endmodule
