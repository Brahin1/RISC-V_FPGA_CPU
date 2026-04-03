// soc_top.sv
// Core + IMEM/DMEM TCMs + MMIO.
//
// Core view of the address space:
//   0x0000_0000 - 0x0000_7FFF  IMEM (instruction fetch only)
//   0x0001_0000 - 0x0001_7FFF  DMEM
//   0x1000_0000 - 0x1000_00FF  MMIO (tohost, console, mtime, mtimecmp, led)
// Data accesses outside DMEM/MMIO read as zero and writes are dropped.
//
// Port A of each TCM is brought out for the PS (AXI BRAM Controller) so the ARM
// can load programs and read results without touching the core datapath.

module soc_top
  import core_pkg::*;
#(
  parameter int IMEM_WORDS = 8192,
  parameter int DMEM_WORDS = 8192,
  parameter int BP_MODE    = 1
) (
  input  logic        clk,
  input  logic        rst_n,

  // PS access to IMEM / DMEM (port A, byte address within the memory)
  input  logic        imem_a_en,
  input  logic [3:0]  imem_a_we,
  input  logic [31:0] imem_a_addr,
  input  logic [31:0] imem_a_wdata,
  output logic [31:0] imem_a_rdata,

  input  logic        dmem_a_en,
  input  logic [3:0]  dmem_a_we,
  input  logic [31:0] dmem_a_addr,
  input  logic [31:0] dmem_a_wdata,
  output logic [31:0] dmem_a_rdata,

  // status
  output logic        tohost_valid,
  output logic [31:0] tohost_data,
  output logic        console_valid,
  output logic [7:0]  console_byte,
  input  logic        con_pop,
  output logic [7:0]  con_data,
  output logic        con_empty,
  output logic [7:0]  led,

  // retire port (simulation trace / ILA)
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

  localparam int IW = $clog2(IMEM_WORDS);
  localparam int DW = $clog2(DMEM_WORDS);

  logic        imem_en;
  logic [31:0] imem_addr, imem_rdata;

  logic        dmem_req, dmem_we;
  logic [3:0]  dmem_be;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;

  logic        timer_irq;

  core_top #(.BP_MODE(BP_MODE)) u_core (
    .clk            (clk),
    .rst_n          (rst_n),
    .imem_en        (imem_en),
    .imem_addr      (imem_addr),
    .imem_rdata     (imem_rdata),
    .dmem_req       (dmem_req),
    .dmem_we        (dmem_we),
    .dmem_be        (dmem_be),
    .dmem_addr      (dmem_addr),
    .dmem_wdata     (dmem_wdata),
    .dmem_rdata     (dmem_rdata),
    .timer_irq      (timer_irq),
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
  // Data-side address decode
  // ---------------------------------------------------------------------------
  logic sel_dmem, sel_mmio;
  assign sel_dmem = (dmem_addr[31:DW+2] == DMEM_BASE[31:DW+2]);
  assign sel_mmio = (dmem_addr[31:8]    == MMIO_BASE[31:8]);

  typedef enum logic [1:0] { RD_NONE, RD_DMEM, RD_MMIO } rd_src_e;
  rd_src_e rd_src;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                   rd_src <= RD_NONE;
    else if (dmem_req && !dmem_we) rd_src <= sel_dmem ? RD_DMEM : (sel_mmio ? RD_MMIO : RD_NONE);
  end

  logic [31:0] dmem_b_rdata, mmio_rdata;

  always_comb begin
    unique case (rd_src)
      RD_DMEM: dmem_rdata = dmem_b_rdata;
      RD_MMIO: dmem_rdata = mmio_rdata;
      default: dmem_rdata = '0;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Memories
  // ---------------------------------------------------------------------------
  tcm #(.DEPTH_WORDS(IMEM_WORDS), .PLUSARG("imem")) u_imem (
    .a_clk   (clk),
    .a_en    (imem_a_en),
    .a_we    (imem_a_we),
    .a_addr  (imem_a_addr[IW+1:2]),
    .a_wdata (imem_a_wdata),
    .a_rdata (imem_a_rdata),
    .b_clk   (clk),
    .b_en    (imem_en),
    .b_we    (4'b0000),
    .b_addr  (imem_addr[IW+1:2]),
    .b_wdata (32'd0),
    .b_rdata (imem_rdata)
  );

  tcm #(.DEPTH_WORDS(DMEM_WORDS), .PLUSARG("dmem")) u_dmem (
    .a_clk   (clk),
    .a_en    (dmem_a_en),
    .a_we    (dmem_a_we),
    .a_addr  (dmem_a_addr[DW+1:2]),
    .a_wdata (dmem_a_wdata),
    .a_rdata (dmem_a_rdata),
    .b_clk   (clk),
    .b_en    (dmem_req && sel_dmem),
    .b_we    (dmem_we ? dmem_be : 4'b0000),
    .b_addr  (dmem_addr[DW+1:2]),
    .b_wdata (dmem_wdata),
    .b_rdata (dmem_b_rdata)
  );

  mmio u_mmio (
    .clk           (clk),
    .rst_n         (rst_n),
    .req           (dmem_req && sel_mmio),
    .we            (dmem_we),
    .be            (dmem_be),
    .addr          (dmem_addr[7:0]),
    .wdata         (dmem_wdata),
    .rdata         (mmio_rdata),
    .timer_irq     (timer_irq),
    .tohost_valid  (tohost_valid),
    .tohost_data   (tohost_data),
    .console_valid (console_valid),
    .console_byte  (console_byte),
    .con_pop       (con_pop),
    .con_data      (con_data),
    .con_empty     (con_empty),
    .led           (led)
  );

endmodule
