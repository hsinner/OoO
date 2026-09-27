// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO SB-01: Set bits only on accepted dispatch; clear only accepted commit writes.
// TODO SB-02: Keep bit zero clear. Allocation wins same-bit clear if reuse is enabled.
// TODO SB-03: flush means ALL remaining writers are killed after older effects settle.
// TODO SB-04: Assert at most one live writer per nonzero register; forwarding never clears busy.
// TODO STATE: 32-bit busy bitmap.
module scoreboard (
  input logic clk_i, rst_i, flush_i,
  input logic [31:0] allocate_mask_i,
  input rv32_pkg::commit_writes_t commit_writes_i,
  output logic [31:0] busy_o
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
