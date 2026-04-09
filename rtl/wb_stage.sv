// wb_stage.sv
// Writeback: register file write and the retire port.
//
// The retire port follows the spirit of RVFI: one record per retired
// instruction, in program order. The lockstep checker compares it against the
// Spike commit log, and the ILA probes the same signals on hardware.

module wb_stage
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  mem_wb_t     mem_wb,

  // register file write
  output logic        rf_we,
  output logic [4:0]  rf_wa,
  output logic [31:0] rf_wd,

  // forwarding value of the instruction in WB
  output logic [31:0] fwd_memwb,

  // retire port
  output logic        rvfi_valid,
  output logic [63:0] rvfi_order,
  output logic [31:0] rvfi_insn,
  output logic [31:0] rvfi_pc_rdata,
  output logic [31:0] rvfi_pc_wdata,
  output logic [4:0]  rvfi_rd_addr,
  output logic [31:0] rvfi_rd_wdata,
  output logic [31:0] rvfi_mem_addr,
  output logic [3:0]  rvfi_mem_rmask,
  output logic [3:0]  rvfi_mem_wmask,
  output logic [31:0] rvfi_mem_wdata
);

  assign rf_we     = mem_wb.rd_we;
  assign rf_wa     = mem_wb.rd;
  assign rf_wd     = mem_wb.rd_wdata;
  assign fwd_memwb = mem_wb.rd_wdata;

  logic [63:0] order;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)            order <= '0;
    else if (mem_wb.valid) order <= order + 64'd1;
  end

  assign rvfi_valid     = mem_wb.valid;
  assign rvfi_order     = order;
  assign rvfi_insn      = mem_wb.insn;
  assign rvfi_pc_rdata  = mem_wb.pc;
  assign rvfi_pc_wdata  = mem_wb.next_pc;
  assign rvfi_rd_addr   = mem_wb.rd_we ? mem_wb.rd : 5'd0;
  assign rvfi_rd_wdata  = mem_wb.rd_we ? mem_wb.rd_wdata : 32'd0;
  assign rvfi_mem_addr  = mem_wb.mem_addr;
  assign rvfi_mem_rmask = mem_wb.mem_rmask;
  assign rvfi_mem_wmask = mem_wb.mem_wmask;
  assign rvfi_mem_wdata = mem_wb.mem_wdata;

endmodule
