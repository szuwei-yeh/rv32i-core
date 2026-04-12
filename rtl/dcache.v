`timescale 1ns/1ps
// D$ — write-back + write-allocate
// On read  hit : return data combinatorially, no stall.
// On write hit : register context for one cycle, commit via FF-driven CE (1-cycle stall).
// On read  miss: [writeback dirty line if needed] → fill LINE_WORDS+1 cycles → return data.
// On write miss: [writeback dirty line if needed] → fill LINE_WORDS+1 cycles → merge store.
//
// Timing note — two-stage fill pipeline:
//   Stage 1 (fill_word 0..LINE_WORDS-1): dmem_rd_data → fill_data_r  (fo=1, fast)
//   Stage 2 (fill_word 1..LINE_WORDS-1 + drain): fill_data_r → cache_data/D (short path)
//   This breaks the cache_tag→dmem_addr→rd_data(fo=207)→cache_data/D 12 ns path.
//   Miss penalty increases by exactly 1 cycle.
//
// NOTE: cache_data is four separate 2D arrays (cache_data0..3); see original comment.
module dcache #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter WAYS       = 1,
    parameter NUM_SETS   = 64,
    parameter LINE_WORDS = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  pipe_mem_re,
    input  wire                  pipe_mem_we,
    input  wire [2:0]            pipe_funct3,
    input  wire [ADDR_WIDTH-1:0] pipe_addr,
    input  wire [DATA_WIDTH-1:0] pipe_wr_data,
    output reg  [DATA_WIDTH-1:0] pipe_rd_data,
    output wire                  stall,

    output reg  [ADDR_WIDTH-1:0] dmem_addr,
    output reg                   dmem_we,
    output reg  [2:0]            dmem_funct3,
    output reg  [DATA_WIDTH-1:0] dmem_wr_data,
    input  wire [DATA_WIDTH-1:0] dmem_rd_data,

    output reg  [31:0]           hit_count,
    output reg  [31:0]           miss_count
);
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

    localparam TAG_BITS = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS - 2;

    reg                  cache_valid [0:WAYS-1][0:NUM_SETS-1];
    reg                  cache_dirty [0:WAYS-1][0:NUM_SETS-1];
    reg [TAG_BITS-1:0]   cache_tag   [0:WAYS-1][0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0] cache_data0 [0:WAYS-1][0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0] cache_data1 [0:WAYS-1][0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0] cache_data2 [0:WAYS-1][0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0] cache_data3 [0:WAYS-1][0:NUM_SETS-1];

    reg lru [0:NUM_SETS-1];

    wire [OFFSET_BITS-1:0] addr_offset = pipe_addr[OFFSET_BITS+1:2];
    wire [INDEX_BITS-1:0]  addr_index  = pipe_addr[INDEX_BITS+OFFSET_BITS+1 : OFFSET_BITS+2];
    wire [TAG_BITS-1:0]    addr_tag    = pipe_addr[ADDR_WIDTH-1 : INDEX_BITS+OFFSET_BITS+2];
    wire [1:0]             addr_boff   = pipe_addr[1:0];

    wire hit_way0  = cache_valid[0][addr_index] && (cache_tag[0][addr_index] == addr_tag);
    wire hit_way1  = (WAYS > 1) &&
                     cache_valid[1][addr_index] && (cache_tag[1][addr_index] == addr_tag);
    wire cache_hit = hit_way0 || hit_way1;
    wire hit_sel   = hit_way1;

    wire evict_way   = (WAYS == 1) ? 1'b0 : lru[addr_index];
    wire evict_dirty = cache_valid[evict_way][addr_index] &&
                       cache_dirty[evict_way][addr_index];

    localparam S_IDLE      = 2'd0;
    localparam S_WRITEBACK = 2'd1;
    localparam S_FILL      = 2'd2;

    reg [1:0]              state;
    reg [OFFSET_BITS-1:0]  wb_word;
    reg [OFFSET_BITS-1:0]  fill_word;

    reg [TAG_BITS-1:0]     miss_tag;
    reg [INDEX_BITS-1:0]   miss_index;
    reg [OFFSET_BITS-1:0]  miss_offset;
    reg [1:0]              miss_boff;
    reg                    miss_way;
    reg                    miss_is_write;
    reg [DATA_WIDTH-1:0]   miss_wr_data;
    reg [2:0]              miss_funct3;

    // ── Registered write-hit (breaks pipe_addr→CE timing path) ───────────
    reg        pending_wr;
    reg        pending_way_r;
    reg [INDEX_BITS-1:0]  pending_index_r;
    reg [OFFSET_BITS-1:0] pending_offset_r;
    reg [1:0]             pending_boff_r;
    reg [2:0]             pending_fn3_r;
    reg [DATA_WIDTH-1:0]  pending_data_r;

    wire access_active = pipe_mem_re || pipe_mem_we;
    wire write_hit = (state == S_IDLE) && access_active
                     && cache_hit && pipe_mem_we && !pending_wr;

    assign stall = (state != S_IDLE) || (access_active && !cache_hit) || write_hit;

    // ── Pipelined fill register (breaks dmem_rd_data fo=207 timing path) ─
    // dmem_rd_data → fill_data_r : fo=1 (placed near dmem)
    // fill_data_r  → cache_data/D: short path from FF Q-pin
    // fill_extra=1 marks the one-cycle drain at the end of fill.
    reg [DATA_WIDTH-1:0]   fill_data_r;
    reg                    fill_extra;

    // ── hit_raw / read-data mux (combinatorial) ───────────────────────────
    reg [DATA_WIDTH-1:0] hit_raw;
    always @(*) begin
        case (addr_offset)
            2'd0: hit_raw = cache_data0[hit_sel][addr_index];
            2'd1: hit_raw = cache_data1[hit_sel][addr_index];
            2'd2: hit_raw = cache_data2[hit_sel][addr_index];
            default: hit_raw = cache_data3[hit_sel][addr_index];
        endcase
    end

    reg [DATA_WIDTH-1:0] hit_rd_mux;
    always @(*) begin
        case (pipe_funct3)
            3'b000: begin
                case (addr_boff)
                    2'b00: hit_rd_mux = {{24{hit_raw[ 7]}}, hit_raw[ 7: 0]};
                    2'b01: hit_rd_mux = {{24{hit_raw[15]}}, hit_raw[15: 8]};
                    2'b10: hit_rd_mux = {{24{hit_raw[23]}}, hit_raw[23:16]};
                    2'b11: hit_rd_mux = {{24{hit_raw[31]}}, hit_raw[31:24]};
                    default: hit_rd_mux = 32'h0;
                endcase
            end
            3'b001: begin
                case (addr_boff[1])
                    1'b0: hit_rd_mux = {{16{hit_raw[15]}}, hit_raw[15: 0]};
                    1'b1: hit_rd_mux = {{16{hit_raw[31]}}, hit_raw[31:16]};
                    default: hit_rd_mux = 32'h0;
                endcase
            end
            3'b010: hit_rd_mux = hit_raw;
            3'b100: begin
                case (addr_boff)
                    2'b00: hit_rd_mux = {24'b0, hit_raw[ 7: 0]};
                    2'b01: hit_rd_mux = {24'b0, hit_raw[15: 8]};
                    2'b10: hit_rd_mux = {24'b0, hit_raw[23:16]};
                    2'b11: hit_rd_mux = {24'b0, hit_raw[31:24]};
                    default: hit_rd_mux = 32'h0;
                endcase
            end
            3'b101: begin
                case (addr_boff[1])
                    1'b0: hit_rd_mux = {16'b0, hit_raw[15: 0]};
                    1'b1: hit_rd_mux = {16'b0, hit_raw[31:16]};
                    default: hit_rd_mux = 32'h0;
                endcase
            end
            default: hit_rd_mux = hit_raw;
        endcase
    end

    always @(*) begin
        if (cache_hit && pipe_mem_re && (state == S_IDLE))
            pipe_rd_data = hit_rd_mux;
        else
            pipe_rd_data = {DATA_WIDTH{1'b0}};
    end

    function [DATA_WIDTH-1:0] merge_store;
        input [DATA_WIDTH-1:0] old_word;
        input [DATA_WIDTH-1:0] wr;
        input [2:0]            fn3;
        input [1:0]            boff;
        reg   [DATA_WIDTH-1:0] r;
        begin
            r = old_word;
            case (fn3)
                3'b000: begin
                    case (boff)
                        2'b00: r[ 7: 0] = wr[7:0];
                        2'b01: r[15: 8] = wr[7:0];
                        2'b10: r[23:16] = wr[7:0];
                        2'b11: r[31:24] = wr[7:0];
                    endcase
                end
                3'b001: begin
                    case (boff[1])
                        1'b0: r[15: 0] = wr[15:0];
                        1'b1: r[31:16] = wr[15:0];
                    endcase
                end
                default: r = wr;
            endcase
            merge_store = r;
        end
    endfunction

    // ── dmem address steering (combinatorial) ─────────────────────────────
    always @(*) begin
        dmem_addr    = pipe_addr;
        dmem_we      = 1'b0;
        dmem_funct3  = 3'b010;
        dmem_wr_data = {DATA_WIDTH{1'b0}};
        case (state)
            S_WRITEBACK: begin
                dmem_addr   = {cache_tag[miss_way][miss_index],
                               miss_index, wb_word, 2'b00};
                dmem_we     = 1'b1;
                dmem_funct3 = 3'b010;
                case (wb_word)
                    2'd0: dmem_wr_data = cache_data0[miss_way][miss_index];
                    2'd1: dmem_wr_data = cache_data1[miss_way][miss_index];
                    2'd2: dmem_wr_data = cache_data2[miss_way][miss_index];
                    default: dmem_wr_data = cache_data3[miss_way][miss_index];
                endcase
            end
            S_FILL: begin
                // During drain (fill_extra=1) fill_word is already LINE_WORDS-1;
                // dmem is no longer needed but address is harmless.
                dmem_addr   = {miss_tag, miss_index, fill_word, 2'b00};
                dmem_we     = 1'b0;
                dmem_funct3 = 3'b010;
            end
            default: ;
        endcase
    end

    // ── Sequential logic ──────────────────────────────────────────────────
    integer ii, jj;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            wb_word      <= {OFFSET_BITS{1'b0}};
            fill_word    <= {OFFSET_BITS{1'b0}};
            fill_extra   <= 1'b0;
            hit_count    <= 32'b0;
            miss_count   <= 32'b0;
            pending_wr   <= 1'b0;
            for (ii = 0; ii < WAYS; ii = ii + 1)
                for (jj = 0; jj < NUM_SETS; jj = jj + 1) begin
                    cache_valid[ii][jj] <= 1'b0;
                    cache_dirty[ii][jj] <= 1'b0;
                    lru[jj]             <= 1'b0;
                end
        end else begin

            // ── 1. Write-hit registration ──────────────────────────────────
            pending_wr <= write_hit;
            if (write_hit) begin
                pending_way_r    <= hit_sel;
                pending_index_r  <= addr_index;
                pending_offset_r <= addr_offset;
                pending_boff_r   <= addr_boff;
                pending_fn3_r    <= pipe_funct3;
                pending_data_r   <= pipe_wr_data;
            end

            // ── 2. Write-hit commit (CE from FF Q-pins → fast path) ────────
            if (pending_wr) begin
                case (pending_offset_r)
                    2'd0: cache_data0[pending_way_r][pending_index_r] <=
                              merge_store(cache_data0[pending_way_r][pending_index_r],
                                          pending_data_r, pending_fn3_r, pending_boff_r);
                    2'd1: cache_data1[pending_way_r][pending_index_r] <=
                              merge_store(cache_data1[pending_way_r][pending_index_r],
                                          pending_data_r, pending_fn3_r, pending_boff_r);
                    2'd2: cache_data2[pending_way_r][pending_index_r] <=
                              merge_store(cache_data2[pending_way_r][pending_index_r],
                                          pending_data_r, pending_fn3_r, pending_boff_r);
                    default: cache_data3[pending_way_r][pending_index_r] <=
                              merge_store(cache_data3[pending_way_r][pending_index_r],
                                          pending_data_r, pending_fn3_r, pending_boff_r);
                endcase
                cache_dirty[pending_way_r][pending_index_r] <= 1'b1;
            end

            // ── 3. FSM ─────────────────────────────────────────────────────
            case (state)

                // ── IDLE ──────────────────────────────────────────────────
                S_IDLE: begin
                    if (access_active && !pending_wr) begin
                        if (cache_hit) begin
                            hit_count <= hit_count + 1;
                            if (WAYS > 1) lru[addr_index] <= hit_sel;
                            // Write hit deferred to step 2 above.
                        end else begin
                            miss_count    <= miss_count + 1;
                            miss_tag      <= addr_tag;
                            miss_index    <= addr_index;
                            miss_offset   <= addr_offset;
                            miss_boff     <= addr_boff;
                            miss_way      <= evict_way;
                            miss_is_write <= pipe_mem_we;
                            miss_wr_data  <= pipe_wr_data;
                            miss_funct3   <= pipe_funct3;
                            if (evict_dirty) begin
                                wb_word <= {OFFSET_BITS{1'b0}};
                                state   <= S_WRITEBACK;
                            end else begin
                                cache_valid[evict_way][addr_index] <= 1'b0;
                                fill_word  <= {OFFSET_BITS{1'b0}};
                                fill_extra <= 1'b0;
                                state      <= S_FILL;
                            end
                        end
                    end
                end

                // ── WRITEBACK ─────────────────────────────────────────────
                S_WRITEBACK: begin
                    if (wb_word == LINE_WORDS - 1) begin
                        cache_valid[miss_way][miss_index] <= 1'b0;
                        cache_dirty[miss_way][miss_index] <= 1'b0;
                        wb_word    <= {OFFSET_BITS{1'b0}};
                        fill_word  <= {OFFSET_BITS{1'b0}};
                        fill_extra <= 1'b0;
                        state      <= S_FILL;
                    end else begin
                        wb_word <= wb_word + 1;
                    end
                end

                // ── FILL (pipelined) ───────────────────────────────────────
                // Cycle N   : dmem presents word fill_word → captured into fill_data_r
                // Cycle N+1 : fill_data_r written to cache_data[fill_word-1]
                // Extra drain cycle writes the final word and validates the line.
                S_FILL: begin
                    // Stage 1: latch dmem read data (fo=1 → fast routing)
                    fill_data_r <= dmem_rd_data;

                    if (fill_extra) begin
                        // ── Drain cycle: write word LINE_WORDS-1 ────────────
                        // fill_data_r now holds dmem word LINE_WORDS-1
                        if (miss_is_write && miss_offset == LINE_WORDS - 1) begin
                            // Write-allocate for the last word
                            case (LINE_WORDS - 1)
                                2'd0: cache_data0[miss_way][miss_index] <=
                                          merge_store(fill_data_r, miss_wr_data,
                                                      miss_funct3, miss_boff);
                                2'd1: cache_data1[miss_way][miss_index] <=
                                          merge_store(fill_data_r, miss_wr_data,
                                                      miss_funct3, miss_boff);
                                2'd2: cache_data2[miss_way][miss_index] <=
                                          merge_store(fill_data_r, miss_wr_data,
                                                      miss_funct3, miss_boff);
                                default: cache_data3[miss_way][miss_index] <=
                                          merge_store(fill_data_r, miss_wr_data,
                                                      miss_funct3, miss_boff);
                            endcase
                        end else begin
                            case (LINE_WORDS - 1)
                                2'd0: cache_data0[miss_way][miss_index] <= fill_data_r;
                                2'd1: cache_data1[miss_way][miss_index] <= fill_data_r;
                                2'd2: cache_data2[miss_way][miss_index] <= fill_data_r;
                                default: cache_data3[miss_way][miss_index] <= fill_data_r;
                            endcase
                        end

                        // Validate cache line
                        cache_valid[miss_way][miss_index] <= 1'b1;
                        cache_tag  [miss_way][miss_index] <= miss_tag;
                        if (WAYS > 1) lru[miss_index] <= miss_way;
                        cache_dirty[miss_way][miss_index] <= miss_is_write ? 1'b1 : 1'b0;

                        fill_extra <= 1'b0;
                        fill_word  <= {OFFSET_BITS{1'b0}};
                        state      <= S_IDLE;

                    end else begin
                        // ── Normal fill cycle ────────────────────────────────
                        // Stage 2: write fill_data_r (= dmem word fill_word-1)
                        // to cache_data[fill_word-1], applying write-allocate if needed.
                        if (fill_word > 0) begin
                            // write_word = fill_word - 1
                            case (fill_word - 2'b01)
                                2'd0: cache_data0[miss_way][miss_index] <=
                                          (miss_is_write && miss_offset == 2'd0)
                                              ? merge_store(fill_data_r, miss_wr_data,
                                                            miss_funct3, miss_boff)
                                              : fill_data_r;
                                2'd1: cache_data1[miss_way][miss_index] <=
                                          (miss_is_write && miss_offset == 2'd1)
                                              ? merge_store(fill_data_r, miss_wr_data,
                                                            miss_funct3, miss_boff)
                                              : fill_data_r;
                                default: cache_data2[miss_way][miss_index] <=
                                          (miss_is_write && miss_offset == 2'd2)
                                              ? merge_store(fill_data_r, miss_wr_data,
                                                            miss_funct3, miss_boff)
                                              : fill_data_r;
                            endcase
                        end

                        // Advance counter; enter drain on last word
                        if (fill_word == LINE_WORDS - 1) begin
                            fill_extra <= 1'b1;
                            // Keep fill_word at LINE_WORDS-1 for drain reference
                        end else begin
                            fill_word <= fill_word + 1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
