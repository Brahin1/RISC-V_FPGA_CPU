// if_stage.sv
// Instruction fetch.
//
// IMEM is a synchronous BRAM, so the fetch address for the next instruction is
// the *combinational* next-PC. On the clock edge the BRAM latches it and pc_d
// takes the same value, so during the following cycle {pc_d, imem_rdata} is the
// instruction in ID. In other words the BRAM output register doubles as the
// IF/ID instruction register.
//
//   pc_next priority: redirect (trap/mret > EX mispredict) > prediction > pc+4
//
// While ID is stalled the BRAM enable is dropped so its output holds.

module if_stage
  import core_pkg::*;
#(
  parameter logic [31:0] RESET_PC = 32'h0000_0000,
  parameter int          BP_MODE  = 2
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        hold,           // ID stalled
  input  logic        redirect,
  input  logic [31:0] redirect_pc,

  // predictor update from EX
  input  logic        bp_up_valid,
  input  logic        bp_up_is_cond,
  input  logic        bp_up_taken,
  input  logic [31:0] bp_up_pc,
  input  logic [31:0] bp_up_target,

  // instruction memory
  output logic        imem_en,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  // to ID
  output logic        id_valid,
  output logic [31:0] id_pc,
  output logic [31:0] id_insn,
  output logic        id_pred_taken,
  output logic [31:0] id_pred_target
);

  logic [31:0] pc_d;
  logic        valid_d;
  logic [31:0] pc_next;

  logic        pred_taken;
  logic [31:0] pred_target;

  branch_predictor #(.MODE(BP_MODE)) u_bp (
    .clk        (clk),
    .rst_n      (rst_n),
    .lk_valid   (valid_d),
    .lk_pc      (pc_d),
    .lk_insn    (imem_rdata),
    .lk_taken   (pred_taken),
    .lk_target  (pred_target),
    .up_valid   (bp_up_valid),
    .up_is_cond (bp_up_is_cond),
    .up_taken   (bp_up_taken),
    .up_pc      (bp_up_pc),
    .up_target  (bp_up_target)
  );

  always_comb begin
    if (redirect)        pc_next = redirect_pc;
    else if (pred_taken) pc_next = pred_target;
    else                 pc_next = pc_d + 32'd4;
  end

  assign imem_en   = rst_n && (redirect || !hold);
  assign imem_addr = pc_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_d    <= RESET_PC - 32'd4;
      valid_d <= 1'b0;
    end else if (imem_en) begin
      pc_d    <= pc_next;
      valid_d <= 1'b1;
    end
  end

  assign id_valid       = valid_d;
  assign id_pc          = pc_d;
  assign id_insn        = imem_rdata;
  assign id_pred_taken  = pred_taken;
  assign id_pred_target = pred_target;

endmodule
