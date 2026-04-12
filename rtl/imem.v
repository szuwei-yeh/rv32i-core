`timescale 1ns/1ps
// Instruction Memory — read-only, initialized from hex file
// Word-addressed (PC bits [1:0] ignored)
module imem #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 4096
)(
    input  wire [ADDR_WIDTH-1:0] addr,
    output wire [DATA_WIDTH-1:0] instr
);
// synthesis translate_off
    // Simulation-only implementation.
    // For synthesis this module is intentionally a black box so that Vivado
    // cannot constant-propagate through uninitialized memory and trim the
    // entire downstream pipeline.
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = 32'h00000013; // NOP (ADDI x0,x0,0)
        $readmemh("sim/program.hex", mem);
    end
    assign instr = mem[addr[ADDR_WIDTH-1:2]];
// synthesis translate_on
endmodule
