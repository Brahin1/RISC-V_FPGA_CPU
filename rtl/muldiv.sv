// muldiv.sv
// M-extension unit.
//
//  * Multiply: two-stage pipeline spanning EX -> MEM. Operands are registered at
//    the EX/MEM boundary (DSP48E1 A/B registers) and the 33x33 signed product is
//    formed in MEM, then registered into MEM/WB (P register). A dependent
//    instruction directly behind a MUL takes one interlock cycle, same as a load.
//  * Divide: iterative radix-2 restoring divider in EX, 32 iterations plus one
//    setup cycle. The pipeline is stalled while it runs. Divide-by-zero
//    completes in one cycle with the spec-defined result.

module muldiv
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // ---- EX side ------------------------------------------------------------
  input  logic        ex_valid,     // valid, non-excepting instruction in EX
  input  logic        ex_is_mul,
  input  logic        ex_is_div,
  input  logic [2:0]  ex_funct3,
  input  logic [31:0] ex_a,
  input  logic [31:0] ex_b,
  input  logic        ex_advance,   // EX -> MEM transfer happens this cycle
  input  logic        flush,        // kill whatever is in EX

  output logic        div_stall,
  output logic [31:0] div_result,

  // ---- MEM side -----------------------------------------------------------
  output logic [31:0] mul_result    // result for the MUL currently in MEM
);

  // ===========================================================================
  // Multiplier
  // ===========================================================================
  (* use_dsp = "yes" *) logic signed [32:0] m_a, m_b;
  logic [1:0] m_op;   // funct3[1:0]: 00 MUL, 01 MULH, 10 MULHSU, 11 MULHU

  always_ff @(posedge clk) begin
    if (ex_advance && ex_is_mul) begin
      m_op <= ex_funct3[1:0];
      // sign-extend to 33 bits according to which operands are signed
      m_a  <= {(ex_funct3[1:0] != 2'b11) & ex_a[31], ex_a};   // MULH, MULHSU: signed rs1
      m_b  <= {(ex_funct3[1:0] == 2'b01) & ex_b[31], ex_b};   // only MULH: signed rs2
    end
  end

  (* use_dsp = "yes" *) logic signed [65:0] m_prod;
  assign m_prod = m_a * m_b;

  assign mul_result = (m_op == 2'b00) ? m_prod[31:0] : m_prod[63:32];

  // ===========================================================================
  // Divider
  // ===========================================================================
  logic        d_busy, d_done;
  logic [5:0]  d_count;
  logic [31:0] d_quo;
  logic [32:0] d_rem;
  logic [31:0] d_div;       // |divisor|
  logic        d_neg_q, d_neg_r, d_want_rem;
  logic [31:0] d_result_q;

  logic        is_signed;
  logic [31:0] abs_a, abs_b;
  logic        start;

  assign is_signed = ~ex_funct3[0];                // DIV, REM
  assign abs_a     = (is_signed && ex_a[31]) ? -ex_a : ex_a;
  assign abs_b     = (is_signed && ex_b[31]) ? -ex_b : ex_b;
  assign start     = ex_valid && ex_is_div && !d_busy && !d_done && !flush;

  // one restoring step
  logic [32:0] rem_shift;
  logic [32:0] rem_sub;
  assign rem_shift = {d_rem[31:0], d_quo[31]};
  assign rem_sub   = rem_shift - {1'b0, d_div};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      d_busy     <= 1'b0;
      d_done     <= 1'b0;
      d_count    <= '0;
      d_quo      <= '0;
      d_rem      <= '0;
      d_div      <= '0;
      d_neg_q    <= 1'b0;
      d_neg_r    <= 1'b0;
      d_want_rem <= 1'b0;
      d_result_q <= '0;
    end else if (flush) begin
      d_busy <= 1'b0;
      d_done <= 1'b0;
    end else if (start) begin
      d_want_rem <= ex_funct3[1];
      if (ex_b == 32'd0) begin
        // x / 0 = all ones, x % 0 = x (no sign fix-up)
        d_result_q <= ex_funct3[1] ? ex_a : 32'hFFFF_FFFF;
        d_done     <= 1'b1;
      end else begin
        d_quo   <= abs_a;
        d_rem   <= '0;
        d_div   <= abs_b;
        d_neg_q <= is_signed && (ex_a[31] ^ ex_b[31]);
        d_neg_r <= is_signed && ex_a[31];
        d_count <= 6'd32;
        d_busy  <= 1'b1;
      end
    end else if (d_busy) begin
      if (!rem_sub[32]) begin
        d_rem <= rem_sub;
        d_quo <= {d_quo[30:0], 1'b1};
      end else begin
        d_rem <= rem_shift;
        d_quo <= {d_quo[30:0], 1'b0};
      end
      d_count <= d_count - 6'd1;
      if (d_count == 6'd1) begin
        d_busy <= 1'b0;
        d_done <= 1'b1;
      end
    end else if (d_done && ex_advance) begin
      d_done <= 1'b0;
    end
  end

  // Result fix-up. INT_MIN / -1 falls out naturally: |a| / 1 = 0x80000000,
  // negated is still 0x80000000, remainder 0.
  logic [31:0] q_fix, r_fix;
  assign q_fix = d_neg_q ? -d_quo        : d_quo;
  assign r_fix = d_neg_r ? -d_rem[31:0]  : d_rem[31:0];

  logic d_zero_path;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)       d_zero_path <= 1'b0;
    else if (start)   d_zero_path <= (ex_b == 32'd0);
  end

  assign div_result = d_zero_path ? d_result_q : (d_want_rem ? r_fix : q_fix);
  assign div_stall  = ex_valid && ex_is_div && !d_done;

endmodule
