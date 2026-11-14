// Trap report and resume ownership around the tested singleton/redirect controller.
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
  typedef enum logic [1:0] {IDLE,REPORT,RESUME,REDIRECT} phase_t;
  typedef struct packed { phase_t phase; trap_t trap; } state_t;
  state_t q,d;
  logic ctrl_serial_ready,ctrl_branch_ready,ctrl_trap_ready;
  logic ctrl_block,ctrl_stop,ctrl_front,ctrl_back;
  logic trap_start, resume_offer;
  always_comb begin
    commit_trap_ready_o=q.phase==IDLE && !rst_i;
  end
  always_comb begin
    trap_start=commit_trap_valid_i && commit_trap_ready_o;
  end
  always_comb begin
    resume_offer=q.phase==RESUME && resume_valid_i;
  end
  always_comb begin
    serial_ready_o=ctrl_serial_ready && q.phase==IDLE && !commit_trap_valid_i;
  end
  always_comb begin
    branch_ready_o=ctrl_branch_ready && q.phase==IDLE && !commit_trap_valid_i;
  end
  always_comb begin
    eei_trap_valid_o=q.phase==REPORT && !rst_i;
  end
  always_comb begin
    eei_trap_o=q.trap;
  end
  always_comb begin
    resume_ready_o=q.phase==RESUME && ctrl_trap_ready && !rst_i;
  end
  always_comb begin
    block_younger_o=ctrl_block || q.phase!=IDLE || commit_trap_valid_i;
  end
  always_comb begin
    stop_fetch_o=ctrl_stop || q.phase!=IDLE || commit_trap_valid_i;
  end
  always_comb begin
    flush_frontend_o=ctrl_front || trap_start;
  end
  always_comb begin
    flush_backend_o=ctrl_back || trap_start;
  end
  always_comb begin

    d=q;
    if (trap_start) begin d.phase=REPORT; d.trap=commit_trap_i; end
    if (eei_trap_valid_o && eei_trap_ready_i) d.phase=RESUME;
    if (resume_valid_i && resume_ready_o) d.phase=REDIRECT;
    if (q.phase==REDIRECT && redirect_valid_o && redirect_ready_i) d.phase=IDLE;
    if (rst_i) d='0;
  end
  control_hazard_unit u_control (
    .clk_i(clk_i),.rst_i(rst_i),
    .serial_valid_i(serial_valid_i && q.phase==IDLE && !commit_trap_valid_i),
    .backend_empty_i(backend_empty_i),.serial_ready_o(ctrl_serial_ready),.serial_done_i(serial_done_i),
    .branch_valid_i(branch_valid_i && q.phase==IDLE && !commit_trap_valid_i),
    .branch_pc_i(branch_pc_i),.branch_ready_o(ctrl_branch_ready),
    .trap_valid_i(resume_offer),.trap_pc_i(resume_pc_i),.trap_ready_o(ctrl_trap_ready),
    .redirect_valid_o(redirect_valid_o),.redirect_pc_o(redirect_pc_o),.redirect_ready_i(redirect_ready_i),
    .block_younger_o(ctrl_block),.stop_fetch_o(ctrl_stop),
    .flush_frontend_o(ctrl_front),.flush_backend_o(ctrl_back));
  always_ff @(posedge clk_i) begin
    q <= d;
  end
endmodule
