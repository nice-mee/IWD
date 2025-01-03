module decoder
import cpu_params::*;
import uop_types::*;
import rv32i_types::*;
(
    input   logic   [31:0]          inst,

    output  logic   [1:0]           rs_type,
    output  logic   [1:0]           fu_type,
    output  logic   [3:0]           fu_opcode,
    output  logic   [0:0]           op1_sel,
    output  logic   [0:0]           op2_sel,
    output  logic   [31:0]          imm,
    output  logic   [ARF_IDX-1:0]   rd_arch,
    output  logic                   rd_en,
    output  logic   [ARF_IDX-1:0]   rs1_arch,
    output  logic   [ARF_IDX-1:0]   rs2_arch,
    output  logic                   is_store
);

    logic   [6:0]               opcode;
    logic   [2:0]               funct3;
    logic   [6:0]               funct7;

    assign opcode = inst[6:0];
    assign funct3 = inst[14:12];
    assign funct7 = inst[31:25];

    // If a register is not used, it's set to r0
    assign rd_en = opcode inside {op_b_lui, op_b_auipc, op_b_imm, op_b_reg, op_b_jal, op_b_jalr, op_b_load};
    assign rd_arch = (rd_en) ? inst[11:7] : '0;
    assign rs1_arch = (opcode inside {op_b_imm, op_b_reg, op_b_jalr, op_b_br, op_b_load, op_b_store}) ? inst[19:15] : '0;
    assign rs2_arch = (opcode inside {op_b_reg, op_b_br, op_b_store}) ? inst[24:20] : '0;
    assign is_store = opcode == op_b_store;

    always_comb begin
        rs_type = RS_INT;
        fu_type = FU_ALU;
        fu_opcode = '0;
        op1_sel = OP1_RS1;
        op2_sel = OP2_RS2;

        unique case (opcode)
            op_b_lui    : begin
                rs_type = RS_INT;
                fu_type = FU_ALU;
                op1_sel = OP1_ZERO;
                op2_sel = OP2_IMM;
                fu_opcode = ALU_ADD;
            end
            op_b_auipc  : begin
                rs_type = RS_BR;
                fu_type = FU_BR;
                fu_opcode = BR_AUIPC;
            end
            op_b_jal    : begin
                rs_type = RS_BR;
                fu_type = FU_BR;
                fu_opcode = BR_JAL;
            end
            op_b_jalr   : begin
                rs_type = RS_BR;
                fu_type = FU_BR;
                fu_opcode = BR_JALR;
            end
            op_b_br     : begin
                rs_type = RS_BR;
                fu_type = FU_BR;
                fu_opcode = {1'b0, funct3};
            end
            op_b_load   : begin
                rs_type = RS_MEM;
                fu_type = FU_AGU;
                fu_opcode = {1'b0, funct3};
            end
            op_b_store  : begin
                rs_type = RS_MEM;
                fu_type = FU_AGU;
                fu_opcode = {1'b1, funct3};
            end
            op_b_imm    : begin
                rs_type = RS_INT;
                fu_type = FU_ALU;
                op1_sel = OP1_RS1;
                op2_sel = OP2_IMM;
                unique case (funct3)
                    arith_f3_slt: begin
                        fu_opcode = ALU_SLT;
                    end
                    arith_f3_sltu: begin
                        fu_opcode = ALU_SLTU;
                    end
                    arith_f3_sr: begin
                        fu_opcode = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    end
                    default: begin
                        fu_opcode = {1'b0, funct3};
                    end
                endcase
            end
            op_b_reg    : begin
                op1_sel = OP1_RS1;
                op2_sel = OP2_RS2;
                if (funct7[0]) begin
                    rs_type = RS_INTM;
                    fu_type = FU_MDU;
                    fu_opcode = {1'b0, funct3};
                end else begin
                    rs_type = RS_INT;
                    fu_type = FU_ALU;
                    unique case (funct3)
                        arith_f3_slt: begin
                            fu_opcode = ALU_SLT;
                        end
                        arith_f3_sltu: begin
                            fu_opcode = ALU_SLTU;
                        end
                        arith_f3_sr: begin
                            fu_opcode = (funct7[5]) ? ALU_SRA : ALU_SRL;
                        end
                        arith_f3_add: begin
                            fu_opcode = (funct7[5]) ? ALU_SUB : ALU_ADD;
                        end
                        default: begin
                            fu_opcode = {1'b0, funct3};
                        end
                    endcase
                end
            end
            default     : begin
                // Ignore the instruction
            end
        endcase
    end

    // Decode immediates
    logic   [31:0]  i_imm;
    logic   [31:0]  s_imm;
    logic   [31:0]  b_imm;
    logic   [31:0]  u_imm;
    logic   [31:0]  j_imm;

    assign i_imm  = {{21{inst[31]}}, inst[30:20]};
    assign s_imm  = {{21{inst[31]}}, inst[30:25], inst[11:7]};
    assign b_imm  = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
    assign u_imm  = {inst[31:12], 12'h000};
    assign j_imm  = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};

    always_comb begin
        unique case (opcode)
            op_b_jalr, op_b_imm, op_b_load  : imm = i_imm;
            op_b_store                      : imm = s_imm;
            op_b_br                         : imm = b_imm;
            op_b_lui, op_b_auipc            : imm = u_imm;
            op_b_jal                        : imm = j_imm;
            default                         : imm = 'x;
        endcase
    end

endmodule
