// hazard_unit.sv
// Forwarding selects for EX and the load-use interlock for ID.
//
// Forwarding sources, newest first:
//   EX/MEM : instruction now in MEM, only if its result was produced in EX
//            (ALU, PC+4, DIV). Loads, MUL and CSR reads finish in MEM.
//   MEM/WB : instruction now in WB, any result.
// The WB -> ID case is handled inside the register file (write-through read).
//
// Interlock: if the instruction in EX produces a late result (load, MUL, CSR)
// and the instruction in ID reads it, ID/IF hold for one cycle and a bubble is
// inserted into EX. Writes to x0 are never forwarded or interlocked on, because
// decode clears rd_we for rd = x0.

module hazard_unit
  import core_pkg::*;
(
  // ID
  input  logic [4:0]  id_rs1,
  input  logic [4:0]  id_rs2,
  input  logic        id_rs1_used,
  input  logic        id_rs2_used,

  // EX
  input  logic        ex_valid,
  input  logic [4:0]  ex_rs1,
  input  logic [4:0]  ex_rs2,
  input  logic [4:0]  ex_rd,
  input  logic        ex_rd_we,
  input  res_sel_e    ex_res_sel,

  // MEM
  input  logic        mem_valid,
  input  logic [4:0]  mem_rd,
  input  logic        mem_rd_we,
  input  res_sel_e    mem_res_sel,

  // WB
  input  logic        wb_rd_we,
  input  logic [4:0]  wb_rd,

  output fwd_sel_e    fwd_a,
  output fwd_sel_e    fwd_b,
  output logic        load_use,       // interlock caused by a load or CSR read
  output logic        mul_use         // interlock caused by a MUL
);

  logic mem_fwd_ok;
  assign mem_fwd_ok = mem_valid && mem_rd_we && !res_is_late(mem_res_sel);

  always_comb begin
    fwd_a = FWD_NONE;
    if (mem_fwd_ok && mem_rd == ex_rs1)  fwd_a = FWD_EXMEM;
    else if (wb_rd_we && wb_rd == ex_rs1) fwd_a = FWD_MEMWB;

    fwd_b = FWD_NONE;
    if (mem_fwd_ok && mem_rd == ex_rs2)  fwd_b = FWD_EXMEM;
    else if (wb_rd_we && wb_rd == ex_rs2) fwd_b = FWD_MEMWB;
  end

  logic dep;
  assign dep = ex_valid && ex_rd_we && res_is_late(ex_res_sel) &&
               ((id_rs1_used && id_rs1 == ex_rd) || (id_rs2_used && id_rs2 == ex_rd));

  assign load_use = dep && (ex_res_sel != RES_MUL);
  assign mul_use  = dep && (ex_res_sel == RES_MUL);

endmodule
