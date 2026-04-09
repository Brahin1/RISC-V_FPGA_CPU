// decoder.sv
// RV32IM + Zicsr instruction decoder (machine mode only).
// Produces a ctrl_t control word; anything not recognised sets ctrl.illegal.

module decoder
  import core_pkg::*;
(
  input  logic [31:0] insn,
  output ctrl_t       ctrl
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [4:0] rs1, rs2, rd;

  assign opcode = insn[6:0];
  assign funct3 = insn[14:12];
  assign funct7 = insn[31:25];
  assign rs1    = insn[19:15];
  assign rs2    = insn[24:20];
  assign rd     = insn[11:7];

  // Immediates
  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  assign imm_i = {{20{insn[31]}}, insn[31:20]};
  assign imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
  assign imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
  assign imm_u = {insn[31:12], 12'b0};
  assign imm_j = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};

  logic writes_rd;

  always_comb begin
    ctrl            = '0;
    ctrl.rs1        = rs1;
    ctrl.rs2        = rs2;
    ctrl.rd         = rd;
    ctrl.funct3     = funct3;
    ctrl.alu_op     = ALU_ADD;
    ctrl.opa_sel    = OPA_RS1;
    ctrl.opb_sel    = OPB_IMM;
    ctrl.res_sel    = RES_ALU;
    ctrl.csr_addr   = insn[31:20];
    writes_rd       = 1'b0;

    unique case (opcode)
      OPC_LUI: begin
        ctrl.opa_sel = OPA_ZERO;
        ctrl.imm     = imm_u;
        writes_rd    = 1'b1;
      end

      OPC_AUIPC: begin
        ctrl.opa_sel = OPA_PC;
        ctrl.imm     = imm_u;
        writes_rd    = 1'b1;
      end

      OPC_JAL: begin
        ctrl.is_jal  = 1'b1;
        ctrl.imm     = imm_j;
        ctrl.res_sel = RES_PC4;
        writes_rd    = 1'b1;
      end

      OPC_JALR: begin
        ctrl.is_jalr  = 1'b1;
        ctrl.imm      = imm_i;
        ctrl.rs1_used = 1'b1;
        ctrl.res_sel  = RES_PC4;
        writes_rd     = 1'b1;
        if (funct3 != 3'b000) ctrl.illegal = 1'b1;
      end

      OPC_BRANCH: begin
        ctrl.is_branch = 1'b1;
        ctrl.imm       = imm_b;
        ctrl.rs1_used  = 1'b1;
        ctrl.rs2_used  = 1'b1;
        if (funct3 == 3'b010 || funct3 == 3'b011) ctrl.illegal = 1'b1;
      end

      OPC_LOAD: begin
        ctrl.mem_read = 1'b1;
        ctrl.imm      = imm_i;
        ctrl.rs1_used = 1'b1;
        ctrl.res_sel  = RES_LOAD;
        writes_rd     = 1'b1;
        if (!(funct3 inside {F3_LB, F3_LH, F3_LW, F3_LBU, F3_LHU})) ctrl.illegal = 1'b1;
      end

      OPC_STORE: begin
        ctrl.mem_write = 1'b1;
        ctrl.imm       = imm_s;
        ctrl.rs1_used  = 1'b1;
        ctrl.rs2_used  = 1'b1;
        if (funct3 > 3'b010) ctrl.illegal = 1'b1;
      end

      OPC_OP_IMM: begin
        ctrl.imm      = imm_i;
        ctrl.rs1_used = 1'b1;
        writes_rd     = 1'b1;
        unique case (funct3)
          3'b000: ctrl.alu_op = ALU_ADD;
          3'b010: ctrl.alu_op = ALU_SLT;
          3'b011: ctrl.alu_op = ALU_SLTU;
          3'b100: ctrl.alu_op = ALU_XOR;
          3'b110: ctrl.alu_op = ALU_OR;
          3'b111: ctrl.alu_op = ALU_AND;
          3'b001: begin
            ctrl.alu_op = ALU_SLL;
            if (funct7 != 7'b0000000) ctrl.illegal = 1'b1;
          end
          3'b101: begin
            if (funct7 == 7'b0000000)      ctrl.alu_op = ALU_SRL;
            else if (funct7 == 7'b0100000) ctrl.alu_op = ALU_SRA;
            else                            ctrl.illegal = 1'b1;
          end
          default: ;
        endcase
      end

      OPC_OP: begin
        ctrl.opb_sel  = OPB_RS2;
        ctrl.rs1_used = 1'b1;
        ctrl.rs2_used = 1'b1;
        writes_rd     = 1'b1;
        if (funct7 == 7'b0000001) begin
          // M extension
          if (funct3[2]) begin
            ctrl.is_div  = 1'b1;
            ctrl.res_sel = RES_DIV;
          end else begin
            ctrl.is_mul  = 1'b1;
            ctrl.res_sel = RES_MUL;
          end
        end else if (funct7 == 7'b0000000) begin
          unique case (funct3)
            3'b000: ctrl.alu_op = ALU_ADD;
            3'b001: ctrl.alu_op = ALU_SLL;
            3'b010: ctrl.alu_op = ALU_SLT;
            3'b011: ctrl.alu_op = ALU_SLTU;
            3'b100: ctrl.alu_op = ALU_XOR;
            3'b101: ctrl.alu_op = ALU_SRL;
            3'b110: ctrl.alu_op = ALU_OR;
            3'b111: ctrl.alu_op = ALU_AND;
            default: ;
          endcase
        end else if (funct7 == 7'b0100000) begin
          if (funct3 == 3'b000)      ctrl.alu_op = ALU_SUB;
          else if (funct3 == 3'b101) ctrl.alu_op = ALU_SRA;
          else                       ctrl.illegal = 1'b1;
        end else begin
          ctrl.illegal = 1'b1;
        end
      end

      OPC_MISC_MEM: begin
        // FENCE and FENCE.I are no-ops: in-order core, no caches, no store buffer.
        // rd/rs1 are left unused on purpose.
        if (funct3 != 3'b000 && funct3 != 3'b001) ctrl.illegal = 1'b1;
      end

      OPC_SYSTEM: begin
        if (funct3 == 3'b000) begin
          unique case (insn)
            32'h0000_0073: ctrl.is_ecall  = 1'b1;
            32'h0010_0073: ctrl.is_ebreak = 1'b1;
            32'h3020_0073: ctrl.is_mret   = 1'b1;
            32'h1050_0073: ;                       // WFI: treated as a NOP
            default:       ctrl.illegal   = 1'b1;
          endcase
        end else if (funct3 == 3'b100) begin
          ctrl.illegal = 1'b1;
        end else begin
          ctrl.is_csr   = 1'b1;
          ctrl.csr_imm  = funct3[2];
          ctrl.rs1_used = ~funct3[2];
          ctrl.res_sel  = RES_CSR;
          ctrl.imm      = {27'b0, rs1};            // uimm for CSRR*I
          // CSRRS/CSRRC with rs1 = x0 (or uimm = 0) must not write the CSR
          ctrl.csr_wr   = (funct3[1:0] == 2'b01) || (rs1 != 5'd0);
          writes_rd     = 1'b1;
        end
      end

      default: ctrl.illegal = 1'b1;
    endcase

    if (insn[1:0] != 2'b11) ctrl.illegal = 1'b1;

    ctrl.rd_we = writes_rd && (rd != 5'd0) && !ctrl.illegal;

    if (ctrl.illegal) begin
      ctrl.rs1_used  = 1'b0;
      ctrl.rs2_used  = 1'b0;
      ctrl.is_branch = 1'b0;
      ctrl.is_jal    = 1'b0;
      ctrl.is_jalr   = 1'b0;
      ctrl.mem_read  = 1'b0;
      ctrl.mem_write = 1'b0;
      ctrl.is_mul    = 1'b0;
      ctrl.is_div    = 1'b0;
      ctrl.is_csr    = 1'b0;
    end
  end

endmodule
