`timescale 1ns/1ps
// Data Memory — synchronous write, asynchronous read
// Supports byte, halfword, word accesses (funct3 encoding matches RV32I load/store)
module dmem #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 1024
)(
    input  wire                  clk,
    input  wire                  mem_we,
    input  wire [2:0]            funct3,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire [DATA_WIDTH-1:0] rd_data
);
// synthesis translate_off
    // Simulation-only memory array.
    // Synthesis black box: Vivado sees only ports, not the array, preventing
    // the optimizer from inferring constant read data and trimming the cache.
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = 32'h0;
    end

    wire [ADDR_WIDTH-1:0] word_addr = {{(ADDR_WIDTH-2){1'b0}}, addr[ADDR_WIDTH-1:2]};
    wire [1:0]            byte_off  = addr[1:0];

    // --- Asynchronous read with sign/zero extension ---
    // Use wire to avoid spurious @* sensitivity-to-whole-array warning
    wire [DATA_WIDTH-1:0] rd_raw = mem[word_addr];

    reg  [DATA_WIDTH-1:0] rd_mux;
    always @(*) begin
        case (funct3)
            3'b000: begin // LB
                case (byte_off)
                    2'b00: rd_mux = {{24{rd_raw[ 7]}}, rd_raw[ 7: 0]};
                    2'b01: rd_mux = {{24{rd_raw[15]}}, rd_raw[15: 8]};
                    2'b10: rd_mux = {{24{rd_raw[23]}}, rd_raw[23:16]};
                    2'b11: rd_mux = {{24{rd_raw[31]}}, rd_raw[31:24]};
                    default: rd_mux = 32'h0; // unreachable; 2-bit fully covered
                endcase
            end
            3'b001: begin // LH
                case (byte_off[1])
                    1'b0: rd_mux = {{16{rd_raw[15]}}, rd_raw[15: 0]};
                    1'b1: rd_mux = {{16{rd_raw[31]}}, rd_raw[31:16]};
                    default: rd_mux = 32'h0; // unreachable; 1-bit fully covered
                endcase
            end
            3'b010: rd_mux = rd_raw; // LW
            3'b100: begin // LBU
                case (byte_off)
                    2'b00: rd_mux = {24'b0, rd_raw[ 7: 0]};
                    2'b01: rd_mux = {24'b0, rd_raw[15: 8]};
                    2'b10: rd_mux = {24'b0, rd_raw[23:16]};
                    2'b11: rd_mux = {24'b0, rd_raw[31:24]};
                    default: rd_mux = 32'h0; // unreachable; 2-bit fully covered
                endcase
            end
            3'b101: begin // LHU
                case (byte_off[1])
                    1'b0: rd_mux = {16'b0, rd_raw[15: 0]};
                    1'b1: rd_mux = {16'b0, rd_raw[31:16]};
                    default: rd_mux = 32'h0; // unreachable; 1-bit fully covered
                endcase
            end
            default: rd_mux = rd_raw;
        endcase
    end
    assign rd_data = rd_mux;

    // --- Synchronous write ---
    always @(posedge clk) begin
        if (mem_we) begin
            case (funct3)
                3'b000: begin // SB
                    case (byte_off)
                        2'b00: mem[word_addr][ 7: 0] <= wr_data[7:0];
                        2'b01: mem[word_addr][15: 8] <= wr_data[7:0];
                        2'b10: mem[word_addr][23:16] <= wr_data[7:0];
                        2'b11: mem[word_addr][31:24] <= wr_data[7:0];
                        default: ; // 2-bit fully covered; suppress synthesis warning
                    endcase
                end
                3'b001: begin // SH
                    case (byte_off[1])
                        1'b0: mem[word_addr][15: 0] <= wr_data[15:0];
                        1'b1: mem[word_addr][31:16] <= wr_data[15:0];
                        default: ; // 1-bit fully covered; suppress synthesis warning
                    endcase
                end
                default: mem[word_addr] <= wr_data; // SW (and default)
            endcase
        end
    end
// synthesis translate_on
endmodule
