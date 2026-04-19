// core_pkg.sv
// Shared constants, enums and pipeline register types for the RV32IM core.

package core_pkg;

  // ---------------------------------------------------------------------------
  // Base opcodes (instr[6:0])
  // ---------------------------------------------------------------------------
  localparam logic [6:0] OPC_LOAD     = 7'b0000011;
  localparam logic [6:0] OPC_MISC_MEM = 7'b0001111;
  localparam logic [6:0] OPC_OP_IMM   = 7'b0010011;
  localparam logic [6:0] OPC_AUIPC    = 7'b0010111;
  localparam logic [6:0] OPC_STORE    = 7'b0100011;
  localparam logic [6:0] OPC_OP       = 7'b0110011;
  localparam logic [6:0] OPC_LUI      = 7'b0110111;
  localparam logic [6:0] OPC_BRANCH   = 7'b1100011;
  localparam logic [6:0] OPC_JALR     = 7'b1100111;
  localparam logic [6:0] OPC_JAL      = 7'b1101111;
  localparam logic [6:0] OPC_SYSTEM   = 7'b1110011;

  // funct3 encodings that get reused across units
  localparam logic [2:0] F3_BEQ  = 3'b000, F3_BNE  = 3'b001,
                         F3_BLT  = 3'b100, F3_BGE  = 3'b101,
                         F3_BLTU = 3'b110, F3_BGEU = 3'b111;

  localparam logic [2:0] F3_LB = 3'b000, F3_LH = 3'b001, F3_LW = 3'b010,
                         F3_LBU = 3'b100, F3_LHU = 3'b101;

  localparam logic [2:0] F3_MUL  = 3'b000, F3_MULH  = 3'b001,
                         F3_MULHSU = 3'b010, F3_MULHU = 3'b011,
                         F3_DIV  = 3'b100, F3_DIVU  = 3'b101,
                         F3_REM  = 3'b110, F3_REMU  = 3'b111;

  localparam logic [2:0] F3_CSRRW  = 3'b001, F3_CSRRS  = 3'b010, F3_CSRRC  = 3'b011,
                         F3_CSRRWI = 3'b101, F3_CSRRSI = 3'b110, F3_CSRRCI = 3'b111;

  // ---------------------------------------------------------------------------
  // Exception / interrupt causes (mcause[3:0]); bit 4 of exc_cause_t = interrupt
  // ---------------------------------------------------------------------------
  typedef logic [4:0] exc_cause_t;

  localparam exc_cause_t EXC_INSN_MISALIGNED  = 5'd0;
  localparam exc_cause_t EXC_ILLEGAL_INSN     = 5'd2;
  localparam exc_cause_t EXC_BREAKPOINT       = 5'd3;
  localparam exc_cause_t EXC_LOAD_MISALIGNED  = 5'd4;
  localparam exc_cause_t EXC_STORE_MISALIGNED = 5'd6;
  localparam exc_cause_t EXC_ECALL_M          = 5'd11;
  localparam exc_cause_t IRQ_M_TIMER          = 5'b1_0111;

  // ---------------------------------------------------------------------------
  // Datapath selects
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND
  } alu_op_e;

  typedef enum logic [1:0] { OPA_RS1, OPA_PC, OPA_ZERO } opa_sel_e;
  typedef enum logic       { OPB_RS2, OPB_IMM }          opb_sel_e;

  // Where the instruction's rd value comes from. LOAD/MUL/CSR results are only
  // known in MEM ("late" results) and cannot be forwarded from EX/MEM.
  typedef enum logic [2:0] {
    RES_ALU, RES_PC4, RES_DIV, RES_LOAD, RES_MUL, RES_CSR
  } res_sel_e;

  // Forwarding mux select for each EX operand
  typedef enum logic [1:0] { FWD_NONE, FWD_EXMEM, FWD_MEMWB } fwd_sel_e;

  // ---------------------------------------------------------------------------
  // Decoded control word
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic        illegal;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic        rs1_used;
    logic        rs2_used;
    logic        rd_we;        // already qualified with rd != 0
    logic [31:0] imm;
    alu_op_e     alu_op;
    opa_sel_e    opa_sel;
    opb_sel_e    opb_sel;
    res_sel_e    res_sel;
    logic        is_branch;
    logic        is_jal;
    logic        is_jalr;
    logic        mem_read;
    logic        mem_write;
    logic [2:0]  funct3;
    logic        is_mul;
    logic        is_div;
    logic        is_csr;
    logic        csr_imm;      // CSRR*I form: operand is the zero-extended rs1 field
    logic        csr_wr;       // CSR is written (RW always; RS/RC only when rs1/uimm != 0)
    logic [11:0] csr_addr;
    logic        is_ecall;
    logic        is_ebreak;
    logic        is_mret;
  } ctrl_t;

  function automatic logic res_is_late(res_sel_e r);
    return (r == RES_LOAD) || (r == RES_MUL) || (r == RES_CSR);
  endfunction

  // ---------------------------------------------------------------------------
  // Pipeline registers
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] insn;
    ctrl_t       ctrl;
    logic [31:0] rs1_val;
    logic [31:0] rs2_val;
    logic        pred_taken;
    logic [31:0] pred_target;
    logic        exc;
    exc_cause_t  exc_cause;
  } id_ex_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] insn;
    logic [31:0] next_pc;
    ctrl_t       ctrl;
    logic [31:0] result;       // ALU / PC+4 / DIV result, or load/store address
    logic [31:0] op_data;      // store data (rs2) or CSR write operand
    logic [3:0]  mem_be;
    logic        exc;
    exc_cause_t  exc_cause;
    logic [31:0] exc_tval;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;        // instruction retires this cycle in WB
    logic [31:0] pc;
    logic [31:0] insn;
    logic [31:0] next_pc;
    logic [4:0]  rd;
    logic        rd_we;
    logic [31:0] rd_wdata;
    logic [31:0] mem_addr;
    logic [3:0]  mem_rmask;
    logic [3:0]  mem_wmask;
    logic [31:0] mem_wdata;
  } mem_wb_t;

  // ---------------------------------------------------------------------------
  // Memory map (core view)
  // ---------------------------------------------------------------------------
  localparam logic [31:0] IMEM_BASE = 32'h0000_0000;
  localparam logic [31:0] DMEM_BASE = 32'h0001_0000;
  localparam logic [31:0] MMIO_BASE = 32'h1000_0000;

  // tohost is 8 bytes wide (upper word reserved) so the layout stays
  // compatible with Spike's 64-bit HTIF tohost when running the same ELF.
  localparam logic [7:0] MMIO_TOHOST    = 8'h00;
  localparam logic [7:0] MMIO_CONSOLE   = 8'h08;
  localparam logic [7:0] MMIO_MTIME     = 8'h10;
  localparam logic [7:0] MMIO_MTIMEH    = 8'h14;
  localparam logic [7:0] MMIO_MTIMECMP  = 8'h18;
  localparam logic [7:0] MMIO_MTIMECMPH = 8'h1C;
  localparam logic [7:0] MMIO_LED       = 8'h20;

endpackage
