`timescale 1ns/1ps
// Hazard Unit
// Responsibilities:
//   1. Full forwarding: EX-EX (from EX/MEM) and MEM-EX (from MEM/WB)
//   2. Load-use hazard detection: 1-cycle stall
//   3. Branch/jump misprediction flush (2 stages)
//   4. I$ miss stall  — stalls IF/ID, injects bubble into ID/EX (like load-use)
//   5. D$ miss stall  — freezes entire pipeline up to MEM, bubbles MEM/WB
//
// Priority (highest first): dcache_stall > load_use / icache_stall > branch flush
// When dcache_stall is asserted, branch flush is deferred until the stall clears.
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

    // Branch/jump redirect signals (from EX stage)
    input  wire        mispredicted, // branch/JAL prediction was wrong → flush 2 stages
    input  wire        ex_jalr,      // JALR always needs redirect (not predicted)

    // Cache stall inputs
    input  wire        icache_stall,   // I$ miss — stall IF
    input  wire        dcache_stall,   // D$ miss — stall MEM (and all upstream)

    // Stall/flush outputs
    output wire        pc_stall,       // stall PC register
    output wire        if_id_stall,    // stall IF/ID register
    output wire        if_id_flush,    // flush IF/ID (insert bubble)
    output wire        id_ex_flush,    // flush ID/EX (insert bubble)
    output wire        id_ex_stall,    // stall ID/EX (hold for D$ miss)
    output wire        ex_mem_stall,   // stall EX/MEM (hold for D$ miss)
    output wire        mem_wb_flush,   // flush MEM/WB (reserved; not used for D$ — use stall instead)
    output wire        mem_wb_stall,   // stall MEM/WB (hold for D$ miss — preserves forwarding)

    // Forwarding mux selects
    // 2'b00 = register file, 2'b01 = MEM/WB wb_data, 2'b10 = EX/MEM alu_result
    output wire [1:0]  fwd_a,
    output wire [1:0]  fwd_b
);
    // ---- Load-use hazard ----
    wire load_use_hazard = id_ex_mem_re &&
                           (id_ex_rd != 5'b0) &&
                           ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

    // ---- Branch/jump flush ----
    // With the branch predictor: only mispredictions and JALR need a flush.
    // Correct predictions are handled transparently in IF; no flush required.
    wire flush_pipeline = mispredicted || ex_jalr;

    // ── Stall/flush logic ─────────────────────────────────────────────────
    // dcache_stall freezes everything from IF through MEM; branch flush deferred.
    // icache_stall and load_use behave identically: stall IF+ID, bubble ID/EX.

    // During a branch redirect, allow PC to take the target even if I$ fill is active.
    // (if_id_reg gives flush priority over stall, so the flush will clear IF/ID correctly.)
    assign pc_stall     = load_use_hazard || (icache_stall && !flush_pipeline) || dcache_stall;
    assign if_id_stall  = load_use_hazard || icache_stall || dcache_stall;

    // IF/ID flush: redirect must clear IF/ID even during an I$ miss.
    // dcache_stall defers branch flush (entire pipeline frozen); icache_stall does not.
    assign if_id_flush  = flush_pipeline && !load_use_hazard && !dcache_stall;

    // ID/EX flush: bubble on load-use / icache miss, or branch redirect
    //              (but NOT when dcache_stall is freezing that register)
    assign id_ex_flush  = (load_use_hazard || icache_stall) ||
                          (flush_pipeline && !dcache_stall);

    // D$-miss outputs: freeze entire pipeline up to and including MEM/WB.
    // MEM/WB is STALLED (not flushed) so the instruction in WB keeps its forwarding
    // data visible to the EX stage throughout the stall.  When the stall clears,
    // EX can still use MEM-EX forwarding from WB for the register that was in
    // flight (e.g. the base-address register of a load immediately after a store).
    assign id_ex_stall  = dcache_stall;
    assign ex_mem_stall = dcache_stall;
    assign mem_wb_flush = 1'b0;        // never flush MEM/WB via hazard unit
    assign mem_wb_stall = dcache_stall;

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
