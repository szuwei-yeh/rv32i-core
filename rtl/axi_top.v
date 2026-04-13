`timescale 1ns/1ps
// axi_top.v — AXI4-Lite synthesis wrapper for the RV32I core
//
// This module replaces the standalone synthesis_top for designs where the host
// (e.g. a Zynq PS, a DMA controller, or a test-bench AXI master) needs to:
//   1. Load a program into instruction memory via AXI4-Lite (s_imem_* ports)
//   2. Pre-populate or inspect data memory via AXI4-Lite (s_dmem_* ports)
//   3. Observe the processor's debug outputs (debug_pc, etc.)
//
// Typical bring-up sequence:
//   a) Assert rst_n = 0 (core in reset)
//   b) Write program binary word-by-word to s_imem (byte addresses 0 …)
//   c) Write initial data to s_dmem if needed
//   d) De-assert rst_n = 1 → core starts fetching from address 0
//
// Memory map (each AXI port has its own independent address space from 0):
//   s_imem : 0x0000_0000 … 0x0000_3FFF  (IMEM_DEPTH × 4 bytes = 16 KB)
//   s_dmem : 0x0000_0000 … 0x0000_0FFF  (DMEM_DEPTH × 4 bytes =  4 KB)
//
// The two AXI4-Lite slaves are separate buses; no interconnect or address
// decoder is included — add one externally if a single AXI master drives both.
//
// NOTE: axi4lite_mem uses (* dont_touch = "yes" *) to prevent Vivado from
// constant-propagating through the uninitialised BRAM arrays.  The internal
// u_imem / u_dmem inside core_top also exist (USE_EXT_MEM=1 muxes them out)
// but their dont_touch attribute keeps them in the netlist harmlessly.

module axi_top #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter IMEM_DEPTH  = 4096,   // instruction memory word depth (16 KB)
    parameter DMEM_DEPTH  = 1024    // data memory word depth         ( 4 KB)
)(
    input  wire clk,
    input  wire rst_n,

    // ── AXI4-Lite Slave: Instruction Memory ──────────────────────────────────
    input  wire [ADDR_WIDTH-1:0]   s_imem_awaddr,
    input  wire                    s_imem_awvalid,
    output wire                    s_imem_awready,
    input  wire [DATA_WIDTH-1:0]   s_imem_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_imem_wstrb,
    input  wire                    s_imem_wvalid,
    output wire                    s_imem_wready,
    output wire [1:0]              s_imem_bresp,
    output wire                    s_imem_bvalid,
    input  wire                    s_imem_bready,
    input  wire [ADDR_WIDTH-1:0]   s_imem_araddr,
    input  wire                    s_imem_arvalid,
    output wire                    s_imem_arready,
    output wire [DATA_WIDTH-1:0]   s_imem_rdata,
    output wire [1:0]              s_imem_rresp,
    output wire                    s_imem_rvalid,
    input  wire                    s_imem_rready,

    // ── AXI4-Lite Slave: Data Memory ─────────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0]   s_dmem_awaddr,
    input  wire                    s_dmem_awvalid,
    output wire                    s_dmem_awready,
    input  wire [DATA_WIDTH-1:0]   s_dmem_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_dmem_wstrb,
    input  wire                    s_dmem_wvalid,
    output wire                    s_dmem_wready,
    output wire [1:0]              s_dmem_bresp,
    output wire                    s_dmem_bvalid,
    input  wire                    s_dmem_bready,
    input  wire [ADDR_WIDTH-1:0]   s_dmem_araddr,
    input  wire                    s_dmem_arvalid,
    output wire                    s_dmem_arready,
    output wire [DATA_WIDTH-1:0]   s_dmem_rdata,
    output wire [1:0]              s_dmem_rresp,
    output wire                    s_dmem_rvalid,
    input  wire                    s_dmem_rready,

    // ── Debug outputs (observe IF-stage PC and WB-stage writeback) ────────────
    output wire [DATA_WIDTH-1:0]   debug_pc,
    output wire [DATA_WIDTH-1:0]   debug_wb_data,
    output wire                    debug_reg_we
);

    // ── External memory interface wires (between core_top and axi4lite_mem) ──
    wire [ADDR_WIDTH-1:0] ext_imem_addr;
    wire [DATA_WIDTH-1:0] ext_imem_rdata;

    wire [ADDR_WIDTH-1:0] ext_dmem_addr;
    wire                  ext_dmem_we;
    wire [2:0]            ext_dmem_funct3;
    wire [DATA_WIDTH-1:0] ext_dmem_wr_data;
    wire [DATA_WIDTH-1:0] ext_dmem_rdata;

    // ── RV32I core (external-memory mode) ─────────────────────────────────────
    core_top #(
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .USE_EXT_MEM (1)
    ) u_core (
        .clk              (clk),
        .rst_n            (rst_n),
        .debug_pc         (debug_pc),
        .debug_wb_data    (debug_wb_data),
        .debug_reg_we     (debug_reg_we),
        // External backing-memory connections
        .ext_imem_addr    (ext_imem_addr),
        .ext_imem_rdata   (ext_imem_rdata),
        .ext_dmem_addr    (ext_dmem_addr),
        .ext_dmem_we      (ext_dmem_we),
        .ext_dmem_funct3  (ext_dmem_funct3),
        .ext_dmem_wr_data (ext_dmem_wr_data),
        .ext_dmem_rdata   (ext_dmem_rdata)
    );

    // ── AXI4-Lite instruction memory ─────────────────────────────────────────
    // core_we=0: I-cache never writes back to instruction memory.
    // core_funct3=010 (LW): cache fills always read whole 32-bit words.
    axi4lite_mem #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .MEM_DEPTH  (IMEM_DEPTH)
    ) u_imem_axi (
        .clk         (clk),
        .rst_n       (rst_n),
        // AXI4-Lite slave
        .s_awaddr    (s_imem_awaddr),
        .s_awvalid   (s_imem_awvalid),
        .s_awready   (s_imem_awready),
        .s_wdata     (s_imem_wdata),
        .s_wstrb     (s_imem_wstrb),
        .s_wvalid    (s_imem_wvalid),
        .s_wready    (s_imem_wready),
        .s_bresp     (s_imem_bresp),
        .s_bvalid    (s_imem_bvalid),
        .s_bready    (s_imem_bready),
        .s_araddr    (s_imem_araddr),
        .s_arvalid   (s_imem_arvalid),
        .s_arready   (s_imem_arready),
        .s_rdata     (s_imem_rdata),
        .s_rresp     (s_imem_rresp),
        .s_rvalid    (s_imem_rvalid),
        .s_rready    (s_imem_rready),
        // Core-facing (read-only from I$ perspective)
        .core_addr     (ext_imem_addr),
        .core_we       (1'b0),
        .core_funct3   (3'b010),
        .core_wr_data  ({DATA_WIDTH{1'b0}}),
        .core_rd_data  (ext_imem_rdata)
    );

    // ── AXI4-Lite data memory ─────────────────────────────────────────────────
    axi4lite_mem #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .MEM_DEPTH  (DMEM_DEPTH)
    ) u_dmem_axi (
        .clk         (clk),
        .rst_n       (rst_n),
        // AXI4-Lite slave
        .s_awaddr    (s_dmem_awaddr),
        .s_awvalid   (s_dmem_awvalid),
        .s_awready   (s_dmem_awready),
        .s_wdata     (s_dmem_wdata),
        .s_wstrb     (s_dmem_wstrb),
        .s_wvalid    (s_dmem_wvalid),
        .s_wready    (s_dmem_wready),
        .s_bresp     (s_dmem_bresp),
        .s_bvalid    (s_dmem_bvalid),
        .s_bready    (s_dmem_bready),
        .s_araddr    (s_dmem_araddr),
        .s_arvalid   (s_dmem_arvalid),
        .s_arready   (s_dmem_arready),
        .s_rdata     (s_dmem_rdata),
        .s_rresp     (s_dmem_rresp),
        .s_rvalid    (s_dmem_rvalid),
        .s_rready    (s_dmem_rready),
        // Core-facing (D$ backing store — full read/write interface)
        .core_addr     (ext_dmem_addr),
        .core_we       (ext_dmem_we),
        .core_funct3   (ext_dmem_funct3),
        .core_wr_data  (ext_dmem_wr_data),
        .core_rd_data  (ext_dmem_rdata)
    );

endmodule
