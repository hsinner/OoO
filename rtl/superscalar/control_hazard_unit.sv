// Conservative singleton controller. No prediction or selective age recovery.
// DP may dispatch a serialized instruction only on serial_valid && serial_ready.
// backend_empty must include EX/MEM/WB/C and outstanding architectural data work.
// Commit supplies trap/branch requests, holding valid + PC until ready. Branch
// requests include the resolved next PC for BOTH taken and not-taken outcomes.
// trap_pc_i is the EEI-provided restart/handler PC, NOT the faulting instruction PC.
// Trap wins simultaneous requests; commit must cancel the losing younger branch.
// While a redirect is pending, new events wait: redirect payload never changes.
module control_hazard_unit (
  input logic clk_i, rst_i,
  input logic serial_valid_i, backend_empty_i,
  output logic serial_ready_o,
  input logic serial_done_i, // Successful non-control singleton commit pulse.
  input logic branch_valid_i,
  input logic [31:0] branch_pc_i,
  output logic branch_ready_o,
  input logic trap_valid_i,
  input logic [31:0] trap_pc_i,
  output logic trap_ready_o,
  output logic redirect_valid_o,
  output logic [31:0] redirect_pc_o,
  input logic redirect_ready_i, // IF has accepted ownership, including stale drain.
  output logic block_younger_o, stop_fetch_o,
  output logic flush_frontend_o, flush_backend_o
);
  typedef struct packed {
    logic serial_busy;
    logic redirect_valid;
    logic [31:0] redirect_pc;
  } state_t;
  state_t state_q, state_d;
  logic start_fire, branch_fire, trap_fire;
  always_comb begin
    state_d = state_q;
    trap_ready_o = !rst_i && !state_q.redirect_valid;
    branch_ready_o = trap_ready_o && !trap_valid_i;
    trap_fire = trap_valid_i && trap_ready_o;
    branch_fire = branch_valid_i && branch_ready_o;
    serial_ready_o = !rst_i && backend_empty_i && !state_q.serial_busy &&
                     !state_q.redirect_valid && !branch_valid_i && !trap_valid_i;
    start_fire = serial_valid_i && serial_ready_o;
    redirect_valid_o = state_q.redirect_valid && !rst_i;
    redirect_pc_o = state_q.redirect_pc;
    // These are same-cycle cancellation controls, sampled at the accepting edge.
    flush_frontend_o = trap_fire || branch_fire;
    flush_backend_o = trap_fire; // Commit already retired all older effects.
    block_younger_o = rst_i || state_q.serial_busy || state_q.redirect_valid ||
                      start_fire || branch_valid_i || trap_valid_i;
    stop_fetch_o = block_younger_o;
    if (serial_done_i) state_d.serial_busy = 1'b0;
    if (redirect_valid_o && redirect_ready_i) begin
      state_d.redirect_valid = 1'b0;
      state_d.serial_busy = 1'b0;
    end
    if (start_fire) state_d.serial_busy = 1'b1;
    if (trap_fire || branch_fire) begin
      state_d.serial_busy = 1'b1;
      state_d.redirect_valid = 1'b1;
      state_d.redirect_pc = trap_fire ? trap_pc_i : branch_pc_i;
    end
    if (rst_i) state_d = '0;
  end
  always_ff @(posedge clk_i) begin
    state_q <= state_d;
  end
endmodule
