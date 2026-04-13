`timescale 1ns/1ps
// axi4lite_mem.v — Dual-port memory: AXI4-Lite slave + core-facing port
//
// Port A (AXI4-Lite slave):  host reads/writes — used to load programs/data
//                            while the processor core is held in reset.
// Port B (core-facing):      cache backing store — async read, synchronous write.
//                            Interface is identical to dmem.v so this module is
//                            a drop-in replacement for both imem and dmem.
//
// Priority: when both ports attempt a write in the same cycle (should not
// happen during normal operation), the core write takes priority.
//
// AXI4-Lite address mapping: byte address; word = addr[ADDR_WIDTH-1:2].
// Out-of-range accesses wrap silently (addr is masked to MEM_DEPTH-1).
//
(* dont_touch = "yes" *) module axi4lite_mem #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 4096    // word depth; byte range = MEM_DEPTH * 4
)(
    input  wire clk,
    input  wire rst_n,

    // ── AXI4-Lite slave — write address channel ──────────────────────────────
    input  wire [ADDR_WIDTH-1:0]   s_awaddr,
    input  wire                    s_awvalid,
    output reg                     s_awready,

    // ── AXI4-Lite slave — write data channel ─────────────────────────────────
    input  wire [DATA_WIDTH-1:0]   s_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_wstrb,
    input  wire                    s_wvalid,
    output reg                     s_wready,

    // ── AXI4-Lite slave — write response channel ─────────────────────────────
    output reg  [1:0]              s_bresp,
    output reg                     s_bvalid,
    input  wire                    s_bready,

    // ── AXI4-Lite slave — read address channel ────────────────────────────────
    input  wire [ADDR_WIDTH-1:0]   s_araddr,
    input  wire                    s_arvalid,
    output reg                     s_arready,

    // ── AXI4-Lite slave — read data channel ──────────────────────────────────
    output reg  [DATA_WIDTH-1:0]   s_rdata,
    output reg  [1:0]              s_rresp,
    output reg                     s_rvalid,
    input  wire                    s_rready,

    // ── Core-facing port (same interface as dmem.v) ───────────────────────────
    // Tie core_we=0 and core_funct3=3'b010 when used as instruction-memory backing store.
    input  wire [ADDR_WIDTH-1:0]   core_addr,
    input  wire                    core_we,
    input  wire [2:0]              core_funct3,
    input  wire [DATA_WIDTH-1:0]   core_wr_data,
    output wire [DATA_WIDTH-1:0]   core_rd_data
);

    // ── Memory array ─────────────────────────────────────────────────────────
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // synthesis translate_off
    integer ii;
    initial begin
        for (ii = 0; ii < MEM_DEPTH; ii = ii + 1)
            mem[ii] = 32'h0;
    end
    // synthesis translate_on

    // ─────────────────────────────────────────────────────────────────────────
    // Core-facing: asynchronous read (mirrors dmem.v)
    // ─────────────────────────────────────────────────────────────────────────
    wire [ADDR_WIDTH-1:0] core_word_addr = {{(ADDR_WIDTH-2){1'b0}}, core_addr[ADDR_WIDTH-1:2]};
    wire [1:0]            core_byte_off  = core_addr[1:0];
    wire [DATA_WIDTH-1:0] core_rd_raw    = mem[core_word_addr];

    reg  [DATA_WIDTH-1:0] core_rd_mux;
    always @(*) begin
        case (core_funct3)
            3'b000: begin // LB
                case (core_byte_off)
                    2'b00: core_rd_mux = {{24{core_rd_raw[ 7]}}, core_rd_raw[ 7: 0]};
                    2'b01: core_rd_mux = {{24{core_rd_raw[15]}}, core_rd_raw[15: 8]};
                    2'b10: core_rd_mux = {{24{core_rd_raw[23]}}, core_rd_raw[23:16]};
                    default: core_rd_mux = {{24{core_rd_raw[31]}}, core_rd_raw[31:24]};
                endcase
            end
            3'b001: begin // LH
                case (core_byte_off[1])
                    1'b0:    core_rd_mux = {{16{core_rd_raw[15]}}, core_rd_raw[15: 0]};
                    default: core_rd_mux = {{16{core_rd_raw[31]}}, core_rd_raw[31:16]};
                endcase
            end
            3'b010: core_rd_mux = core_rd_raw; // LW
            3'b100: begin // LBU
                case (core_byte_off)
                    2'b00: core_rd_mux = {24'b0, core_rd_raw[ 7: 0]};
                    2'b01: core_rd_mux = {24'b0, core_rd_raw[15: 8]};
                    2'b10: core_rd_mux = {24'b0, core_rd_raw[23:16]};
                    default: core_rd_mux = {24'b0, core_rd_raw[31:24]};
                endcase
            end
            3'b101: begin // LHU
                case (core_byte_off[1])
                    1'b0:    core_rd_mux = {16'b0, core_rd_raw[15: 0]};
                    default: core_rd_mux = {16'b0, core_rd_raw[31:16]};
                endcase
            end
            default: core_rd_mux = core_rd_raw;
        endcase
    end
    assign core_rd_data = core_rd_mux;

    // ─────────────────────────────────────────────────────────────────────────
    // AXI4-Lite write channel — state machine
    // Accepts AW and W independently; performs the write once both arrive.
    // ─────────────────────────────────────────────────────────────────────────
    reg                    aw_done;    // AW handshake captured
    reg                    w_done;     // W  handshake captured
    reg [ADDR_WIDTH-1:0]   aw_addr_r;  // latched write address
    reg [DATA_WIDTH-1:0]   w_data_r;   // latched write data
    reg [DATA_WIDTH/8-1:0] w_strb_r;   // latched byte strobes

    wire do_axi_write = aw_done && w_done && !s_bvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_awready <= 1'b0;
            s_wready  <= 1'b0;
            s_bvalid  <= 1'b0;
            s_bresp   <= 2'b00;
            aw_done   <= 1'b0;
            w_done    <= 1'b0;
            aw_addr_r <= {ADDR_WIDTH{1'b0}};
            w_data_r  <= {DATA_WIDTH{1'b0}};
            w_strb_r  <= {(DATA_WIDTH/8){1'b0}};
        end else begin
            // Single-cycle ready pulses
            s_awready <= 1'b0;
            s_wready  <= 1'b0;

            // Capture write address
            if (!aw_done && s_awvalid) begin
                s_awready <= 1'b1;
                aw_addr_r <= s_awaddr;
                aw_done   <= 1'b1;
            end

            // Capture write data
            if (!w_done && s_wvalid) begin
                s_wready <= 1'b1;
                w_data_r <= s_wdata;
                w_strb_r <= s_wstrb;
                w_done   <= 1'b1;
            end

            // Send B response after write committed; clear flags
            if (do_axi_write) begin
                s_bresp  <= 2'b00; // OKAY
                s_bvalid <= 1'b1;
                aw_done  <= 1'b0;
                w_done   <= 1'b0;
            end

            // Release B channel after master accepts
            if (s_bvalid && s_bready)
                s_bvalid <= 1'b0;
        end
    end

    // ─────────────────────────────────────────────────────────────────────────
    // AXI4-Lite read channel
    // ─────────────────────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_arready <= 1'b0;
            s_rvalid  <= 1'b0;
            s_rdata   <= {DATA_WIDTH{1'b0}};
            s_rresp   <= 2'b00;
        end else begin
            s_arready <= 1'b0;

            if (!s_rvalid && s_arvalid) begin
                s_arready <= 1'b1;
                s_rdata   <= mem[s_araddr[ADDR_WIDTH-1:2]];
                s_rresp   <= 2'b00; // OKAY
                s_rvalid  <= 1'b1;
            end

            if (s_rvalid && s_rready)
                s_rvalid <= 1'b0;
        end
    end

    // ─────────────────────────────────────────────────────────────────────────
    // Combined memory write (single always block avoids multi-driver)
    // Core write takes priority over AXI write.
    // ─────────────────────────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (core_we) begin
            // Core (D$) synchronous write — same sub-word logic as dmem.v
            case (core_funct3)
                3'b000: begin // SB
                    case (core_byte_off)
                        2'b00: mem[core_word_addr][ 7: 0] <= core_wr_data[7:0];
                        2'b01: mem[core_word_addr][15: 8] <= core_wr_data[7:0];
                        2'b10: mem[core_word_addr][23:16] <= core_wr_data[7:0];
                        default: mem[core_word_addr][31:24] <= core_wr_data[7:0];
                    endcase
                end
                3'b001: begin // SH
                    case (core_byte_off[1])
                        1'b0:    mem[core_word_addr][15: 0] <= core_wr_data[15:0];
                        default: mem[core_word_addr][31:16] <= core_wr_data[15:0];
                    endcase
                end
                default: mem[core_word_addr] <= core_wr_data; // SW
            endcase
        end else if (do_axi_write) begin
            // AXI byte-strobe write — used during host program loading
            if (w_strb_r[0]) mem[aw_addr_r[ADDR_WIDTH-1:2]][ 7: 0] <= w_data_r[ 7: 0];
            if (w_strb_r[1]) mem[aw_addr_r[ADDR_WIDTH-1:2]][15: 8] <= w_data_r[15: 8];
            if (w_strb_r[2]) mem[aw_addr_r[ADDR_WIDTH-1:2]][23:16] <= w_data_r[23:16];
            if (w_strb_r[3]) mem[aw_addr_r[ADDR_WIDTH-1:2]][31:24] <= w_data_r[31:24];
        end
    end

endmodule
