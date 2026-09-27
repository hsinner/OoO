// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO BUS-01: Route serialized MEM loads and C stores to one abstract data port.
// TODO BUS-02: Track owner through response consumption; never route response to new owner.
// TODO BUS-03: Assert loads/stores do not compete under serialization; document arbitration defensively.
// TODO BUS-04: idle means no offered/accepted/buffered data transaction remains, not just bus-ready.
// TODO BUS-05: Failed store has no visible effects; ack meets EEI ordering. No silent posted-write model.
// TODO STATE: request owner, request/response holding, acceptance state. Reset coordinated with endpoint.
// TODO This is an abstract bridge, NOT an unfinished AXI implementation with invented signals.
module memory_adapter (
  input logic clk_i, rst_i,
  input logic load_request_valid_i,
  input rv32_pkg::mem_request_t load_request_i,
  output logic load_request_ready_o,
  output logic load_response_valid_o,
  output rv32_pkg::mem_response_t load_response_o,
  input logic load_response_ready_i,
  input logic store_request_valid_i,
  input rv32_pkg::mem_request_t store_request_i,
  output logic store_request_ready_o,
  output logic store_response_valid_o,
  output rv32_pkg::mem_response_t store_response_o,
  input logic store_response_ready_i,
  output logic request_valid_o,
  output rv32_pkg::mem_request_t request_o,
  input logic request_ready_i,
  input logic response_valid_i,
  input rv32_pkg::mem_response_t response_i,
  output logic response_ready_o,
  output logic idle_o
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
