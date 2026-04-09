// mem_stage.sv
// Memory / commit stage.
//
//  * Aligns and sign-extends load data returned by the synchronous DMEM.
//  * Picks up the MUL product (second half of the multiplier pipeline).
//  * Performs CSR accesses.
//  * Takes traps and MRET. This is the commit point: everything older has
//    already left MEM, everything younger is still flushable, and the only store
//    that could have been younger was blocked in EX by `flush`.
//
// An instruction tagged with a timer interrupt in ID is re-checked here. If the
// interrupt is no longer enabled/pending (an older CSR write disabled it), the
// instruction is replayed by redirecting fetch to its own PC.

module mem_stage
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  ex_mem_t     ex_mem,

  input  logic [31:0] dmem_rdata,
  input  logic [31:0] mul_result,

  // CSR unit interface
  output logic        csr_acc_valid,
  output logic [2:0]  csr_acc_funct3,
  output logic [11:0] csr_acc_addr,
  output logic        csr_acc_wr,
  output logic [31:0] csr_acc_operand,
  input  logic [31:0] csr_acc_rdata,
  input  logic        csr_acc_illegal,
  input  logic [31:0] csr_mtvec,
  input  logic [31:0] csr_mepc,
  input  logic        irq_pending,

  output logic        trap_take,
  output exc_cause_t  trap_cause,
  output logic [31:0] trap_pc,
  output logic [31:0] trap_tval,
  output logic        mret_take,

  // redirect fetch (trap, mret, interrupt replay)
  output logic        redirect,
  output logic [31:0] redirect_pc,

  // forwarding value of the instruction in MEM (valid only for non-late results)
  output logic [31:0] fwd_exmem,

  output mem_wb_t     mem_wb
);

  ctrl_t c;
  assign c = ex_mem.ctrl;

  // ---------------------------------------------------------------------------
  // Load data
  // ---------------------------------------------------------------------------
  logic [1:0]  off;
  logic [31:0] shifted;
  logic [31:0] load_data;

  assign off     = ex_mem.result[1:0];
  assign shifted = dmem_rdata >> {off, 3'b000};

  always_comb begin
    unique case (c.funct3)
      F3_LB:   load_data = {{24{shifted[7]}},  shifted[7:0]};
      F3_LH:   load_data = {{16{shifted[15]}}, shifted[15:0]};
      F3_LBU:  load_data = {24'b0, shifted[7:0]};
      F3_LHU:  load_data = {16'b0, shifted[15:0]};
      default: load_data = shifted;
    endcase
  end

  // ---------------------------------------------------------------------------
  // CSR access
  // ---------------------------------------------------------------------------
  assign csr_acc_valid   = ex_mem.valid && !ex_mem.exc && c.is_csr;
  assign csr_acc_funct3  = c.funct3;
  assign csr_acc_addr    = c.csr_addr;
  assign csr_acc_wr      = c.csr_wr;
  assign csr_acc_operand = ex_mem.op_data;

  // ---------------------------------------------------------------------------
  // Traps
  // ---------------------------------------------------------------------------
  logic is_irq, irq_replay;
  assign is_irq     = ex_mem.valid && ex_mem.exc && ex_mem.exc_cause[4];
  assign irq_replay = is_irq && !irq_pending;

  always_comb begin
    trap_take  = 1'b0;
    trap_cause = ex_mem.exc_cause;
    trap_tval  = ex_mem.exc_tval;
    if (ex_mem.valid) begin
      if (ex_mem.exc) begin
        trap_take = !irq_replay;
        if (is_irq) trap_tval = '0;
      end else if (csr_acc_illegal) begin
        trap_take  = 1'b1;
        trap_cause = EXC_ILLEGAL_INSN;
        trap_tval  = ex_mem.insn;
      end
    end
  end

  assign trap_pc   = ex_mem.pc;
  assign mret_take = ex_mem.valid && !ex_mem.exc && c.is_mret;

  assign redirect    = trap_take || mret_take || irq_replay;
  assign redirect_pc = trap_take ? csr_mtvec :
                       mret_take ? csr_mepc  : ex_mem.pc;

  // ---------------------------------------------------------------------------
  // Result
  // ---------------------------------------------------------------------------
  logic [31:0] rd_val;
  always_comb begin
    unique case (c.res_sel)
      RES_LOAD: rd_val = load_data;
      RES_MUL:  rd_val = mul_result;
      RES_CSR:  rd_val = csr_acc_rdata;
      default:  rd_val = ex_mem.result;
    endcase
  end

  assign fwd_exmem = ex_mem.result;

  logic retire;
  assign retire = ex_mem.valid && !ex_mem.exc && !csr_acc_illegal;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_wb <= '0;
    end else begin
      mem_wb.valid     <= retire;
      mem_wb.pc        <= ex_mem.pc;
      mem_wb.insn      <= ex_mem.insn;
      mem_wb.next_pc   <= mret_take ? csr_mepc : ex_mem.next_pc;
      mem_wb.rd        <= c.rd;
      mem_wb.rd_we     <= retire && c.rd_we;
      mem_wb.rd_wdata  <= c.rd_we ? rd_val : 32'd0;
      mem_wb.mem_addr  <= (c.mem_read || c.mem_write) ? ex_mem.result : 32'd0;
      mem_wb.mem_rmask <= c.mem_read  ? ex_mem.mem_be : 4'd0;
      mem_wb.mem_wmask <= c.mem_write ? ex_mem.mem_be : 4'd0;
      mem_wb.mem_wdata <= c.mem_write ? ex_mem.op_data : 32'd0;
    end
  end

endmodule
