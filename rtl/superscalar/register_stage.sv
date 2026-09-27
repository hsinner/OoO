// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO R-01: Hold a stable index/control packet and continuously read its RF indices.
// TODO R-02: live_operands is a separate changing sideband sampled only on R-to-DP acceptance.
// TODO R-03: Bypass simultaneous accepted commit writes into live reads; x0 always zero.
// TODO R-04: packet_o src1/src2 are not authoritative; dispatch samples live_operands instead.
// TODO STATE: ordered control packet and valid; no early register writes.
module register_stage (
  input logic clk_i, rst_i, flush_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  output logic packet_ready_o,
  output rv32_pkg::read_indices_t read_indices_o,
  input rv32_pkg::read_values_t read_values_i,
  input rv32_pkg::commit_writes_t commit_writes_i,
  output logic packet_valid_o,
  output rv32_pkg::packet_t packet_o,
  output rv32_pkg::read_values_t live_operands_o,
  input logic packet_ready_i
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
