// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO IF-01: Own PC, aligned block request, response buffer and next-word offset.
// TODO IF-02: Hold accepted request ownership; drain stale responses after redirect.
// TODO IF-03: stop_fetch blocks new sequential requests, not response/redirect acceptance.
// TODO IF-04: Emit compact prefixes with per-word PCs and access faults; reset PC is sampled on reset.
// TODO STATE: PC; request accepted/pending; buffered response; discard-on-return; pending redirect.
module fetch (
  input logic clk_i, rst_i,
  input rv32_pkg::word_t reset_pc_i,
  input logic stop_fetch_i, flush_i,
  input logic redirect_valid_i,
  input rv32_pkg::word_t redirect_pc_i,
  output logic redirect_ready_o,
  output logic request_valid_o,
  output rv32_pkg::word_t request_address_o,
  input logic request_ready_i,
  input logic response_valid_i,
  input rv32_pkg::if_response_t response_i,
  output logic response_ready_o,
  output logic packet_valid_o,
  output rv32_pkg::packet_t packet_o,
  input logic packet_ready_i,
  output logic outstanding_o
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
