`timescale 1ns/1ps
// EX/MEM Pipeline Register
module ex_mem_reg #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,
    input  wire                  stall,  // hold register (D$ miss — takes priority over flush)

    // Data inputs from EX stage
    input  wire [ADDR_WIDTH-1:0] ex_pc4,
    input  wire [DATA_WIDTH-1:0] ex_alu_result,
    input  wire [DATA_WIDTH-1:0] ex_rs2_fwd,   // forwarded rs2 (store data)
    input  wire [4:0]            ex_rd,
    input  wire [2:0]            ex_funct3,

    // Control inputs from EX stage
    input  wire                  ex_reg_we,
    input  wire                  ex_mem_we,
    input  wire                  ex_mem_re,
    input  wire [1:0]            ex_wb_sel,

    // Data outputs to MEM stage
    output reg  [ADDR_WIDTH-1:0] mem_pc4,
    output reg  [DATA_WIDTH-1:0] mem_alu_result,
    output reg  [DATA_WIDTH-1:0] mem_rs2_data,
    output reg  [4:0]            mem_rd,
    output reg  [2:0]            mem_funct3,

    // Control outputs to MEM stage
    output reg                   mem_reg_we,
    output reg                   mem_mem_we,
    output reg                   mem_mem_re,
    output reg  [1:0]            mem_wb_sel
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            mem_pc4        <= {ADDR_WIDTH{1'b0}};
            mem_alu_result <= {DATA_WIDTH{1'b0}};
            mem_rs2_data   <= {DATA_WIDTH{1'b0}};
            mem_rd         <= 5'b0;
            mem_funct3     <= 3'b0;
            mem_reg_we     <= 1'b0;
            mem_mem_we     <= 1'b0;
            mem_mem_re     <= 1'b0;
            mem_wb_sel     <= 2'b0;
        end else if (stall) begin
            // Hold all outputs — D$ miss freezes EX/MEM
        end else begin
            mem_pc4        <= ex_pc4;
            mem_alu_result <= ex_alu_result;
            mem_rs2_data   <= ex_rs2_fwd;
            mem_rd         <= ex_rd;
            mem_funct3     <= ex_funct3;
            mem_reg_we     <= ex_reg_we;
            mem_mem_we     <= ex_mem_we;
            mem_mem_re     <= ex_mem_re;
            mem_wb_sel     <= ex_wb_sel;
        end
    end
endmodule
