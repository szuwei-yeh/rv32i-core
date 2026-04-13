`timescale 1ns/1ps
// Control Unit — decodes opcode/funct3/funct7, generates all pipeline control signals
module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,

    // ALU
    output reg  [3:0] alu_ctrl,
    output reg        alu_src_a,  // 0=rs1, 1=PC
    output reg        alu_src_b,  // 0=rs2, 1=imm

    // Register file
    output reg        reg_we,

    // Data memory
    output reg        mem_we,
    output reg        mem_re,

    // Writeback mux: 00=alu_result, 01=mem_rdata, 10=PC+4
    output reg  [1:0] wb_sel,

    // Immediate type: 000=I, 001=S, 010=B, 011=U, 100=J
    output reg  [2:0] imm_sel,

    // Branch/jump
    output reg        branch,
    output reg        jal,
    output reg        jalr
);
    // Opcodes
    localparam OP_R      = 7'b0110011;
    localparam OP_I_ALU  = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;

    // ALU ctrl codes (must match alu.v)
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;
    localparam ALU_PASS = 4'b1010;

    always @(*) begin
        // Safe defaults — NOP
        alu_ctrl = ALU_ADD;
        alu_src_a = 1'b0;
        alu_src_b = 1'b0;
        reg_we    = 1'b0;
        mem_we    = 1'b0;
        mem_re    = 1'b0;
        wb_sel    = 2'b00;
        imm_sel   = 3'b000;
        branch    = 1'b0;
        jal       = 1'b0;
        jalr      = 1'b0;

        case (opcode)
            // ---- R-type ----
            OP_R: begin
                reg_we    = 1'b1;
                alu_src_a = 1'b0;
                alu_src_b = 1'b0;
                wb_sel    = 2'b00;
                case ({funct7[5], funct3})
                    4'b0_000: alu_ctrl = ALU_ADD;
                    4'b1_000: alu_ctrl = ALU_SUB;
                    4'b0_001: alu_ctrl = ALU_SLL;
                    4'b0_010: alu_ctrl = ALU_SLT;
                    4'b0_011: alu_ctrl = ALU_SLTU;
                    4'b0_100: alu_ctrl = ALU_XOR;
                    4'b0_101: alu_ctrl = ALU_SRL;
                    4'b1_101: alu_ctrl = ALU_SRA;
                    4'b0_110: alu_ctrl = ALU_OR;
                    4'b0_111: alu_ctrl = ALU_AND;
                    default:  alu_ctrl = ALU_ADD;
                endcase
            end

            // ---- I-type ALU ----
            OP_I_ALU: begin
                reg_we    = 1'b1;
                alu_src_a = 1'b0;
                alu_src_b = 1'b1;
                wb_sel    = 2'b00;
                imm_sel   = 3'b000; // I-type
                case (funct3)
                    3'b000: alu_ctrl = ALU_ADD;
                    3'b001: alu_ctrl = ALU_SLL;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b011: alu_ctrl = ALU_SLTU;
                    3'b100: alu_ctrl = ALU_XOR;
                    3'b101: alu_ctrl = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: alu_ctrl = ALU_OR;
                    3'b111: alu_ctrl = ALU_AND;
                    default: alu_ctrl = ALU_ADD;
                endcase
            end

            // ---- Load ----
            OP_LOAD: begin
                reg_we    = 1'b1;
                alu_src_a = 1'b0;
                alu_src_b = 1'b1;
                mem_re    = 1'b1;
                wb_sel    = 2'b01; // memory data
                imm_sel   = 3'b000; // I-type
                alu_ctrl  = ALU_ADD;
            end

            // ---- Store ----
            OP_STORE: begin
                alu_src_a = 1'b0;
                alu_src_b = 1'b1;
                mem_we    = 1'b1;
                imm_sel   = 3'b001; // S-type
                alu_ctrl  = ALU_ADD;
            end

            // ---- Branch ----
            OP_BRANCH: begin
                branch    = 1'b1;
                alu_src_a = 1'b0;
                alu_src_b = 1'b0;
                imm_sel   = 3'b010; // B-type
                case (funct3)
                    3'b000: alu_ctrl = ALU_SUB;  // BEQ
                    3'b001: alu_ctrl = ALU_SUB;  // BNE
                    3'b100: alu_ctrl = ALU_SLT;  // BLT
                    3'b101: alu_ctrl = ALU_SLT;  // BGE
                    3'b110: alu_ctrl = ALU_SLTU; // BLTU
                    3'b111: alu_ctrl = ALU_SLTU; // BGEU
                    default: alu_ctrl = ALU_SUB;
                endcase
            end

            // ---- JAL ----
            OP_JAL: begin
                reg_we    = 1'b1;
                jal       = 1'b1;
                wb_sel    = 2'b10; // PC+4
                imm_sel   = 3'b100; // J-type
                alu_src_a = 1'b1; // PC (for target = PC+imm via branch adder)
                alu_src_b = 1'b1;
                alu_ctrl  = ALU_ADD;
            end

            // ---- JALR ----
            OP_JALR: begin
                reg_we    = 1'b1;
                jalr      = 1'b1;
                alu_src_a = 1'b0; // rs1
                alu_src_b = 1'b1;
                wb_sel    = 2'b10; // PC+4
                imm_sel   = 3'b000; // I-type
                alu_ctrl  = ALU_ADD; // rs1+imm = jump target
            end

            // ---- LUI ----
            OP_LUI: begin
                reg_we    = 1'b1;
                alu_src_b = 1'b1;
                wb_sel    = 2'b00;
                imm_sel   = 3'b011; // U-type
                alu_ctrl  = ALU_PASS; // pass immediate through
            end

            // ---- AUIPC ----
            OP_AUIPC: begin
                reg_we    = 1'b1;
                alu_src_a = 1'b1; // PC
                alu_src_b = 1'b1;
                wb_sel    = 2'b00;
                imm_sel   = 3'b011; // U-type
                alu_ctrl  = ALU_ADD; // PC + imm
            end

            default: begin /* NOP */ end
        endcase
    end
endmodule
