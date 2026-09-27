// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO DP-01: Own remaining packet suffix and operand snapshots; refresh on every commit.
// TODO DP-02: Instantiate forwarding_unit; sources = 2*lane + operand (rs1=0, rs2=1).
// TODO DP-03: Select oldest executable prefix; enforce source readiness, WAW and same-packet RAW.
// TODO DP-04: Freeze offered bundle under EX backpressure; no duplicate dispatch after compaction.
// TODO DP-05: Atomic singleton transfer requires serial_ready AND EX acceptance; avoid combinational loop
// TODO        with block_younger (which rises on serial handshake); it gates ordinary lanes only.
// TODO DP-06: allocate_mask pulses on actual EX transfer; do not allocate for a held offer.
// TODO STATE: retained suffix, snapshots and frozen offered prefix/values; no rename tags.
module dispatch (
  input logic clk_i, rst_i, flush_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  input rv32_pkg::read_values_t live_operands_i,
  output logic packet_ready_o,
  input rv32_pkg::commit_writes_t commit_writes_i,
  input logic [31:0] busy_i,
  input hazard_pkg::producer_t [hazard_pkg::PRODUCERS-1:0] producers_i,
  input logic block_younger_i,
  output logic serial_valid_o,
  input logic serial_ready_i,
  output logic [31:0] allocate_mask_o,
  output logic packet_valid_o,
  output rv32_pkg::packet_t packet_o,
  input logic packet_ready_i
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
