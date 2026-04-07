// ex_stage.sv
// Execute: operand forwarding, ALU, branch resolution, address generation,
// data-memory request, divider control and the EX/MEM pipeline register.
//
// Branches and JALR resolve here. A misprediction redirects fetch and squashes
// the one instruction in ID (1-cycle penalty). Loads/stores issue to the
// synchronous DMEM from EX so the data is available in MEM.

module ex_stage
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  id_ex_t      id_ex,

  // forwarding
  input  fwd_sel_e    fwd_a,
  input  fwd_sel_e    fwd_b,
  input  logic [31:0] fwd_exmem,
  input  logic [31:0] fwd_memwb,

  // pipeline control
  input  logic        flush,          // trap/mret from MEM: kill EX
  output logic        div_stall,

  // redirect (mispredict)
  output logic        redirect,
  output logic [31:0] redirect_pc,

  // predictor update
  output logic        bp_up_valid,
  output logic        bp_up_is_cond,
  output logic        bp_up_taken,
  output logic [31:0] bp_up_pc,
  output logic [31:0] bp_up_target,

  // events
  output logic        ev_br_mispredict,
  output logic        ev_jmp_redirect,
  output logic        ev_branch,

  // data memory request (issued in EX, data returns in MEM)
  output logic        dmem_req,
  output logic        dmem_we,
  output logic [3:0]  dmem_be,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,

  // MUL result for the instruction in MEM
  output logic [31:0] mul_result,

  output ex_mem_t     ex_mem
);

  ctrl_t c;
  assign c = id_ex.ctrl;

  logic active;   // valid and not already carrying an exception
  assign active = id_ex.valid && !id_ex.exc;

  // ---------------------------------------------------------------------------
  // Forwarding
  // ---------------------------------------------------------------------------
  logic [31:0] rs1, rs2;
  always_comb begin
    unique case (fwd_a)
      FWD_EXMEM: rs1 = fwd_exmem;
      FWD_MEMWB: rs1 = fwd_memwb;
      default:   rs1 = id_ex.rs1_val;
    endcase
    unique case (fwd_b)
      FWD_EXMEM: rs2 = fwd_exmem;
      FWD_MEMWB: rs2 = fwd_memwb;
      default:   rs2 = id_ex.rs2_val;
    endcase
  end

  // ---------------------------------------------------------------------------
  // ALU
  // ---------------------------------------------------------------------------
  logic [31:0] alu_a, alu_b, alu_y;
  always_comb begin
    unique case (c.opa_sel)
      OPA_PC:   alu_a = id_ex.pc;
      OPA_ZERO: alu_a = '0;
      default:  alu_a = rs1;
    endcase
    alu_b = (c.opb_sel == OPB_IMM) ? c.imm : rs2;
  end

  alu u_alu (
    .op (c.alu_op),
    .a  (alu_a),
    .b  (alu_b),
    .y  (alu_y)
  );

  // ---------------------------------------------------------------------------
  // Branch / jump resolution
  // ---------------------------------------------------------------------------
  logic        eq, lt, ltu;
  logic        br_cond;
  logic        taken;
  logic [31:0] target;
  logic [31:0] pc_plus4;
  logic [31:0] next_pc;
  logic        is_ctrl;

  assign eq  = (rs1 == rs2);
  assign lt  = $signed(rs1) < $signed(rs2);
  assign ltu = rs1 < rs2;

  always_comb begin
    unique case (c.funct3)
      F3_BEQ:  br_cond = eq;
      F3_BNE:  br_cond = !eq;
      F3_BLT:  br_cond = lt;
      F3_BGE:  br_cond = !lt;
      F3_BLTU: br_cond = ltu;
      F3_BGEU: br_cond = !ltu;
      default: br_cond = 1'b0;
    endcase
  end

  assign is_ctrl  = c.is_branch || c.is_jal || c.is_jalr;
  assign taken    = c.is_jal || c.is_jalr || (c.is_branch && br_cond);
  assign target   = c.is_jalr ? ((rs1 + c.imm) & ~32'd1) : (id_ex.pc + c.imm);
  assign pc_plus4 = id_ex.pc + 32'd4;
  assign next_pc  = taken ? target : pc_plus4;

  // No C extension: a taken control transfer to a non-word-aligned target
  // raises instruction-address-misaligned on the jump/branch itself.
  logic target_misaligned;
  assign target_misaligned = taken && (target[1:0] != 2'b00);

  // Did fetch go to the right place after this instruction?
  logic mispredict;
  assign mispredict = (id_ex.pred_taken != taken) ||
                      (taken && id_ex.pred_target != target);

  assign redirect    = active && !target_misaligned && !flush &&
                       (is_ctrl ? mispredict : id_ex.pred_taken);
  assign redirect_pc = next_pc;

  assign bp_up_valid   = active && is_ctrl && !target_misaligned && !flush;
  assign bp_up_is_cond = c.is_branch;
  assign bp_up_taken   = taken;
  assign bp_up_pc      = id_ex.pc;
  assign bp_up_target  = target;

  assign ev_branch        = bp_up_valid && c.is_branch;
  assign ev_br_mispredict = redirect && c.is_branch;
  assign ev_jmp_redirect  = redirect && (c.is_jal || c.is_jalr);

  // ---------------------------------------------------------------------------
  // Load / store
  // ---------------------------------------------------------------------------
  logic [1:0]  byte_off;
  logic        mem_misaligned;
  logic [3:0]  be;
  logic [31:0] wdata;

  assign byte_off = alu_y[1:0];

  always_comb begin
    unique case (c.funct3[1:0])
      2'b00:   begin be = 4'b0001 << byte_off;   mem_misaligned = 1'b0;               end
      2'b01:   begin be = 4'b0011 << byte_off;   mem_misaligned = byte_off[0];        end
      default: begin be = 4'b1111;               mem_misaligned = (byte_off != 2'b00); end
    endcase
    unique case (c.funct3[1:0])
      2'b00:   wdata = {4{rs2[7:0]}};
      2'b01:   wdata = {2{rs2[15:0]}};
      default: wdata = rs2;
    endcase
  end

  logic is_mem;
  assign is_mem = c.mem_read || c.mem_write;

  assign dmem_req   = active && is_mem && !mem_misaligned && !flush;
  assign dmem_we    = c.mem_write;
  assign dmem_be    = be;
  assign dmem_addr  = alu_y;
  assign dmem_wdata = wdata;

  // ---------------------------------------------------------------------------
  // M extension
  // ---------------------------------------------------------------------------
  logic        ex_advance;
  logic [31:0] div_result;

  assign ex_advance = !div_stall;

  muldiv u_muldiv (
    .clk        (clk),
    .rst_n      (rst_n),
    .ex_valid   (active),
    .ex_is_mul  (c.is_mul),
    .ex_is_div  (c.is_div),
    .ex_funct3  (c.funct3),
    .ex_a       (rs1),
    .ex_b       (rs2),
    .ex_advance (ex_advance),
    .flush      (flush),
    .div_stall  (div_stall),
    .div_result (div_result),
    .mul_result (mul_result)
  );

  // ---------------------------------------------------------------------------
  // Exceptions detected in EX
  // ---------------------------------------------------------------------------
  logic       exc;
  exc_cause_t exc_cause;
  logic [31:0] exc_tval;
  always_comb begin
    exc       = id_ex.exc;
    exc_cause = id_ex.exc_cause;
    exc_tval  = '0;
    if (id_ex.exc) begin
      // illegal instruction reports the instruction bits, like Spike
      if (id_ex.exc_cause == EXC_ILLEGAL_INSN) exc_tval = id_ex.insn;
    end else if (is_ctrl && target_misaligned) begin
      exc       = 1'b1;
      exc_cause = EXC_INSN_MISALIGNED;
      exc_tval  = target;
    end else if (is_mem && mem_misaligned) begin
      exc       = 1'b1;
      exc_cause = c.mem_write ? EXC_STORE_MISALIGNED : EXC_LOAD_MISALIGNED;
      exc_tval  = alu_y;
    end
  end

  // ---------------------------------------------------------------------------
  // EX/MEM register
  // ---------------------------------------------------------------------------
  logic [31:0] result;
  always_comb begin
    unique case (c.res_sel)
      RES_PC4: result = pc_plus4;
      RES_DIV: result = div_result;
      default: result = alu_y;          // ALU result / memory address
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_mem <= '0;
    end else if (flush || div_stall) begin
      ex_mem.valid <= 1'b0;
    end else begin
      ex_mem.valid     <= id_ex.valid;
      ex_mem.pc        <= id_ex.pc;
      ex_mem.insn      <= id_ex.insn;
      ex_mem.next_pc   <= next_pc;
      ex_mem.ctrl      <= c;
      ex_mem.result    <= result;
      ex_mem.op_data   <= c.is_csr ? (c.csr_imm ? c.imm : rs1) : wdata;
      ex_mem.mem_be    <= be;
      ex_mem.exc       <= exc;
      ex_mem.exc_cause <= exc_cause;
      ex_mem.exc_tval  <= exc_tval;
    end
  end

endmodule
