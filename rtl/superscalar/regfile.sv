// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO RF-01: Provide eight combinational reads and four accepted commit writes.
// TODO RF-02: x0 reads zero and ignores writes; choose/reset all other registers explicitly.
// TODO RF-03: Define simultaneous read/write behavior with explicit commit bypass at R/DP.
// TODO RF-04: Assert no two accepted nonzero writes target the same rd under one-writer policy.
// TODO STATE: committed registers only; no flush input because committed state survives recovery.
module regfile (
  input logic clk_i, rst_i,
  input rv32_pkg::read_indices_t read_indices_i,
  output rv32_pkg::read_values_t read_values_o,
  input rv32_pkg::commit_writes_t commit_writes_i
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
