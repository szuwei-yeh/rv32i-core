`timescale 1ns/1ps
// I$ — direct-mapped or 2-way set-associative, write-through (read-only from pipeline)
// On miss: stall IF for LINE_WORDS cycles while filling one word/cycle from imem.
//
// NOTE: cache_data is implemented as four separate 2D arrays (cache_data0..3)
// instead of a single 3D array.  Icarus Verilog silently drops non-blocking
// assignments to 3D unpacked arrays, so a 3D array would leave all data as X.
module icache #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter WAYS       = 1,
    parameter NUM_SETS   = 64,
    parameter LINE_WORDS = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Pipeline IF-stage interface
    input  wire [ADDR_WIDTH-1:0] if_pc,       // fetch address (byte-addressed)
    output reg  [DATA_WIDTH-1:0] instr,        // instruction returned on hit
    output wire                  stall,        // asserted every cycle of a miss

    // Backing-memory interface (to imem)
    output reg  [ADDR_WIDTH-1:0] mem_addr,     // byte address driven to imem
    input  wire [DATA_WIDTH-1:0] mem_rdata,    // word returned by imem (combinatorial)

    // Performance counters
    output reg  [31:0]           hit_count,
    output reg  [31:0]           miss_count
);
    // ---------------------------------------------------------------
    // Address field widths (must be integer constants for Verilog-2001
    // array dimensions; $clog2 used only for bit-select ranges)
    // ---------------------------------------------------------------
    localparam OFFSET_BITS = (LINE_WORDS == 1) ? 0 :
                             (LINE_WORDS == 2) ? 1 :
                             (LINE_WORDS == 4) ? 2 :
                             (LINE_WORDS == 8) ? 3 : 4;

    localparam INDEX_BITS  = (NUM_SETS ==  1) ? 0 :
                             (NUM_SETS ==  2) ? 1 :
                             (NUM_SETS ==  4) ? 2 :
                             (NUM_SETS ==  8) ? 3 :
                             (NUM_SETS == 16) ? 4 :
                             (NUM_SETS == 32) ? 5 :
                             (NUM_SETS == 64) ? 6 :
                             (NUM_SETS ==128) ? 7 : 8;

    localparam TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS - 2;

    // ---------------------------------------------------------------
    // Cache arrays  [way][set]
    // Four separate 2D arrays, one per word-offset position.
    // ---------------------------------------------------------------
    reg                  cache_valid [0:WAYS-1][0:NUM_SETS-1];
    reg [TAG_BITS-1:0]   cache_tag   [0:WAYS-1][0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0] cache_data0 [0:WAYS-1][0:NUM_SETS-1]; // word offset 0
    reg [DATA_WIDTH-1:0] cache_data1 [0:WAYS-1][0:NUM_SETS-1]; // word offset 1
    reg [DATA_WIDTH-1:0] cache_data2 [0:WAYS-1][0:NUM_SETS-1]; // word offset 2
    reg [DATA_WIDTH-1:0] cache_data3 [0:WAYS-1][0:NUM_SETS-1]; // word offset 3

    // LRU bit per set (only meaningful when WAYS==2)
    reg lru [0:NUM_SETS-1];

    // ---------------------------------------------------------------
    // Address decode
    // ---------------------------------------------------------------
    wire [OFFSET_BITS-1:0] addr_offset = if_pc[OFFSET_BITS+1:2];
    wire [INDEX_BITS-1:0]  addr_index  = if_pc[INDEX_BITS+OFFSET_BITS+1 : OFFSET_BITS+2];
    wire [TAG_BITS-1:0]    addr_tag    = if_pc[ADDR_WIDTH-1 : INDEX_BITS+OFFSET_BITS+2];

    // ---------------------------------------------------------------
    // Hit detection (combinatorial)
    // ---------------------------------------------------------------
    wire hit_way0 = cache_valid[0][addr_index] && (cache_tag[0][addr_index] == addr_tag);
    wire hit_way1 = (WAYS > 1) &&
                    cache_valid[1][addr_index] && (cache_tag[1][addr_index] == addr_tag);
    wire cache_hit = hit_way0 || hit_way1;

    wire hit_sel   = hit_way1;   // 0 = way0, 1 = way1
    wire evict_way = (WAYS == 1) ? 1'b0 : lru[addr_index];

    // ---------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------
    localparam S_IDLE = 1'b0;
    localparam S_FILL = 1'b1;

    reg                    state;
    reg [OFFSET_BITS-1:0]  fill_word;   // which word we are currently filling
    reg [TAG_BITS-1:0]     fill_tag;    // tag of the line being filled
    reg [INDEX_BITS-1:0]   fill_index;  // set index of the line being filled
    reg                    fill_way;    // which way we are filling into

    assign stall = (state == S_FILL) || (!cache_hit && (state == S_IDLE));

    // ---------------------------------------------------------------
    // Output instruction mux (combinatorial)
    // ---------------------------------------------------------------
    always @(*) begin
        if (cache_hit) begin
            case (addr_offset)
                2'd0: instr = cache_data0[hit_sel][addr_index];
                2'd1: instr = cache_data1[hit_sel][addr_index];
                2'd2: instr = cache_data2[hit_sel][addr_index];
                default: instr = cache_data3[hit_sel][addr_index];
            endcase
        end else begin
            instr = {DATA_WIDTH{1'b0}};
        end
    end

    // ---------------------------------------------------------------
    // mem_addr during fill (combinatorial so imem sees it same cycle)
    // ---------------------------------------------------------------
    always @(*) begin
        if (state == S_FILL)
            mem_addr = {fill_tag, fill_index, fill_word, 2'b00};
        else
            mem_addr = if_pc;   // pass-through when idle
    end

    // ---------------------------------------------------------------
    // Sequential logic
    // ---------------------------------------------------------------
    integer i, j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            fill_word  <= {OFFSET_BITS{1'b0}};
            fill_tag   <= {TAG_BITS{1'b0}};
            fill_index <= {INDEX_BITS{1'b0}};
            fill_way   <= 1'b0;
            hit_count  <= 32'b0;
            miss_count <= 32'b0;
            for (i = 0; i < WAYS; i = i + 1) begin
                for (j = 0; j < NUM_SETS; j = j + 1) begin
                    cache_valid[i][j] <= 1'b0;
                    lru[j]            <= 1'b0;
                end
            end
        end else begin
            case (state)
                S_IDLE: begin
                    if (cache_hit) begin
                        hit_count <= hit_count + 1;
                        if (WAYS > 1)
                            lru[addr_index] <= hit_sel;
                    end else begin
                        // Miss — start fill
                        miss_count  <= miss_count + 1;
                        fill_tag    <= addr_tag;
                        fill_index  <= addr_index;
                        fill_way    <= evict_way;
                        fill_word   <= {OFFSET_BITS{1'b0}};
                        cache_valid[evict_way][addr_index] <= 1'b0;
                        state <= S_FILL;
                    end
                end

                S_FILL: begin
                    // Latch one word per cycle from imem (combinatorial read)
                    case (fill_word)
                        2'd0: cache_data0[fill_way][fill_index] <= mem_rdata;
                        2'd1: cache_data1[fill_way][fill_index] <= mem_rdata;
                        2'd2: cache_data2[fill_way][fill_index] <= mem_rdata;
                        default: cache_data3[fill_way][fill_index] <= mem_rdata;
                    endcase

                    if (fill_word == LINE_WORDS - 1) begin
                        // Last word — validate the line and return to IDLE
                        cache_valid[fill_way][fill_index] <= 1'b1;
                        cache_tag  [fill_way][fill_index] <= fill_tag;
                        if (WAYS > 1)
                            lru[fill_index] <= fill_way;
                        fill_word <= {OFFSET_BITS{1'b0}};
                        state     <= S_IDLE;
                    end else begin
                        fill_word <= fill_word + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
