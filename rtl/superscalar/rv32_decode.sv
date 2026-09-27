// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO DEC-01: Decode all 40 RV32I instructions; validate opcode/funct fields.
// TODO DEC-02: Build immediates, source-use flags and serial classification.
// TODO DEC-03: Record symbolic illegal fault; never silently substitute ADD.
module rv32_decode (
  input rv32_pkg::word_t instruction_i,
  output rv32_pkg::decoded_t decoded_o
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
