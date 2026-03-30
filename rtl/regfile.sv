// regfile.sv
// 32 x 32-bit register file, 2 asynchronous read ports, 1 synchronous write port.
// x0 is hard-wired to zero. Maps to distributed RAM (LUTRAM) on 7-series.
//
// With BYPASS = 1, reads are write-through: if WB writes the register ID is
// reading in the same cycle, the new value is returned. This closes the
// WB -> ID hazard without a separate forwarding path. The single-cycle core
// uses BYPASS = 0 (it reads and writes the same register in one cycle).

module regfile #(
  parameter bit BYPASS = 1'b1
) (
  input  logic        clk,

  input  logic [4:0]  ra1,
  output logic [31:0] rd1,
  input  logic [4:0]  ra2,
  output logic [31:0] rd2,

  input  logic        we,
  input  logic [4:0]  wa,
  input  logic [31:0] wd
);

  logic [31:0] regs [32];

  always_ff @(posedge clk) begin
    if (we && wa != 5'd0)
      regs[wa] <= wd;
  end

  always_comb begin
    if (ra1 == 5'd0)                    rd1 = '0;
    else if (BYPASS && we && wa == ra1) rd1 = wd;
    else                                rd1 = regs[ra1];

    if (ra2 == 5'd0)                    rd2 = '0;
    else if (BYPASS && we && wa == ra2) rd2 = wd;
    else                                rd2 = regs[ra2];
  end

`ifndef SYNTHESIS
  initial begin
    for (int i = 0; i < 32; i++) regs[i] = '0;
  end
`endif

endmodule
