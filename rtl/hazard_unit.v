`timescale 1ns/1ps
// Hazard Unit
// Responsibilities:
//   1. Full forwarding: EX-EX (from EX/MEM) and MEM-EX (from MEM/WB)
//   2. Load-use hazard detection: 1-cycle stall
//   3. Branch/jump misprediction flush (2 stages)
module hazard_unit (
    // ID/EX stage info (instruction currently in EX)
    input  wire        id_ex_mem_re,   // is it a load?
    input  wire [4:0]  id_ex_rd,       // destination register

    // EX/MEM stage info (instruction in MEM)
    input  wire        ex_mem_reg_we,
    input  wire [4:0]  ex_mem_rd,

    // MEM/WB stage info (instruction in WB)
    input  wire        mem_wb_reg_we,
    input  wire [4:0]  mem_wb_rd,

    // Source registers of instruction currently in ID (for load-use check)
    input  wire [4:0]  if_id_rs1,
    input  wire [4:0]  if_id_rs2,

    // Source registers of instruction currently in EX (for forwarding)
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,

    // Branch/jump taken signal (from EX stage)
    input  wire        branch_taken,
    input  wire        ex_jal,
    input  wire        ex_jalr,

    // Stall/flush outputs
    output wire        pc_stall,       // stall PC register
    output wire        if_id_stall,    // stall IF/ID register
    output wire        if_id_flush,    // flush IF/ID (insert bubble)
    output wire        id_ex_flush,    // flush ID/EX (insert bubble)

    // Forwarding mux selects
    // 2'b00 = register file, 2'b01 = MEM/WB wb_data, 2'b10 = EX/MEM alu_result
    output wire [1:0]  fwd_a,
    output wire [1:0]  fwd_b
);
    // ---- Load-use hazard ----
    wire load_use_hazard = id_ex_mem_re &&
                           (id_ex_rd != 5'b0) &&
                           ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

    // ---- Branch/jump misprediction flush ----
    wire flush_pipeline = branch_taken || ex_jal || ex_jalr;

    assign pc_stall    = load_use_hazard;
    assign if_id_stall = load_use_hazard;
    assign if_id_flush = flush_pipeline && !load_use_hazard;
    assign id_ex_flush = load_use_hazard || flush_pipeline;

    // ---- EX-EX forwarding (higher priority): from EX/MEM ----
    wire fwd_a_ex = ex_mem_reg_we && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1);
    wire fwd_b_ex = ex_mem_reg_we && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2);

    // ---- MEM-EX forwarding: from MEM/WB (only if EX/MEM doesn't already forward) ----
    wire fwd_a_mem = mem_wb_reg_we && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs1) && !fwd_a_ex;
    wire fwd_b_mem = mem_wb_reg_we && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2) && !fwd_b_ex;

    assign fwd_a = fwd_a_ex  ? 2'b10 :
                  fwd_a_mem ? 2'b01 :
                              2'b00;

    assign fwd_b = fwd_b_ex  ? 2'b10 :
                  fwd_b_mem ? 2'b01 :
                              2'b00;
endmodule
