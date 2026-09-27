// UNIMPLEMENTED SKELETON: interface contract only; outputs intentionally undriven.
// See docs/superscalar/skeleton.md. This file must not be used as working RTL.
// No tie-offs, behavioral substitutes, or inferred test results are provided.
// TODO REC-01: Instantiate existing control_hazard_unit; translate accepted commit trap to EEI report.
// TODO REC-02: Retain trap metadata across EEI stalls; wait for report acceptance before accepting resume.
// TODO REC-03: Gate younger work throughout trap-report/resume wait, even after C releases its packet.
// TODO REC-04: resume PC becomes controller trap_pc; never substitute faulting PC or invented vector.
// TODO REC-05: Flush only after older effects settle; trap wins branch and losing branch is canceled.
// TODO STATE: trap report holding; report-accepted/wait-resume; controller pending redirect state.
module recovery (
  input logic clk_i, rst_i,
  input logic serial_valid_i, backend_empty_i,
  output logic serial_ready_o,
  input logic serial_done_i,
  input logic branch_valid_i,
  input rv32_pkg::word_t branch_pc_i,
  output logic branch_ready_o,
  input logic commit_trap_valid_i,
  input rv32_pkg::trap_t commit_trap_i,
  output logic commit_trap_ready_o,
  output logic eei_trap_valid_o,
  output rv32_pkg::trap_t eei_trap_o,
  input logic eei_trap_ready_i,
  input logic resume_valid_i,
  input rv32_pkg::word_t resume_pc_i,
  output logic resume_ready_o,
  output logic redirect_valid_o,
  output rv32_pkg::word_t redirect_pc_o,
  input logic redirect_ready_i,
  output logic block_younger_o, stop_fetch_o,
  output logic flush_frontend_o, flush_backend_o
);
  import rv32_pkg::*;
  // TODO Declare module-specific state_q/state_d, if this block owns state.
  // TODO Implement next-state/defaults/reset/flush in always_comb.
  // TODO Use always_ff only for nonblocking state assignments.
  // TODO Add meaningful directed tests before declaring this block complete.
endmodule
