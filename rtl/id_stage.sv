// id_stage.sv
// Decode + register read, and the ID/EX pipeline register.
//
// Exceptions that are known at decode time (illegal instruction, ECALL, EBREAK)
// are attached to the instruction here and travel down to MEM, where all traps
// are taken. A pending, enabled timer interrupt is attached the same way: the
// instruction in ID becomes the interrupted instruction and never executes.

module id_stage
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // from IF
  input  logic        id_valid,
  input  logic [31:0] id_pc,
  input  logic [31:0] id_insn,
  input  logic        id_pred_taken,
  input  logic [31:0] id_pred_target,

  // pipeline control
  input  logic        flush,          // trap/mret from MEM: kill ID and EX
  input  logic        hold_ex,        // divider busy: ID/EX keeps its value
  input  logic        bubble,         // EX redirect or load-use: insert NOP into EX

  input  logic        irq_pending,

  // register file write port (from WB)
  input  logic        rf_we,
  input  logic [4:0]  rf_wa,
  input  logic [31:0] rf_wd,

  // decoded register indices for the hazard unit
  output logic [4:0]  id_rs1,
  output logic [4:0]  id_rs2,
  output logic        id_rs1_used,
  output logic        id_rs2_used,

  output id_ex_t      id_ex
);

  ctrl_t       ctrl;
  logic [31:0] rs1_val, rs2_val;

  decoder u_dec (
    .insn (id_insn),
    .ctrl (ctrl)
  );

  regfile u_rf (
    .clk (clk),
    .ra1 (ctrl.rs1),
    .rd1 (rs1_val),
    .ra2 (ctrl.rs2),
    .rd2 (rs2_val),
    .we  (rf_we),
    .wa  (rf_wa),
    .wd  (rf_wd)
  );

  assign id_rs1      = ctrl.rs1;
  assign id_rs2      = ctrl.rs2;
  assign id_rs1_used = id_valid && ctrl.rs1_used;
  assign id_rs2_used = id_valid && ctrl.rs2_used;

  // decode-time exceptions; interrupt has priority over synchronous exceptions
  logic       exc;
  exc_cause_t exc_cause;
  always_comb begin
    exc       = 1'b1;
    exc_cause = EXC_ILLEGAL_INSN;
    if (irq_pending)         exc_cause = IRQ_M_TIMER;
    else if (ctrl.illegal)   exc_cause = EXC_ILLEGAL_INSN;
    else if (ctrl.is_ecall)  exc_cause = EXC_ECALL_M;
    else if (ctrl.is_ebreak) exc_cause = EXC_BREAKPOINT;
    else                     exc       = 1'b0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_ex <= '0;
    end else if (flush) begin
      id_ex.valid <= 1'b0;
    end else if (hold_ex) begin
      id_ex <= id_ex;
    end else if (bubble || !id_valid) begin
      id_ex.valid <= 1'b0;
    end else begin
      id_ex.valid       <= 1'b1;
      id_ex.pc          <= id_pc;
      id_ex.insn        <= id_insn;
      id_ex.ctrl        <= ctrl;
      id_ex.rs1_val     <= rs1_val;
      id_ex.rs2_val     <= rs2_val;
      id_ex.pred_taken  <= id_pred_taken;
      id_ex.pred_target <= id_pred_target;
      id_ex.exc         <= exc;
      id_ex.exc_cause   <= exc_cause;
    end
  end

endmodule
