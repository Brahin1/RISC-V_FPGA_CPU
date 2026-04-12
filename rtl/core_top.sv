// core_top.sv
// RV32IM + Zicsr five-stage in-order pipeline: IF -> ID -> EX -> MEM -> WB.
//
//   IF  : next-PC select + branch prediction, IMEM (sync BRAM) address
//   ID  : decode, register read
//   EX  : forwarding, ALU, branch resolve, AGU, DMEM request, divider
//   MEM : load align, MUL product, CSR access, traps / MRET (commit point)
//   WB  : register write, retire port
//
// Pipeline control priority (highest first):
//   1. trap / MRET / interrupt replay in MEM : redirect, flush ID + EX
//   2. divider busy in EX                    : hold IF/ID/EX, bubble into MEM
//   3. mispredict resolved in EX             : redirect, squash ID
//   4. load-use / mul-use interlock          : hold IF/ID, bubble into EX

module core_top
  import core_pkg::*;
#(
  parameter logic [31:0] RESET_PC = 32'h0000_0000,
  parameter int          BP_MODE  = 1
) (
  input  logic        clk,
  input  logic        rst_n,

  // instruction memory (synchronous read)
  output logic        imem_en,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  // data memory / MMIO (request in EX, read data valid next cycle)
  output logic        dmem_req,
  output logic        dmem_we,
  output logic [3:0]  dmem_be,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,

  input  logic        timer_irq,

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

  // ---------------------------------------------------------------------------
  // Pipeline registers
  // ---------------------------------------------------------------------------
  id_ex_t  id_ex;
  ex_mem_t ex_mem;
  mem_wb_t mem_wb;

  // IF -> ID
  logic        id_valid;
  logic [31:0] id_pc, id_insn, id_pred_target;
  logic        id_pred_taken;

  // hazards / control
  logic [4:0]  id_rs1, id_rs2;
  logic        id_rs1_used, id_rs2_used;
  fwd_sel_e    fwd_a, fwd_b;
  logic        load_use, mul_use, interlock;
  logic        div_stall;

  logic        ex_redirect, mem_redirect;
  logic [31:0] ex_redirect_pc, mem_redirect_pc;
  logic        redirect;
  logic [31:0] redirect_pc;

  logic        flush;            // from MEM
  logic        hold_if;

  // predictor update
  logic        bp_up_valid, bp_up_is_cond, bp_up_taken;
  logic [31:0] bp_up_pc, bp_up_target;

  // forwarding data
  logic [31:0] fwd_exmem, fwd_memwb;

  // MEM <-> CSR
  logic        csr_acc_valid, csr_acc_wr, csr_acc_illegal;
  logic [2:0]  csr_acc_funct3;
  logic [11:0] csr_acc_addr;
  logic [31:0] csr_acc_operand, csr_acc_rdata;
  logic [31:0] csr_mtvec, csr_mepc;
  logic        irq_pending;
  logic        trap_take, mret_take;
  exc_cause_t  trap_cause;
  logic [31:0] trap_pc, trap_tval;

  logic [31:0] mul_result;

  // WB
  logic        rf_we;
  logic [4:0]  rf_wa;
  logic [31:0] rf_wd;

  // events
  logic ev_br_mispredict, ev_jmp_redirect, ev_branch;

  // ---------------------------------------------------------------------------
  // Control
  // ---------------------------------------------------------------------------
  assign flush     = mem_redirect;
  assign interlock = (load_use || mul_use) && !flush;
  assign redirect    = mem_redirect || ex_redirect;
  assign redirect_pc = mem_redirect ? mem_redirect_pc : ex_redirect_pc;
  assign hold_if     = (div_stall || interlock) && !flush;

  // ---------------------------------------------------------------------------
  // Stages
  // ---------------------------------------------------------------------------
  if_stage #(.RESET_PC(RESET_PC), .BP_MODE(BP_MODE)) u_if (
    .clk            (clk),
    .rst_n          (rst_n),
    .hold           (hold_if),
    .redirect       (redirect),
    .redirect_pc    (redirect_pc),
    .bp_up_valid    (bp_up_valid),
    .bp_up_is_cond  (bp_up_is_cond),
    .bp_up_taken    (bp_up_taken),
    .bp_up_pc       (bp_up_pc),
    .bp_up_target   (bp_up_target),
    .imem_en        (imem_en),
    .imem_addr      (imem_addr),
    .imem_rdata     (imem_rdata),
    .id_valid       (id_valid),
    .id_pc          (id_pc),
    .id_insn        (id_insn),
    .id_pred_taken  (id_pred_taken),
    .id_pred_target (id_pred_target)
  );

  id_stage u_id (
    .clk            (clk),
    .rst_n          (rst_n),
    .id_valid       (id_valid),
    .id_pc          (id_pc),
    .id_insn        (id_insn),
    .id_pred_taken  (id_pred_taken),
    .id_pred_target (id_pred_target),
    .flush          (flush),
    .hold_ex        (div_stall),
    .bubble         (ex_redirect || interlock),
    .irq_pending    (irq_pending),
    .rf_we          (rf_we),
    .rf_wa          (rf_wa),
    .rf_wd          (rf_wd),
    .id_rs1         (id_rs1),
    .id_rs2         (id_rs2),
    .id_rs1_used    (id_rs1_used),
    .id_rs2_used    (id_rs2_used),
    .id_ex          (id_ex)
  );

  hazard_unit u_hazard (
    .id_rs1      (id_rs1),
    .id_rs2      (id_rs2),
    .id_rs1_used (id_rs1_used),
    .id_rs2_used (id_rs2_used),
    .ex_valid    (id_ex.valid),
    .ex_rs1      (id_ex.ctrl.rs1),
    .ex_rs2      (id_ex.ctrl.rs2),
    .ex_rd       (id_ex.ctrl.rd),
    .ex_rd_we    (id_ex.ctrl.rd_we),
    .ex_res_sel  (id_ex.ctrl.res_sel),
    .mem_valid   (ex_mem.valid),
    .mem_rd      (ex_mem.ctrl.rd),
    .mem_rd_we   (ex_mem.ctrl.rd_we),
    .mem_res_sel (ex_mem.ctrl.res_sel),
    .wb_rd_we    (rf_we),
    .wb_rd       (rf_wa),
    .fwd_a       (fwd_a),
    .fwd_b       (fwd_b),
    .load_use    (load_use),
    .mul_use     (mul_use)
  );

  ex_stage u_ex (
    .clk              (clk),
    .rst_n            (rst_n),
    .id_ex            (id_ex),
    .fwd_a            (fwd_a),
    .fwd_b            (fwd_b),
    .fwd_exmem        (fwd_exmem),
    .fwd_memwb        (fwd_memwb),
    .flush            (flush),
    .div_stall        (div_stall),
    .redirect         (ex_redirect),
    .redirect_pc      (ex_redirect_pc),
    .bp_up_valid      (bp_up_valid),
    .bp_up_is_cond    (bp_up_is_cond),
    .bp_up_taken      (bp_up_taken),
    .bp_up_pc         (bp_up_pc),
    .bp_up_target     (bp_up_target),
    .ev_br_mispredict (ev_br_mispredict),
    .ev_jmp_redirect  (ev_jmp_redirect),
    .ev_branch        (ev_branch),
    .dmem_req         (dmem_req),
    .dmem_we          (dmem_we),
    .dmem_be          (dmem_be),
    .dmem_addr        (dmem_addr),
    .dmem_wdata       (dmem_wdata),
    .mul_result       (mul_result),
    .ex_mem           (ex_mem)
  );

  mem_stage u_mem (
    .clk             (clk),
    .rst_n           (rst_n),
    .ex_mem          (ex_mem),
    .dmem_rdata      (dmem_rdata),
    .mul_result      (mul_result),
    .csr_acc_valid   (csr_acc_valid),
    .csr_acc_funct3  (csr_acc_funct3),
    .csr_acc_addr    (csr_acc_addr),
    .csr_acc_wr      (csr_acc_wr),
    .csr_acc_operand (csr_acc_operand),
    .csr_acc_rdata   (csr_acc_rdata),
    .csr_acc_illegal (csr_acc_illegal),
    .csr_mtvec       (csr_mtvec),
    .csr_mepc        (csr_mepc),
    .irq_pending     (irq_pending),
    .trap_take       (trap_take),
    .trap_cause      (trap_cause),
    .trap_pc         (trap_pc),
    .trap_tval       (trap_tval),
    .mret_take       (mret_take),
    .redirect        (mem_redirect),
    .redirect_pc     (mem_redirect_pc),
    .fwd_exmem       (fwd_exmem),
    .mem_wb          (mem_wb)
  );

  wb_stage u_wb (
    .clk            (clk),
    .rst_n          (rst_n),
    .mem_wb         (mem_wb),
    .rf_we          (rf_we),
    .rf_wa          (rf_wa),
    .rf_wd          (rf_wd),
    .fwd_memwb      (fwd_memwb),
    .rvfi_valid     (rvfi_valid),
    .rvfi_order     (rvfi_order),
    .rvfi_insn      (rvfi_insn),
    .rvfi_pc_rdata  (rvfi_pc_rdata),
    .rvfi_pc_wdata  (rvfi_pc_wdata),
    .rvfi_rd_addr   (rvfi_rd_addr),
    .rvfi_rd_wdata  (rvfi_rd_wdata),
    .rvfi_mem_addr  (rvfi_mem_addr),
    .rvfi_mem_rmask (rvfi_mem_rmask),
    .rvfi_mem_wmask (rvfi_mem_wmask),
    .rvfi_mem_wdata (rvfi_mem_wdata)
  );

  // ---------------------------------------------------------------------------
  // CSRs
  // ---------------------------------------------------------------------------
  logic [5:0] hpm_event;
  assign hpm_event[0] = load_use && !flush && !div_stall;
  assign hpm_event[1] = ev_br_mispredict;
  assign hpm_event[2] = ev_jmp_redirect;
  assign hpm_event[3] = (mul_use && !flush && !div_stall) || (div_stall && !flush);
  assign hpm_event[4] = ev_branch;
  assign hpm_event[5] = trap_take;

  csr u_csr (
    .clk         (clk),
    .rst_n       (rst_n),
    .acc_valid   (csr_acc_valid),
    .acc_funct3  (csr_acc_funct3),
    .acc_addr    (csr_acc_addr),
    .acc_wr      (csr_acc_wr),
    .acc_operand (csr_acc_operand),
    .acc_rdata   (csr_acc_rdata),
    .acc_illegal (csr_acc_illegal),
    .trap_take   (trap_take),
    .trap_cause  (trap_cause),
    .trap_pc     (trap_pc),
    .trap_tval   (trap_tval),
    .mret_take   (mret_take),
    .mtvec_o     (csr_mtvec),
    .mepc_o      (csr_mepc),
    .irq_pending (irq_pending),
    .timer_irq   (timer_irq),
    .instret     (mem_wb.valid),
    .hpm_event   (hpm_event)
  );

endmodule
