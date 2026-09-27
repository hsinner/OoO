// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO TOP-01: Wire IF/D/R/DP/EX/MEM/WB/C, RF, scoreboard, adapter and recovery.
// TODO TOP-02: Pack producer ports youngest first: EX[3..0], MEM[3..0], WB[3..0], C[3..0].
// TODO TOP-03: Broadcast accepted commit writes to RF, scoreboard, R and DP.
// TODO TOP-04: backend_empty = no EX/MEM/WB/C owner and memory_adapter idle.
// TODO TOP-05: Frontend flush covers IF/D/R/DP; backend trap flush covers EX/MEM/WB and scoreboard.
// TODO TOP-06: C and committed RF are NOT indiscriminately reset on a branch redirect.
// TODO TOP-07: Prove packet-stage ownership, singleton handshake, no ready/data loops and no extra stages.
// TODO TOP-08: Keep all top outputs deliberately undriven until actual submodules are wired.
module core (
  input logic clk_i, rst_i,
  input rv32_pkg::word_t reset_pc_i,
  output logic instruction_request_valid_o,
  output rv32_pkg::word_t instruction_request_address_o,
  input logic instruction_request_ready_i,
  input logic instruction_response_valid_i,
  input rv32_pkg::if_response_t instruction_response_i,
  output logic instruction_response_ready_o,
  output logic data_request_valid_o,
  output rv32_pkg::mem_request_t data_request_o,
  input logic data_request_ready_i,
  input logic data_response_valid_i,
  input rv32_pkg::mem_response_t data_response_i,
  output logic data_response_ready_o,
  output rv32_pkg::retire_bundle_t retire_o,
  output logic trap_valid_o,
  output rv32_pkg::trap_t trap_o,
  input logic trap_ready_i,
  input logic resume_valid_i,
  input rv32_pkg::word_t resume_pc_i,
  output logic resume_ready_o
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
