`timescale 1ns/1ps
// Program Counter Register
// Supports stall (hold current PC) and synchronous reset
module pc_reg #(
    parameter ADDR_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  stall,
    input  wire [ADDR_WIDTH-1:0] pc_next,
    output reg  [ADDR_WIDTH-1:0] pc
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= {ADDR_WIDTH{1'b0}};
        else if (!stall)
            pc <= pc_next;
    end
endmodule
