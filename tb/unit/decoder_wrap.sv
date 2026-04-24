// decoder_wrap.sv - flattens ctrl_t so cocotb can see the fields
module decoder_wrap
  import core_pkg::*;
(
  input  logic [31:0] insn,
  output logic        illegal,
  output logic        rd_we,
  output logic        rs1_used,
  output logic        rs2_used,
  output logic [31:0] imm,
  output logic        is_branch,
  output logic        is_jal,
  output logic        is_jalr,
  output logic        mem_read,
  output logic        mem_write,
  output logic        is_mul,
  output logic        is_div,
  output logic        is_csr,
  output logic        csr_wr,
  output logic        is_ecall,
  output logic        is_ebreak,
  output logic        is_mret
);
  ctrl_t c;
  decoder u_dec (.insn(insn), .ctrl(c));

  assign illegal   = c.illegal;
  assign rd_we     = c.rd_we;
  assign rs1_used  = c.rs1_used;
  assign rs2_used  = c.rs2_used;
  assign imm       = c.imm;
  assign is_branch = c.is_branch;
  assign is_jal    = c.is_jal;
  assign is_jalr   = c.is_jalr;
  assign mem_read  = c.mem_read;
  assign mem_write = c.mem_write;
  assign is_mul    = c.is_mul;
  assign is_div    = c.is_div;
  assign is_csr    = c.is_csr;
  assign csr_wr    = c.csr_wr;
  assign is_ecall  = c.is_ecall;
  assign is_ebreak = c.is_ebreak;
  assign is_mret   = c.is_mret;
endmodule
