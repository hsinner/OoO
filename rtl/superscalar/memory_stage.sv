// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO MEM-01: Pass ALU results in order; issue a singleton load exactly once and wait for response.
// TODO MEM-02: Extract little-endian bytes and sign/zero extend; preserve original fault address.
// TODO MEM-03: Package stores only, never issue them; commit owns store requests.
// TODO MEM-04: A load is a live unready producer until actual data arrives; fault blocks forwarding.
// TODO MEM-05: Coordinate flush with adapter ownership; accepted external requests still need draining.
// TODO STATE: resident packet; request-sent flag; load response/result holding.
module memory_stage (
  input logic clk_i, rst_i, flush_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  output logic packet_ready_o,
  output logic load_request_valid_o,
  output rv32_pkg::mem_request_t load_request_o,
  input logic load_request_ready_i,
  input logic load_response_valid_i,
  input rv32_pkg::mem_response_t load_response_i,
  output logic load_response_ready_o,
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
