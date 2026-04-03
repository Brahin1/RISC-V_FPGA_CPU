// tcm.sv
// Tightly-coupled memory: true dual-port block RAM with byte write enables.
//   Port A : PS side (AXI BRAM Controller) - program load / result readback
//   Port B : core side
// Both ports are synchronous read with an output that holds when en = 0.
// Written in the Xilinx byte-write template so Vivado infers RAMB36E1.

module tcm #(
  parameter int    DEPTH_WORDS = 8192,          // 32 KB
  parameter string INIT_FILE   = "",
  parameter string PLUSARG     = ""             // simulation only
) (
  // port A
  input  logic        a_clk,
  input  logic        a_en,
  input  logic [3:0]  a_we,
  input  logic [$clog2(DEPTH_WORDS)-1:0] a_addr,   // word address
  input  logic [31:0] a_wdata,
  output logic [31:0] a_rdata,

  // port B
  input  logic        b_clk,
  input  logic        b_en,
  input  logic [3:0]  b_we,
  input  logic [$clog2(DEPTH_WORDS)-1:0] b_addr,   // word address
  input  logic [31:0] b_wdata,
  output logic [31:0] b_rdata
);

  (* ram_style = "block" *) logic [31:0] mem [DEPTH_WORDS];

  always_ff @(posedge a_clk) begin
    if (a_en) begin
      for (int i = 0; i < 4; i++)
        if (a_we[i]) mem[a_addr][8*i +: 8] <= a_wdata[8*i +: 8];
      a_rdata <= mem[a_addr];
    end
  end

  always_ff @(posedge b_clk) begin
    if (b_en) begin
      for (int i = 0; i < 4; i++)
        if (b_we[i]) mem[b_addr][8*i +: 8] <= b_wdata[8*i +: 8];
      b_rdata <= mem[b_addr];
    end
  end

  initial begin
    for (int i = 0; i < DEPTH_WORDS; i++) mem[i] = '0;
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
`ifndef SYNTHESIS
    // simulation loader: +imem=<file>.hex / +dmem=<file>.hex
    if (PLUSARG != "") begin
      string path;
      if ($value$plusargs({PLUSARG, "=%s"}, path)) $readmemh(path, mem);
    end
`endif
  end

endmodule
