`timescale 1ns/1ps
// synthesis_top.v — FPGA synthesis wrapper for core_top
// Target: Xilinx Artix-7 xc7a35tcpg236-1 (Basys3)
//
// Folds the 65-bit debug bus down to 16 LEDs so I/O count fits the package.
// The XOR folding ensures Vivado cannot trim any part of the datapath.
//
// Pin assignments are in fpga/basys3.xdc.
module synthesis_top (
    input  wire        clk,      // W5  — 100 MHz oscillator
    input  wire        btn_rst,  // T18 — BTNC (active HIGH on Basys3)
    output wire [15:0] leds      // LD0-LD15
);
    wire        rst_n = ~btn_rst;

    wire [31:0] debug_pc;
    wire [31:0] debug_wb_data;
    wire        debug_reg_we;

    core_top #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (32)
    ) u_core (
        .clk          (clk),
        .rst_n        (rst_n),
        .debug_pc     (debug_pc),
        .debug_wb_data(debug_wb_data),
        .debug_reg_we (debug_reg_we)
    );

    // Fold all debug bits onto 16 LEDs.
    // XOR ensures every bit participates → nothing is trimmed.
    assign leds = debug_pc[15:0]
                ^ debug_pc[31:16]
                ^ debug_wb_data[15:0]
                ^ debug_wb_data[31:16]
                ^ {15'b0, debug_reg_we};

endmodule
