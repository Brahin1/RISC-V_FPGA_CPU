// sc_tb.sv - simulation top for the single-cycle reference core
// Combinational-read memories, tohost at 0x1000_0000, console at 0x1000_0008.

module sc_tb (
  input  logic        clk,
  input  logic        rst_n,
  output logic        done,
  output logic [31:0] tohost,
  output logic        console_valid,
  output logic [7:0]  console_byte,
  output logic        halted
);

  localparam int WORDS = 8192;

  logic [31:0] imem [WORDS];
  logic [31:0] dmem [WORDS];

  initial begin
    string f;
    for (int i = 0; i < WORDS; i++) begin imem[i] = '0; dmem[i] = '0; end
    if ($value$plusargs("imem=%s", f)) $readmemh(f, imem);
    if ($value$plusargs("dmem=%s", f)) $readmemh(f, dmem);
  end

  logic [31:0] imem_addr, dmem_addr, dmem_wdata, dmem_rdata;
  logic        dmem_re, dmem_we;
  logic [3:0]  dmem_be;

  logic        rv;
  logic [31:0] rpc, rinsn, rwd;
  logic [4:0]  rrd;

  sc_core u_core (
    .clk, .rst_n,
    .imem_addr, .imem_rdata (imem[imem_addr[14:2]]),
    .dmem_re, .dmem_we, .dmem_be, .dmem_addr, .dmem_wdata, .dmem_rdata,
    .halt (halted),
    .retire_valid (rv), .retire_pc (rpc), .retire_insn (rinsn),
    .retire_rd (rrd), .retire_rd_wdata (rwd)
  );

  logic in_dmem, in_mmio;
  assign in_dmem    = dmem_addr[31:15] == 17'h0002;   // 0x0001_0000 - 0x0001_7FFF
  assign in_mmio    = dmem_addr[31:8]  == 24'h10_0000;
  assign dmem_rdata = in_dmem ? dmem[dmem_addr[14:2]] : 32'd0;

  always_ff @(posedge clk) begin
    if (rst_n && dmem_we && in_dmem && !halted)
      for (int i = 0; i < 4; i++)
        if (dmem_be[i]) dmem[dmem_addr[14:2]][8*i +: 8] <= dmem_wdata[8*i +: 8];
  end

  assign done          = rst_n && !halted && dmem_we && in_mmio && dmem_addr[7:0] == 8'h00;
  assign tohost        = dmem_wdata;
  assign console_valid = rst_n && !halted && dmem_we && in_mmio && dmem_addr[7:0] == 8'h08;
  assign console_byte  = dmem_wdata[7:0];

endmodule
