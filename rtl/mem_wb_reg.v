`timescale 1ns/1ps
// MEM/WB Pipeline Register
module mem_wb_reg #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  stall,  // hold register (D$ stall — takes priority, preserves forwarding)
    input  wire                  flush,  // insert bubble (branch flush — lower priority than stall)

    // Data inputs from MEM stage
    input  wire [ADDR_WIDTH-1:0] mem_pc4,
    input  wire [DATA_WIDTH-1:0] mem_alu_result,
    input  wire [DATA_WIDTH-1:0] mem_rdata,
    input  wire [4:0]            mem_rd,

    // Control inputs from MEM stage
    input  wire                  mem_reg_we,
    input  wire [1:0]            mem_wb_sel,

    // Data outputs to WB stage
    output reg  [ADDR_WIDTH-1:0] wb_pc4,
    output reg  [DATA_WIDTH-1:0] wb_alu_result,
    output reg  [DATA_WIDTH-1:0] wb_mem_data,
    output reg  [4:0]            wb_rd,

    // Control outputs to WB stage
    output reg                   wb_reg_we,
    output reg  [1:0]            wb_wb_sel
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_pc4        <= {ADDR_WIDTH{1'b0}};
            wb_alu_result <= {DATA_WIDTH{1'b0}};
            wb_mem_data   <= {DATA_WIDTH{1'b0}};
            wb_rd         <= 5'b0;
            wb_reg_we     <= 1'b0;
            wb_wb_sel     <= 2'b0;
        end else if (stall) begin
            // Hold all outputs — D$ stall freezes MEM/WB to preserve forwarding context
            // (prevents loss of the MEM-EX forwarding source for instructions in EX)
        end else if (flush) begin
            wb_pc4        <= {ADDR_WIDTH{1'b0}};
            wb_alu_result <= {DATA_WIDTH{1'b0}};
            wb_mem_data   <= {DATA_WIDTH{1'b0}};
            wb_rd         <= 5'b0;
            wb_reg_we     <= 1'b0;
            wb_wb_sel     <= 2'b0;
        end else begin
            wb_pc4        <= mem_pc4;
            wb_alu_result <= mem_alu_result;
            wb_mem_data   <= mem_rdata;
            wb_rd         <= mem_rd;
            wb_reg_we     <= mem_reg_we;
            wb_wb_sel     <= mem_wb_sel;
        end
    end
endmodule
