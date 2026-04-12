`timescale 1ns/1ps
// branch_predictor — 2-bit saturating BHT + BTB, direct-mapped (64 entries)
//
// Scope    : conditional branches (BEQ/BNE/BLT/BGE/BLTU/BGEU) and JAL.
//            JALR is NOT predicted (always 2-cycle penalty).
// Lookup   : combinatorial, from IF-stage PC.
// Update   : synchronous, from EX-stage resolved outcome.
//
// Address layout (ADDR_WIDTH=32, NUM_ENTRIES=64):
//   pc[1:0]  = ignored (word-aligned)
//   pc[7:2]  = index  (6 bits → 64 entries)
//   pc[31:8] = tag    (24 bits)
module branch_predictor #(
    parameter ADDR_WIDTH  = 32,
    parameter NUM_ENTRIES = 64
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // ── IF stage — combinatorial lookup ──────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0] if_pc,
    output wire                  pred_taken,   // 1 → redirect PC to pred_target
    output wire [ADDR_WIDTH-1:0] pred_target,  // predicted branch target

    // ── EX stage — synchronous update ────────────────────────────────────────
    input  wire                  ex_update_en,   // branch or JAL resolved in EX
    input  wire [ADDR_WIDTH-1:0] ex_pc,          // PC of the resolved instruction
    input  wire                  ex_taken,        // actual direction
    input  wire [ADDR_WIDTH-1:0] ex_target,       // actual target (valid when ex_taken=1)
    input  wire                  ex_mispredicted, // used only for performance counting

    // ── Performance counters ─────────────────────────────────────────────────
    output reg  [31:0]           branch_count,    // total branches/JALs resolved
    output reg  [31:0]           mispredict_count // total mispredictions
);
    localparam IDX_BITS = 6;                      // log2(64)
    localparam TAG_BITS = ADDR_WIDTH - IDX_BITS - 2; // 24

    // ── BHT: 2-bit saturating counters ───────────────────────────────────────
    reg [1:0]          bht        [0:NUM_ENTRIES-1];

    // ── BTB: valid + tag + target ─────────────────────────────────────────────
    reg                btb_valid  [0:NUM_ENTRIES-1];
    reg [TAG_BITS-1:0] btb_tag    [0:NUM_ENTRIES-1];
    reg [ADDR_WIDTH-1:0] btb_target [0:NUM_ENTRIES-1];

    // ── IF lookup (combinatorial) ─────────────────────────────────────────────
    wire [IDX_BITS-1:0] if_idx = if_pc[IDX_BITS+1 : 2];   // pc[7:2]
    wire [TAG_BITS-1:0] if_tag = if_pc[ADDR_WIDTH-1 : IDX_BITS+2]; // pc[31:8]

    wire btb_hit = btb_valid[if_idx] && (btb_tag[if_idx] == if_tag);

    assign pred_taken  = btb_hit && bht[if_idx][1]; // MSB=1 → predict taken
    assign pred_target = btb_target[if_idx];

    // ── EX update index ───────────────────────────────────────────────────────
    wire [IDX_BITS-1:0] ex_idx = ex_pc[IDX_BITS+1 : 2];
    wire [TAG_BITS-1:0] ex_tag = ex_pc[ADDR_WIDTH-1 : IDX_BITS+2];

    // ── EX-update pipeline stage (timing optimisation) ────────────────────────
    // Critical path: forwarding → ALU → ex_branch_taken → BTB CE ≈ 14.3 ns.
    // Registering all update signals by 1 clock breaks the ALU→CE path at the
    // cost of writing the BTB one cycle later — no functional impact because
    // the instruction that caused the update has already left EX by then.
    reg                  update_en_r;
    reg                  taken_r;
    reg [IDX_BITS-1:0]   idx_r;
    reg [TAG_BITS-1:0]   tag_r;
    reg [ADDR_WIDTH-1:0] target_r;
    reg                  mispredicted_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            update_en_r    <= 1'b0;
            taken_r        <= 1'b0;
            idx_r          <= {IDX_BITS{1'b0}};
            tag_r          <= {TAG_BITS{1'b0}};
            target_r       <= {ADDR_WIDTH{1'b0}};
            mispredicted_r <= 1'b0;
        end else begin
            update_en_r    <= ex_update_en;
            taken_r        <= ex_taken;
            idx_r          <= ex_idx;
            tag_r          <= ex_tag;
            target_r       <= ex_target;
            mispredicted_r <= ex_mispredicted;
        end
    end

    // ── Sequential logic (uses registered update signals) ─────────────────────
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                bht[i]        <= 2'b01;          // weakly not-taken at reset
                btb_valid[i]  <= 1'b0;
                btb_tag[i]    <= {TAG_BITS{1'b0}};
                btb_target[i] <= {ADDR_WIDTH{1'b0}};
            end
            branch_count     <= 32'b0;
            mispredict_count <= 32'b0;
        end else begin
            if (update_en_r) begin
                branch_count <= branch_count + 1;
                if (mispredicted_r)
                    mispredict_count <= mispredict_count + 1;

                // Update 2-bit saturating counter
                if (taken_r) begin
                    if (bht[idx_r] != 2'b11) bht[idx_r] <= bht[idx_r] + 1;
                    // Allocate / refresh BTB entry on taken
                    btb_valid[idx_r]  <= 1'b1;
                    btb_tag[idx_r]    <= tag_r;
                    btb_target[idx_r] <= target_r;
                end else begin
                    if (bht[idx_r] != 2'b00) bht[idx_r] <= bht[idx_r] - 1;
                    // Do NOT invalidate BTB on not-taken; keep last-known target
                end
            end
        end
    end

endmodule
