// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO C-01: Retire oldest legal prefix; commit_writes and passive trace occur exactly once.
// TODO C-02: Hold trap report stable until recovery accepts it; no faulting/younger retirement.
// TODO C-03: Branch link write/retirement and branch handshake are one atomic accepted event.
// TODO C-04: Issue authorized store once, hold until response, then retire or report error.
// TODO C-05: serial_done only on successful non-control serial completion; fence requires memory idle.
// TODO C-06: Trap report acceptance retires NO faulting instruction; clear its C ownership only after
// TODO       recovery owns the report. Recovery still blocks all younger work until resume.
// TODO STATE: current packet/cursor; store-sent/response ownership; trap/branch event holding.
// TODO No external flush port: this is the architectural ordering owner, not a younger stage.
module commit (
  input logic clk_i, rst_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  output logic packet_ready_o,
  output rv32_pkg::commit_writes_t commit_writes_o,
  output rv32_pkg::retire_bundle_t retire_o,
  output logic trap_valid_o,
  output rv32_pkg::trap_t trap_o,
  input logic trap_ready_i,
  output logic branch_valid_o,
  output rv32_pkg::word_t branch_pc_o,
  input logic branch_ready_i,
  output logic serial_done_o,
  output logic store_request_valid_o,
  output rv32_pkg::mem_request_t store_request_o,
  input logic store_request_ready_i,
  input logic store_response_valid_i,
  input rv32_pkg::mem_response_t store_response_i,
  output logic store_response_ready_o,
  input logic memory_idle_i,
  output hazard_pkg::producer_t [3:0] producers_o,
  output logic occupied_o
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
