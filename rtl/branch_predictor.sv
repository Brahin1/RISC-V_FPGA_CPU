// branch_predictor.sv
// Next-fetch-address predictor used by IF.
//
// MODE = 0 : static not-taken (always pc + 4)
// MODE = 1 : static BTFN (backward taken / forward not-taken, JAL always taken),
//            decoded from the instruction word currently in ID
//
// The prediction is made from the instruction that was just fetched (the one
// sitting in ID), so a correct taken prediction costs zero bubbles. The update
// port is there for a dynamic predictor later; the static modes ignore it.

module branch_predictor #(
  parameter int MODE    = 1,
  parameter int ENTRIES = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  // lookup
  input  logic        lk_valid,
  input  logic [31:0] lk_pc,
  input  logic [31:0] lk_insn,     // only used by MODE 1
  output logic        lk_taken,
  output logic [31:0] lk_target,

  // update from EX
  input  logic        up_valid,
  input  logic        up_is_cond,  // conditional branch (vs. JAL/JALR)
  input  logic        up_taken,
  input  logic [31:0] up_pc,
  input  logic [31:0] up_target
);

  localparam int IDX_W = $clog2(ENTRIES);
  localparam int TAG_W = 32 - IDX_W - 2;

  generate
    if (MODE == 1) begin : g_btfn

      logic [31:0] imm_b, imm_j;
      assign imm_b = {{19{lk_insn[31]}}, lk_insn[31], lk_insn[7], lk_insn[30:25], lk_insn[11:8], 1'b0};
      assign imm_j = {{11{lk_insn[31]}}, lk_insn[31], lk_insn[19:12], lk_insn[20], lk_insn[30:21], 1'b0};

      logic is_br, is_jal;
      assign is_br  = (lk_insn[6:0] == 7'b1100011);
      assign is_jal = (lk_insn[6:0] == 7'b1101111);

      assign lk_taken  = lk_valid && (is_jal || (is_br && lk_insn[31]));
      assign lk_target = lk_pc + (is_jal ? imm_j : imm_b);

    end else begin : g_static

      assign lk_taken  = 1'b0;
      assign lk_target = lk_pc + 32'd4;

    end
  endgenerate

  // unused in some modes
  logic unused;
  assign unused = &{1'b0, up_valid, up_is_cond, up_taken, up_pc, up_target, lk_insn, clk, rst_n};

endmodule
