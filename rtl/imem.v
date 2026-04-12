`timescale 1ns/1ps
// Instruction Memory
// Simulation : initialised via $readmemh("sim/program.hex", mem)
// Synthesis  : (* dont_touch = "yes" *) prevents Vivado from constant-propagating
//              through the uninitialised array and trimming the downstream pipeline.
//              The array is visible so imem is NOT a black box and implementation
//              can place it; the initial block is hidden from synthesis.
(* dont_touch = "yes" *) module imem #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 4096
)(
    input  wire [ADDR_WIDTH-1:0] addr,
    output wire [DATA_WIDTH-1:0] instr
);
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // synthesis translate_off
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = 32'h00000013; // NOP (ADDI x0,x0,0)
        $readmemh("sim/program.hex", mem);
    end
    // synthesis translate_on

    assign instr = mem[addr[ADDR_WIDTH-1:2]];
endmodule
