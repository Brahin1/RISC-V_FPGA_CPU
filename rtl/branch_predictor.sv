// branch_predictor.sv
// Next-fetch-address predictor used by IF.
//
// MODE = 0 : static not-taken (always pc + 4)
// MODE = 1 : static BTFN (backward taken / forward not-taken, JAL always taken),
//            decoded from the instruction word currently in ID
// MODE = 2 : 64-entry direct-mapped BTB with a 2-bit saturating counter per
//            entry. JAL/JALR entries are always predicted taken.
//
// The lookup is done with the PC of the instruction that was just fetched (the
// one sitting in ID), so a correct taken prediction costs zero bubbles.
// Updates come from EX when a control-flow instruction resolves.

module branch_predictor #(
  parameter int MODE    = 2,
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
    if (MODE == 2) begin : g_btb

      logic [ENTRIES-1:0] v;
      logic [ENTRIES-1:0] uncond;
      logic [TAG_W-1:0]   tag    [ENTRIES];
      logic [31:2]        target [ENTRIES];
      logic [1:0]         ctr    [ENTRIES];

      logic [IDX_W-1:0] lk_idx, up_idx;
      assign lk_idx = lk_pc[IDX_W+1:2];
      assign up_idx = up_pc[IDX_W+1:2];

      logic lk_hit;
      assign lk_hit    = lk_valid && v[lk_idx] && (tag[lk_idx] == lk_pc[31:IDX_W+2]);
      assign lk_taken  = lk_hit && (uncond[lk_idx] || ctr[lk_idx][1]);
      assign lk_target = {target[lk_idx], 2'b00};

      logic up_hit;
      assign up_hit = v[up_idx] && (tag[up_idx] == up_pc[31:IDX_W+2]);

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          v <= '0;
        end else if (up_valid && (up_taken || up_hit)) begin
          v[up_idx] <= 1'b1;
        end
      end

      // Arrays without reset -> LUTRAM
      always_ff @(posedge clk) begin
        if (up_valid) begin
          if (!up_is_cond) begin
            tag[up_idx]    <= up_pc[31:IDX_W+2];
            target[up_idx] <= up_target[31:2];
            uncond[up_idx] <= 1'b1;
            ctr[up_idx]    <= 2'b11;
          end else if (up_hit) begin
            if (up_taken) begin
              target[up_idx] <= up_target[31:2];
              if (ctr[up_idx] != 2'b11) ctr[up_idx] <= ctr[up_idx] + 2'd1;
            end else begin
              if (ctr[up_idx] != 2'b00) ctr[up_idx] <= ctr[up_idx] - 2'd1;
            end
            uncond[up_idx] <= 1'b0;
          end else if (up_taken) begin
            // allocate on first taken occurrence, weakly taken
            tag[up_idx]    <= up_pc[31:IDX_W+2];
            target[up_idx] <= up_target[31:2];
            uncond[up_idx] <= 1'b0;
            ctr[up_idx]    <= 2'b10;
          end
        end
      end

    end else if (MODE == 1) begin : g_btfn

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
