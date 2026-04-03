// mmio.sv
// Memory-mapped peripherals at 0x1000_0000:
//   +0x00 tohost    W   1 = pass, (n << 1) | 1 = test n failed
//   +0x04 console   W   low byte pushed into a 256-entry FIFO drained by the PS
//   +0x08 mtime     RW  64-bit free-running counter at the core clock
//   +0x10 mtimecmp  RW  timer interrupt when mtime >= mtimecmp
//   +0x18 led       RW
// Reads return data one cycle after the request, matching the BRAM timing.

module mmio
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // core side
  input  logic        req,
  input  logic        we,
  input  logic [3:0]  be,
  input  logic [7:0]  addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata,

  output logic        timer_irq,

  // status / PS side
  output logic        tohost_valid,
  output logic [31:0] tohost_data,
  output logic        console_valid,   // byte written this cycle (for simulation)
  output logic [7:0]  console_byte,
  input  logic        con_pop,
  output logic [7:0]  con_data,
  output logic        con_empty,
  output logic [7:0]  led
);

  logic [63:0] mtime, mtimecmp;
  logic [31:0] tohost;

  logic wr;
  assign wr = req && we;

  function automatic logic [31:0] merge(input logic [31:0] old, input logic [31:0] nw,
                                        input logic [3:0] m);
    for (int i = 0; i < 4; i++) if (m[i]) old[8*i +: 8] = nw[8*i +: 8];
    return old;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mtime    <= '0;
      mtimecmp <= '1;
      tohost   <= '0;
      led      <= '0;
    end else begin
      mtime <= mtime + 64'd1;
      if (wr) begin
        unique case (addr)
          MMIO_TOHOST:    tohost          <= merge(tohost, wdata, be);
          MMIO_MTIME:     mtime[31:0]     <= merge(mtime[31:0], wdata, be);
          MMIO_MTIMEH:    mtime[63:32]    <= merge(mtime[63:32], wdata, be);
          MMIO_MTIMECMP:  mtimecmp[31:0]  <= merge(mtimecmp[31:0], wdata, be);
          MMIO_MTIMECMPH: mtimecmp[63:32] <= merge(mtimecmp[63:32], wdata, be);
          MMIO_LED:       led             <= wdata[7:0];
          default: ;
        endcase
      end
    end
  end

  assign timer_irq = (mtime >= mtimecmp);

  assign tohost_valid  = wr && (addr == MMIO_TOHOST);
  assign tohost_data   = wdata;
  assign console_valid = wr && (addr == MMIO_CONSOLE);
  assign console_byte  = wdata[7:0];

  // read data, registered
  always_ff @(posedge clk) begin
    if (req && !we) begin
      unique case (addr)
        MMIO_TOHOST:    rdata <= tohost;
        MMIO_MTIME:     rdata <= mtime[31:0];
        MMIO_MTIMEH:    rdata <= mtime[63:32];
        MMIO_MTIMECMP:  rdata <= mtimecmp[31:0];
        MMIO_MTIMECMPH: rdata <= mtimecmp[63:32];
        MMIO_LED:       rdata <= {24'b0, led};
        default:        rdata <= '0;
      endcase
    end
  end

  // console FIFO (256 x 8) for the PS
  logic [7:0] fifo [256];
  logic [8:0] wptr, rptr;
  logic       full;

  assign con_empty = (wptr == rptr);
  assign full      = (wptr[7:0] == rptr[7:0]) && (wptr[8] != rptr[8]);
  assign con_data  = fifo[rptr[7:0]];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wptr <= '0;
      rptr <= '0;
    end else begin
      if (console_valid && !full) wptr <= wptr + 9'd1;
      if (con_pop && !con_empty)  rptr <= rptr + 9'd1;
    end
  end

  always_ff @(posedge clk) begin
    if (console_valid && !full) fifo[wptr[7:0]] <= console_byte;
  end

endmodule
