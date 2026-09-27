// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO ALU-01: Implement integer data operations only; no memory or control effects.
// TODO ALU-02: Specify signed comparisons/right shifts and low-five-bit shift amount.
// TODO ALU-03: Immediate/PC operand selection belongs to execute, not this block.
module alu (
  input rv32_pkg::op_t op_i,
  input rv32_pkg::word_t a_i, b_i,
  output rv32_pkg::word_t result_o
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
