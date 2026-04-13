`timescale 1ns/1ps
// Arithmetic Logic Unit — full RV32I operation set
module alu #(
    parameter DATA_WIDTH = 32
)(
    input  wire [3:0]            alu_ctrl,
    input  wire [DATA_WIDTH-1:0] a,
    input  wire [DATA_WIDTH-1:0] b,
    output reg  [DATA_WIDTH-1:0] result,
    output wire                  zero
);
    // ALU control encoding
    localparam ADD  = 4'b0000;
    localparam SUB  = 4'b0001;
    localparam AND  = 4'b0010;
    localparam OR   = 4'b0011;
    localparam XOR  = 4'b0100;
    localparam SLL  = 4'b0101;
    localparam SRL  = 4'b0110;
    localparam SRA  = 4'b0111;
    localparam SLT  = 4'b1000;
    localparam SLTU = 4'b1001;
    localparam PASS = 4'b1010; // pass-through B (for LUI)

    always @(*) begin
        case (alu_ctrl)
            ADD:  result = a + b;
            SUB:  result = a - b;
            AND:  result = a & b;
            OR:   result = a | b;
            XOR:  result = a ^ b;
            SLL:  result = a << b[4:0];
            SRL:  result = a >> b[4:0];
            SRA:  result = $signed(a) >>> b[4:0];
            SLT:  result = ($signed(a) < $signed(b)) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1}
                                                      : {DATA_WIDTH{1'b0}};
            SLTU: result = (a < b) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1}
                                   : {DATA_WIDTH{1'b0}};
            PASS: result = b;
            default: result = {DATA_WIDTH{1'b0}};
        endcase
    end

    assign zero = (result == {DATA_WIDTH{1'b0}});
endmodule
