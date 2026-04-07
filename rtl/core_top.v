`timescale 1ns/1ps
// RV32I 5-Stage Pipelined Processor — Top Level
// Stages: IF → ID → EX → MEM → WB
// Hazards: full forwarding (EX-EX, MEM-EX), load-use stall, branch flush (predict not-taken)
// Branch resolved in EX stage; flushes IF and ID on misprediction.

module core_top #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] debug_pc       // current IF-stage PC (for debug / ILA)
);
    // =========================================================
    // Wire declarations
    // =========================================================

    // IF stage
    wire [ADDR_WIDTH-1:0] if_pc;
    wire [ADDR_WIDTH-1:0] if_pc4;
    wire [DATA_WIDTH-1:0] if_instr;

    // debug_pc — direct view of the IF-stage program counter
    assign debug_pc = if_pc;

    // IF/ID register outputs (ID stage inputs)
    wire [ADDR_WIDTH-1:0] id_pc;
    wire [ADDR_WIDTH-1:0] id_pc4;
    wire [DATA_WIDTH-1:0] id_instr;

    // ID stage decode wires
    wire [6:0] id_opcode  = id_instr[6:0];
    wire [4:0] id_rd      = id_instr[11:7];
    wire [2:0] id_funct3  = id_instr[14:12];
    wire [4:0] id_rs1_addr = id_instr[19:15];
    wire [4:0] id_rs2_addr = id_instr[24:20];
    wire [6:0] id_funct7  = id_instr[31:25];

    // Immediate generation (combinational in ID stage)
    reg  [DATA_WIDTH-1:0] id_imm;
    wire [2:0] id_imm_sel;

    // Control signals (from control unit)
    wire [3:0] id_alu_ctrl;
    wire       id_alu_src_a;
    wire       id_alu_src_b;
    wire       id_reg_we;
    wire       id_mem_we;
    wire       id_mem_re;
    wire [1:0] id_wb_sel;
    wire       id_branch;
    wire       id_jal;
    wire       id_jalr;

    // Register file read data
    wire [DATA_WIDTH-1:0] id_rs1_data;
    wire [DATA_WIDTH-1:0] id_rs2_data;

    // WB stage writeback (needed by regfile)
    wire [4:0]            wb_rd;
    wire                  wb_reg_we;
    wire [DATA_WIDTH-1:0] wb_data;

    // ID/EX register outputs (EX stage inputs)
    wire [ADDR_WIDTH-1:0] ex_pc;
    wire [ADDR_WIDTH-1:0] ex_pc4;
    wire [DATA_WIDTH-1:0] ex_rs1_data;
    wire [DATA_WIDTH-1:0] ex_rs2_data;
    wire [DATA_WIDTH-1:0] ex_imm;
    wire [4:0]            ex_rs1_addr;
    wire [4:0]            ex_rs2_addr;
    wire [4:0]            ex_rd;
    wire [2:0]            ex_funct3;
    wire [3:0]            ex_alu_ctrl;
    wire                  ex_alu_src_a;
    wire                  ex_alu_src_b;
    wire                  ex_reg_we;
    wire                  ex_mem_we;
    wire                  ex_mem_re;
    wire [1:0]            ex_wb_sel;
    wire                  ex_branch;
    wire                  ex_jal;
    wire                  ex_jalr;

    // EX stage internal
    wire [DATA_WIDTH-1:0] ex_alu_op_a_raw;  // after forwarding mux
    wire [DATA_WIDTH-1:0] ex_alu_op_b_raw;  // after forwarding mux (rs2 value)
    wire [DATA_WIDTH-1:0] ex_alu_op_a;      // after src_a mux (rs1 or PC)
    wire [DATA_WIDTH-1:0] ex_alu_op_b;      // after src_b mux (rs2_fwd or imm)
    wire [DATA_WIDTH-1:0] ex_alu_result;
    wire                  ex_alu_zero;
    wire [ADDR_WIDTH-1:0] ex_branch_target; // PC + imm
    wire [ADDR_WIDTH-1:0] ex_jalr_target;   // (rs1 + imm) & ~1
    wire                  ex_branch_taken;
    wire [ADDR_WIDTH-1:0] ex_pc_next_redirect; // redirect PC on taken branch/jump

    // EX/MEM register outputs (MEM stage inputs)
    wire [ADDR_WIDTH-1:0] mem_pc4;
    wire [DATA_WIDTH-1:0] mem_alu_result;
    wire [DATA_WIDTH-1:0] mem_rs2_data;
    wire [4:0]            mem_rd;
    wire [2:0]            mem_funct3;
    wire                  mem_reg_we;
    wire                  mem_mem_we;
    wire                  mem_mem_re;
    wire [1:0]            mem_wb_sel;

    // MEM stage
    wire [DATA_WIDTH-1:0] mem_rdata;

    // MEM/WB register outputs (WB stage inputs)
    wire [ADDR_WIDTH-1:0] wb_pc4;
    wire [DATA_WIDTH-1:0] wb_alu_result;
    wire [DATA_WIDTH-1:0] wb_mem_data;
    wire [1:0]            wb_wb_sel;

    // Hazard unit outputs
    wire        pc_stall;
    wire        if_id_stall;
    wire        if_id_flush;
    wire        id_ex_flush;
    wire [1:0]  fwd_a;
    wire [1:0]  fwd_b;

    // =========================================================
    // IF Stage
    // =========================================================

    // Branch/jump redirects PC
    assign ex_branch_taken  = ex_branch && (
        (ex_funct3 == 3'b000 &&  ex_alu_zero)       // BEQ
     || (ex_funct3 == 3'b001 && !ex_alu_zero)       // BNE
     || (ex_funct3 == 3'b100 &&  ex_alu_result[0])  // BLT
     || (ex_funct3 == 3'b101 && !ex_alu_result[0])  // BGE
     || (ex_funct3 == 3'b110 &&  ex_alu_result[0])  // BLTU
     || (ex_funct3 == 3'b111 && !ex_alu_result[0])  // BGEU
    );

    assign ex_branch_target    = ex_pc + ex_imm;
    assign ex_jalr_target      = {ex_alu_result[ADDR_WIDTH-1:1], 1'b0}; // clear bit 0

    assign ex_pc_next_redirect = ex_jalr       ? ex_jalr_target :
                                 ex_branch_taken || ex_jal ? ex_branch_target :
                                 {ADDR_WIDTH{1'b0}};

    assign if_pc4 = if_pc + 32'd4;

    wire redirect = ex_branch_taken || ex_jal || ex_jalr;

    wire [ADDR_WIDTH-1:0] pc_next = redirect ? ex_pc_next_redirect : if_pc4;

    pc_reg #(.ADDR_WIDTH(ADDR_WIDTH)) u_pc (
        .clk     (clk),
        .rst_n   (rst_n),
        .stall   (pc_stall),
        .pc_next (pc_next),
        .pc      (if_pc)
    );

    imem #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_imem (
        .addr  (if_pc),
        .instr (if_instr)
    );

    // =========================================================
    // IF/ID Register
    // =========================================================
    if_id_reg #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_if_id (
        .clk      (clk),
        .rst_n    (rst_n),
        .stall    (if_id_stall),
        .flush    (if_id_flush),
        .if_pc    (if_pc),
        .if_pc4   (if_pc4),
        .if_instr (if_instr),
        .id_pc    (id_pc),
        .id_pc4   (id_pc4),
        .id_instr (id_instr)
    );

    // =========================================================
    // ID Stage
    // =========================================================

    // Control unit
    control u_ctrl (
        .opcode    (id_opcode),
        .funct3    (id_funct3),
        .funct7    (id_funct7),
        .alu_ctrl  (id_alu_ctrl),
        .alu_src_a (id_alu_src_a),
        .alu_src_b (id_alu_src_b),
        .reg_we    (id_reg_we),
        .mem_we    (id_mem_we),
        .mem_re    (id_mem_re),
        .wb_sel    (id_wb_sel),
        .imm_sel   (id_imm_sel),
        .branch    (id_branch),
        .jal       (id_jal),
        .jalr      (id_jalr)
    );

    // Register file
    regfile #(.DATA_WIDTH(DATA_WIDTH)) u_rf (
        .clk     (clk),
        .we      (wb_reg_we),
        .rs1     (id_rs1_addr),
        .rs2     (id_rs2_addr),
        .rd      (wb_rd),
        .wr_data (wb_data),
        .rd1     (id_rs1_data),
        .rd2     (id_rs2_data)
    );

    // Immediate generator
    always @(*) begin
        case (id_imm_sel)
            3'b000: id_imm = {{20{id_instr[31]}}, id_instr[31:20]};                      // I
            3'b001: id_imm = {{20{id_instr[31]}}, id_instr[31:25], id_instr[11:7]};       // S
            3'b010: id_imm = {{19{id_instr[31]}}, id_instr[31], id_instr[7],               // B
                               id_instr[30:25], id_instr[11:8], 1'b0};
            3'b011: id_imm = {id_instr[31:12], 12'b0};                                   // U
            3'b100: id_imm = {{11{id_instr[31]}}, id_instr[31], id_instr[19:12],          // J
                               id_instr[20], id_instr[30:21], 1'b0};
            default: id_imm = {DATA_WIDTH{1'b0}};
        endcase
    end

    // =========================================================
    // ID/EX Register
    // =========================================================
    id_ex_reg #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_id_ex (
        .clk         (clk),
        .rst_n       (rst_n),
        .flush       (id_ex_flush),
        .id_pc       (id_pc),
        .id_pc4      (id_pc4),
        .id_rs1_data (id_rs1_data),
        .id_rs2_data (id_rs2_data),
        .id_imm      (id_imm),
        .id_rs1_addr (id_rs1_addr),
        .id_rs2_addr (id_rs2_addr),
        .id_rd       (id_rd),
        .id_funct3   (id_funct3),
        .id_alu_ctrl (id_alu_ctrl),
        .id_alu_src_a(id_alu_src_a),
        .id_alu_src_b(id_alu_src_b),
        .id_reg_we   (id_reg_we),
        .id_mem_we   (id_mem_we),
        .id_mem_re   (id_mem_re),
        .id_wb_sel   (id_wb_sel),
        .id_branch   (id_branch),
        .id_jal      (id_jal),
        .id_jalr     (id_jalr),
        // outputs
        .ex_pc       (ex_pc),
        .ex_pc4      (ex_pc4),
        .ex_rs1_data (ex_rs1_data),
        .ex_rs2_data (ex_rs2_data),
        .ex_imm      (ex_imm),
        .ex_rs1_addr (ex_rs1_addr),
        .ex_rs2_addr (ex_rs2_addr),
        .ex_rd       (ex_rd),
        .ex_funct3   (ex_funct3),
        .ex_alu_ctrl (ex_alu_ctrl),
        .ex_alu_src_a(ex_alu_src_a),
        .ex_alu_src_b(ex_alu_src_b),
        .ex_reg_we   (ex_reg_we),
        .ex_mem_we   (ex_mem_we),
        .ex_mem_re   (ex_mem_re),
        .ex_wb_sel   (ex_wb_sel),
        .ex_branch   (ex_branch),
        .ex_jal      (ex_jal),
        .ex_jalr     (ex_jalr)
    );

    // =========================================================
    // EX Stage
    // =========================================================

    // Forwarding muxes for rs1 (operand A) and rs2 (operand B)
    // fwd: 00=regfile, 01=MEM/WB wb_data, 10=EX/MEM alu_result
    assign ex_alu_op_a_raw = (fwd_a == 2'b10) ? mem_alu_result :
                             (fwd_a == 2'b01) ? wb_data        :
                                                ex_rs1_data;

    assign ex_alu_op_b_raw = (fwd_b == 2'b10) ? mem_alu_result :
                             (fwd_b == 2'b01) ? wb_data        :
                                                ex_rs2_data;

    // ALU source muxes
    assign ex_alu_op_a = ex_alu_src_a ? ex_pc           : ex_alu_op_a_raw;
    assign ex_alu_op_b = ex_alu_src_b ? ex_imm          : ex_alu_op_b_raw;

    alu #(.DATA_WIDTH(DATA_WIDTH)) u_alu (
        .alu_ctrl (ex_alu_ctrl),
        .a        (ex_alu_op_a),
        .b        (ex_alu_op_b),
        .result   (ex_alu_result),
        .zero     (ex_alu_zero)
    );

    // =========================================================
    // EX/MEM Register
    // =========================================================
    ex_mem_reg #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_ex_mem (
        .clk           (clk),
        .rst_n         (rst_n),
        .flush         (1'b0), // no flush after EX
        .ex_pc4        (ex_pc4),
        .ex_alu_result (ex_alu_result),
        .ex_rs2_fwd    (ex_alu_op_b_raw), // forwarded rs2 for store
        .ex_rd         (ex_rd),
        .ex_funct3     (ex_funct3),
        .ex_reg_we     (ex_reg_we),
        .ex_mem_we     (ex_mem_we),
        .ex_mem_re     (ex_mem_re),
        .ex_wb_sel     (ex_wb_sel),
        // outputs
        .mem_pc4       (mem_pc4),
        .mem_alu_result(mem_alu_result),
        .mem_rs2_data  (mem_rs2_data),
        .mem_rd        (mem_rd),
        .mem_funct3    (mem_funct3),
        .mem_reg_we    (mem_reg_we),
        .mem_mem_we    (mem_mem_we),
        .mem_mem_re    (mem_mem_re),
        .mem_wb_sel    (mem_wb_sel)
    );

    // =========================================================
    // MEM Stage
    // =========================================================
    dmem #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_dmem (
        .clk      (clk),
        .mem_we   (mem_mem_we),
        .funct3   (mem_funct3),
        .addr     (mem_alu_result),
        .wr_data  (mem_rs2_data),
        .rd_data  (mem_rdata)
    );

    // =========================================================
    // MEM/WB Register
    // =========================================================
    mem_wb_reg #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_mem_wb (
        .clk           (clk),
        .rst_n         (rst_n),
        .mem_pc4       (mem_pc4),
        .mem_alu_result(mem_alu_result),
        .mem_rdata     (mem_rdata),
        .mem_rd        (mem_rd),
        .mem_reg_we    (mem_reg_we),
        .mem_wb_sel    (mem_wb_sel),
        // outputs
        .wb_pc4        (wb_pc4),
        .wb_alu_result (wb_alu_result),
        .wb_mem_data   (wb_mem_data),
        .wb_rd         (wb_rd),
        .wb_reg_we     (wb_reg_we),
        .wb_wb_sel     (wb_wb_sel)
    );

    // =========================================================
    // WB Stage
    // =========================================================
    assign wb_data = (wb_wb_sel == 2'b01) ? wb_mem_data   :
                     (wb_wb_sel == 2'b10) ? wb_pc4        :
                                            wb_alu_result;

    // =========================================================
    // Hazard Unit
    // =========================================================
    hazard_unit u_haz (
        .id_ex_mem_re  (ex_mem_re),
        .id_ex_rd      (ex_rd),
        .ex_mem_reg_we (mem_reg_we),
        .ex_mem_rd     (mem_rd),
        .mem_wb_reg_we (wb_reg_we),
        .mem_wb_rd     (wb_rd),
        .if_id_rs1     (id_rs1_addr),
        .if_id_rs2     (id_rs2_addr),
        .id_ex_rs1     (ex_rs1_addr),
        .id_ex_rs2     (ex_rs2_addr),
        .branch_taken  (ex_branch_taken),
        .ex_jal        (ex_jal),
        .ex_jalr       (ex_jalr),
        .pc_stall      (pc_stall),
        .if_id_stall   (if_id_stall),
        .if_id_flush   (if_id_flush),
        .id_ex_flush   (id_ex_flush),
        .fwd_a         (fwd_a),
        .fwd_b         (fwd_b)
    );

endmodule
