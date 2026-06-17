// csr.sv
// Machine-mode CSR file (Zicsr), trap/MRET state updates and counters.
//
// All CSR reads and writes happen in MEM, which is the commit point of the
// pipeline: anything older has already left MEM, and anything younger can still
// be flushed. Traps are taken there as well, so mepc/mcause/mtval updates and
// CSR instruction writes are never speculative.

module csr
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // ---- CSR instruction in MEM ------------------------------------------------
  input  logic        acc_valid,      // valid CSR instruction (no earlier exception)
  input  logic [2:0]  acc_funct3,
  input  logic [11:0] acc_addr,
  input  logic        acc_wr,         // CSRRS/C with rs1=x0 do not write
  input  logic [31:0] acc_operand,    // rs1 value or zero-extended uimm
  output logic [31:0] acc_rdata,
  output logic        acc_illegal,

  // ---- trap / return -----------------------------------------------------------
  input  logic        trap_take,
  input  exc_cause_t  trap_cause,
  input  logic [31:0] trap_pc,
  input  logic [31:0] trap_tval,
  input  logic        mret_take,

  output logic [31:0] mtvec_o,
  output logic [31:0] mepc_o,
  output logic        irq_pending,    // enabled timer interrupt is pending

  // ---- events --------------------------------------------------------------------
  input  logic        timer_irq,      // mtime >= mtimecmp
  input  logic        instret,        // instruction retiring in WB this cycle
  input  logic [5:0]  hpm_event       // custom performance counter increments
);

  // ---------------------------------------------------------------------------
  // CSR addresses
  // ---------------------------------------------------------------------------
  localparam logic [11:0]
    CSR_MSTATUS  = 12'h300, CSR_MISA     = 12'h301, CSR_MIE      = 12'h304,
    CSR_MTVEC    = 12'h305, CSR_MSCRATCH = 12'h340, CSR_MEPC     = 12'h341,
    CSR_MCAUSE   = 12'h342, CSR_MTVAL    = 12'h343, CSR_MIP      = 12'h344,
    CSR_MCYCLE   = 12'hB00, CSR_MINSTRET = 12'hB02,
    CSR_MCYCLEH  = 12'hB80, CSR_MINSTRETH= 12'hB82,
    CSR_CYCLE    = 12'hC00, CSR_INSTRET  = 12'hC02,
    CSR_CYCLEH   = 12'hC80, CSR_INSTRETH = 12'hC82,
    CSR_MVENDORID= 12'hF11, CSR_MARCHID  = 12'hF12, CSR_MIMPID   = 12'hF13,
    CSR_MHARTID  = 12'hF14;

  // mhpmcounter3..8 (0xB03-0xB08) and their user aliases (0xC03-0xC08)
  //   3: load-use interlock cycles
  //   4: conditional branch mispredicts
  //   5: JAL/JALR redirects (target mispredicted)
  //   6: MUL-use interlock + divider stall cycles
  //   7: conditional branches executed
  //   8: traps taken (exceptions + interrupts)
  localparam int NHPM = 6;

  localparam logic [31:0] MISA_VAL = 32'h4000_1100;   // RV32, I + M

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  logic        mstatus_mie, mstatus_mpie;
  logic        mie_msie, mie_mtie, mie_meie;
  logic [31:0] mtvec, mscratch, mepc, mtval;
  logic        mcause_irq;
  logic [3:0]  mcause_code;
  logic [63:0] mcycle, minstret;
  logic [31:0] hpm [NHPM];

  logic [31:0] mstatus_r, mie_r, mip_r, mcause_r;
  assign mstatus_r = {19'b0, 2'b11, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
  assign mie_r     = {20'b0, mie_meie, 3'b0, mie_mtie, 3'b0, mie_msie, 3'b0};
  assign mip_r     = {24'b0, timer_irq, 7'b0};
  assign mcause_r  = {mcause_irq, 27'b0, mcause_code};

  // minstret as seen by an instruction in MEM must include the older instruction
  // retiring in WB this same cycle.
  logic [63:0] minstret_view;
  assign minstret_view = minstret + {63'b0, instret};

  // ---------------------------------------------------------------------------
  // Read mux
  // ---------------------------------------------------------------------------
  logic       known;
  logic       hpm_sel;
  logic [3:0] hpm_idx;
  assign hpm_idx = acc_addr[3:0];
  assign hpm_sel = (acc_addr[11:4] == 8'hB0 || acc_addr[11:4] == 8'hC0) &&
                   (hpm_idx >= 4'd3) && (hpm_idx <= 4'd8);

  always_comb begin
    known     = 1'b1;
    acc_rdata = '0;
    if (hpm_sel) begin
      acc_rdata = hpm[3'(hpm_idx - 4'd3)];
    end else unique case (acc_addr)
      CSR_MSTATUS:   acc_rdata = mstatus_r;
      CSR_MISA:      acc_rdata = MISA_VAL;
      CSR_MIE:       acc_rdata = mie_r;
      CSR_MTVEC:     acc_rdata = mtvec;
      CSR_MSCRATCH:  acc_rdata = mscratch;
      CSR_MEPC:      acc_rdata = mepc;
      CSR_MCAUSE:    acc_rdata = mcause_r;
      CSR_MTVAL:     acc_rdata = mtval;
      CSR_MIP:       acc_rdata = mip_r;
      CSR_MCYCLE,   CSR_CYCLE:    acc_rdata = mcycle[31:0];
      CSR_MCYCLEH,  CSR_CYCLEH:   acc_rdata = mcycle[63:32];
      CSR_MINSTRET, CSR_INSTRET:  acc_rdata = minstret_view[31:0];
      CSR_MINSTRETH,CSR_INSTRETH: acc_rdata = minstret_view[63:32];
      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID: acc_rdata = '0;
      default:       known = 1'b0;
    endcase
  end

  // Writing a read-only CSR (addr[11:10] == 2'b11) is illegal.
  assign acc_illegal = acc_valid && (!known || (acc_wr && acc_addr[11:10] == 2'b11));

  // ---------------------------------------------------------------------------
  // Write data
  // ---------------------------------------------------------------------------
  logic [31:0] wdata;
  always_comb begin
    unique case (acc_funct3[1:0])
      2'b01:   wdata = acc_operand;                 // RW
      2'b10:   wdata = acc_rdata |  acc_operand;    // RS
      2'b11:   wdata = acc_rdata & ~acc_operand;    // RC
      default: wdata = acc_rdata;
    endcase
  end

  logic do_write;
  assign do_write = acc_valid && acc_wr && !acc_illegal;

  // ---------------------------------------------------------------------------
  // Sequential
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus_mie  <= 1'b0;
      mstatus_mpie <= 1'b0;
      mie_msie     <= 1'b0;
      mie_mtie     <= 1'b0;
      mie_meie     <= 1'b0;
      mtvec        <= '0;
      mscratch     <= '0;
      mepc         <= '0;
      mtval        <= '0;
      mcause_irq   <= 1'b0;
      mcause_code  <= '0;
      mcycle       <= '0;
      minstret     <= '0;
      for (int i = 0; i < NHPM; i++) hpm[i] <= '0;
    end else begin
      // free-running counters (an explicit write below takes priority)
      mcycle   <= mcycle + 64'd1;
      minstret <= minstret + {63'b0, instret};
      for (int i = 0; i < NHPM; i++)
        if (hpm_event[i]) hpm[i] <= hpm[i] + 32'd1;

      if (trap_take) begin
        mepc         <= {trap_pc[31:2], 2'b00};
        mcause_irq   <= trap_cause[4];
        mcause_code  <= trap_cause[3:0];
        mtval        <= trap_tval;
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= 1'b0;
      end else if (mret_take) begin
        mstatus_mie  <= mstatus_mpie;
        mstatus_mpie <= 1'b1;
      end else if (do_write) begin
        unique case (acc_addr)
          CSR_MSTATUS: begin
            mstatus_mie  <= wdata[3];
            mstatus_mpie <= wdata[7];
          end
          CSR_MIE: begin
            mie_msie <= wdata[3];
            mie_mtie <= wdata[7];
            mie_meie <= wdata[11];
          end
          CSR_MTVEC:     mtvec    <= {wdata[31:2], 2'b00};   // direct mode only
          CSR_MSCRATCH:  mscratch <= wdata;
          CSR_MEPC:      mepc     <= {wdata[31:2], 2'b00};
          CSR_MCAUSE: begin
            mcause_irq  <= wdata[31];
            mcause_code <= wdata[3:0];
          end
          CSR_MTVAL:     mtval    <= wdata;
          CSR_MCYCLE:    mcycle[31:0]    <= wdata;
          CSR_MCYCLEH:   mcycle[63:32]   <= wdata;
          CSR_MINSTRET:  minstret        <= {minstret_view[63:32], wdata};
          CSR_MINSTRETH: minstret        <= {wdata, minstret_view[31:0]};
          default: ;
        endcase
      end
    end
  end

  assign mtvec_o     = mtvec;
  assign mepc_o      = mepc;
  assign irq_pending = mstatus_mie && mie_mtie && timer_irq;

endmodule
