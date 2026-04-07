`timescale 1ns/1ps
// ID/EX Pipeline Register
module id_ex_reg #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,  // insert bubble (load-use stall or branch flush)

    // Data inputs from ID stage
    input  wire [ADDR_WIDTH-1:0] id_pc,
    input  wire [ADDR_WIDTH-1:0] id_pc4,
    input  wire [DATA_WIDTH-1:0] id_rs1_data,
    input  wire [DATA_WIDTH-1:0] id_rs2_data,
    input  wire [DATA_WIDTH-1:0] id_imm,
    input  wire [4:0]            id_rs1_addr,
    input  wire [4:0]            id_rs2_addr,
    input  wire [4:0]            id_rd,
    input  wire [2:0]            id_funct3,

    // Control inputs from ID stage
    input  wire [3:0]            id_alu_ctrl,
    input  wire                  id_alu_src_a,
    input  wire                  id_alu_src_b,
    input  wire                  id_reg_we,
    input  wire                  id_mem_we,
    input  wire                  id_mem_re,
    input  wire [1:0]            id_wb_sel,
    input  wire                  id_branch,
    input  wire                  id_jal,
    input  wire                  id_jalr,

    // Data outputs to EX stage
    output reg  [ADDR_WIDTH-1:0] ex_pc,
    output reg  [ADDR_WIDTH-1:0] ex_pc4,
    output reg  [DATA_WIDTH-1:0] ex_rs1_data,
    output reg  [DATA_WIDTH-1:0] ex_rs2_data,
    output reg  [DATA_WIDTH-1:0] ex_imm,
    output reg  [4:0]            ex_rs1_addr,
    output reg  [4:0]            ex_rs2_addr,
    output reg  [4:0]            ex_rd,
    output reg  [2:0]            ex_funct3,

    // Control outputs to EX stage
    output reg  [3:0]            ex_alu_ctrl,
    output reg                   ex_alu_src_a,
    output reg                   ex_alu_src_b,
    output reg                   ex_reg_we,
    output reg                   ex_mem_we,
    output reg                   ex_mem_re,
    output reg  [1:0]            ex_wb_sel,
    output reg                   ex_branch,
    output reg                   ex_jal,
    output reg                   ex_jalr
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            ex_pc        <= {ADDR_WIDTH{1'b0}};
            ex_pc4       <= {ADDR_WIDTH{1'b0}};
            ex_rs1_data  <= {DATA_WIDTH{1'b0}};
            ex_rs2_data  <= {DATA_WIDTH{1'b0}};
            ex_imm       <= {DATA_WIDTH{1'b0}};
            ex_rs1_addr  <= 5'b0;
            ex_rs2_addr  <= 5'b0;
            ex_rd        <= 5'b0;
            ex_funct3    <= 3'b0;
            ex_alu_ctrl  <= 4'b0;
            ex_alu_src_a <= 1'b0;
            ex_alu_src_b <= 1'b0;
            ex_reg_we    <= 1'b0;
            ex_mem_we    <= 1'b0;
            ex_mem_re    <= 1'b0;
            ex_wb_sel    <= 2'b0;
            ex_branch    <= 1'b0;
            ex_jal       <= 1'b0;
            ex_jalr      <= 1'b0;
        end else begin
            ex_pc        <= id_pc;
            ex_pc4       <= id_pc4;
            ex_rs1_data  <= id_rs1_data;
            ex_rs2_data  <= id_rs2_data;
            ex_imm       <= id_imm;
            ex_rs1_addr  <= id_rs1_addr;
            ex_rs2_addr  <= id_rs2_addr;
            ex_rd        <= id_rd;
            ex_funct3    <= id_funct3;
            ex_alu_ctrl  <= id_alu_ctrl;
            ex_alu_src_a <= id_alu_src_a;
            ex_alu_src_b <= id_alu_src_b;
            ex_reg_we    <= id_reg_we;
            ex_mem_we    <= id_mem_we;
            ex_mem_re    <= id_mem_re;
            ex_wb_sel    <= id_wb_sel;
            ex_branch    <= id_branch;
            ex_jal       <= id_jal;
            ex_jalr      <= id_jalr;
        end
    end
endmodule
