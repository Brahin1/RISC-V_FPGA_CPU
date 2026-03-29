// sc_core.sv
// Single-cycle RV32I reference core.
//
// Fetch, decode, execute, memory and writeback all complete in one cycle, so
// it needs combinational-read memories and is simulation-only in practice. Its
// job was to pass rv32ui before any pipelining started, and it is kept around as
// a known-good reference for debugging the five-stage core.
//
// Not supported here: M extension, CSRs (decoded as NOPs), traps. ECALL/EBREAK
// and illegal instructions assert `halt`.

module sc_core
  import core_pkg::*;
#(
  parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
  input  logic        clk,
  input  logic        rst_n,

  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,     // combinational

  output logic        dmem_re,
  output logic        dmem_we,
  output logic [3:0]  dmem_be,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,     // combinational

  output logic        halt,

  output logic        retire_valid,
  output logic [31:0] retire_pc,
  output logic [31:0] retire_insn,
  output logic [4:0]  retire_rd,
  output logic [31:0] retire_rd_wdata
);

  logic [31:0] pc;
  logic [31:0] insn;
  ctrl_t       c;

  assign imem_addr = pc;
  assign insn      = imem_rdata;

  decoder u_dec (.insn(insn), .ctrl(c));

  // register file (write-through bypass not needed: write at end of cycle)
  logic [31:0] rs1, rs2, rd_val;
  logic        rf_we;

  regfile u_rf (
    .clk (clk),
    .ra1 (c.rs1), .rd1 (rs1),
    .ra2 (c.rs2), .rd2 (rs2),
    .we  (rf_we), .wa (c.rd), .wd (rd_val)
  );

  // ALU
  logic [31:0] a, b, y;
  always_comb begin
    unique case (c.opa_sel)
      OPA_PC:   a = pc;
      OPA_ZERO: a = '0;
      default:  a = rs1;
    endcase
    b = (c.opb_sel == OPB_IMM) ? c.imm : rs2;
  end

  alu u_alu (.op(c.alu_op), .a(a), .b(b), .y(y));

  // branches / jumps
  logic        taken;
  logic [31:0] next_pc;
  always_comb begin
    unique case (c.funct3)
      F3_BEQ:  taken = (rs1 == rs2);
      F3_BNE:  taken = (rs1 != rs2);
      F3_BLT:  taken = ($signed(rs1) <  $signed(rs2));
      F3_BGE:  taken = ($signed(rs1) >= $signed(rs2));
      F3_BLTU: taken = (rs1 <  rs2);
      F3_BGEU: taken = (rs1 >= rs2);
      default: taken = 1'b0;
    endcase
    taken = c.is_jal || c.is_jalr || (c.is_branch && taken);

    if (c.is_jalr)   next_pc = (rs1 + c.imm) & ~32'd1;
    else if (taken)  next_pc = pc + c.imm;
    else             next_pc = pc + 32'd4;
  end

  // memory
  logic [1:0]  off;
  logic [31:0] shifted, load_val;
  assign off = y[1:0];

  assign dmem_re   = c.mem_read;
  assign dmem_we   = c.mem_write;
  assign dmem_addr = y;
  always_comb begin
    unique case (c.funct3[1:0])
      2'b00:   begin dmem_be = 4'b0001 << off; dmem_wdata = {4{rs2[7:0]}};  end
      2'b01:   begin dmem_be = 4'b0011 << off; dmem_wdata = {2{rs2[15:0]}}; end
      default: begin dmem_be = 4'b1111;        dmem_wdata = rs2;            end
    endcase
  end

  assign shifted = dmem_rdata >> {off, 3'b000};
  always_comb begin
    unique case (c.funct3)
      F3_LB:   load_val = {{24{shifted[7]}},  shifted[7:0]};
      F3_LH:   load_val = {{16{shifted[15]}}, shifted[15:0]};
      F3_LBU:  load_val = {24'b0, shifted[7:0]};
      F3_LHU:  load_val = {16'b0, shifted[15:0]};
      default: load_val = shifted;
    endcase
  end

  // writeback
  always_comb begin
    unique case (c.res_sel)
      RES_PC4:  rd_val = pc + 32'd4;
      RES_LOAD: rd_val = load_val;
      default:  rd_val = y;
    endcase
  end

  logic unsupported;
  assign unsupported = c.illegal || c.is_ecall || c.is_ebreak || c.is_mul || c.is_div;

  assign rf_we = rst_n && !halt && c.rd_we && !c.is_csr && !unsupported;
  assign halt  = unsupported;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)     pc <= RESET_PC;
    else if (!halt) pc <= next_pc;
  end

  assign retire_valid    = rst_n && !halt;
  assign retire_pc       = pc;
  assign retire_insn     = insn;
  assign retire_rd       = rf_we ? c.rd : 5'd0;
  assign retire_rd_wdata = rf_we ? rd_val : 32'd0;

endmodule
