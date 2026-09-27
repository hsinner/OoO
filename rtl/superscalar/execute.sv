// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO EX-01: Four ALUs; select register/immediate/PC operands and compute results.
// TODO EX-02: Singleton address/branch path computes target/link/effective address, not side effects.
// TODO EX-03: Check taken-target alignment and data alignment; retain earlier faults.
// TODO EX-04: producers_o[lane] describes resident operation; never mark a load address as ready data.
// TODO EX-05: Define the resident EX packet and its combinational result path exactly once; no extra
// TODO        hidden ninth stage or dependence on new DP selection to validate current EX results.
// TODO STATE: resident EX packet; output valid/data hold across downstream backpressure.
module execute (
  input logic clk_i, rst_i, flush_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  output logic packet_ready_o,
  output logic packet_valid_o,
  output rv32_pkg::packet_t packet_o,
  input logic packet_ready_i,
  output hazard_pkg::producer_t [3:0] producers_o,
  output logic occupied_o
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
