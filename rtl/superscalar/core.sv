// Eight-stage four-wide in-order RV32I core; abstract memory and EEI ports.
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
  packet_t packets [7];
  logic valid [7], ready [7];
  logic stop_fetch,front_flush,back_flush,redirect_valid,redirect_ready;
  word_t redirect_pc;
  logic unused_fetch_outstanding;
  read_indices_t read_indices;
  read_values_t read_values,live_operands;
  commit_writes_t writes;
  logic [31:0] busy,allocate;
  logic [3:0] occupied;
  hazard_pkg::producer_t [3:0] stage_producers [4];
  hazard_pkg::producer_t [15:0] producers;
  logic serial_valid,serial_ready,serial_done,block_younger;
  logic branch_valid,branch_ready,commit_trap_valid,commit_trap_ready;
  word_t branch_pc;
  trap_t commit_trap;
  logic load_req_valid,load_req_ready,load_rsp_valid,load_rsp_ready;
  logic store_req_valid,store_req_ready,store_rsp_valid,store_rsp_ready,memory_idle;
  mem_request_t load_req,store_req;
  mem_response_t load_rsp,store_rsp;
  always_comb begin
    for (int stage=0; stage<4; stage++)
      for (int lane=0; lane<4; lane++)
        producers[4*stage+lane]=stage_producers[stage][3-lane];
  end
  fetch u_fetch (.clk_i(clk_i),.rst_i(rst_i),.reset_pc_i(reset_pc_i),
    .stop_fetch_i(stop_fetch),.flush_i(front_flush),.redirect_valid_i(redirect_valid),
    .redirect_pc_i(redirect_pc),.redirect_ready_o(redirect_ready),
    .request_valid_o(instruction_request_valid_o),.request_address_o(instruction_request_address_o),
    .request_ready_i(instruction_request_ready_i),.response_valid_i(instruction_response_valid_i),
    .response_i(instruction_response_i),.response_ready_o(instruction_response_ready_o),
    .packet_valid_o(valid[0]),.packet_o(packets[0]),.packet_ready_i(ready[0]),
    .outstanding_o(unused_fetch_outstanding));
  decode_stage u_decode (.clk_i(clk_i),.rst_i(rst_i),.flush_i(front_flush),
    .packet_valid_i(valid[0]),.packet_i(packets[0]),.packet_ready_o(ready[0]),
    .packet_valid_o(valid[1]),.packet_o(packets[1]),.packet_ready_i(ready[1]));
  regfile u_regfile (.clk_i(clk_i),.rst_i(rst_i),.read_indices_i(read_indices),
    .read_values_o(read_values),.commit_writes_i(writes));
  register_stage u_register (.clk_i(clk_i),.rst_i(rst_i),.flush_i(front_flush),
    .packet_valid_i(valid[1]),.packet_i(packets[1]),.packet_ready_o(ready[1]),
    .read_indices_o(read_indices),.read_values_i(read_values),.commit_writes_i(writes),
    .packet_valid_o(valid[2]),.packet_o(packets[2]),.live_operands_o(live_operands),.packet_ready_i(ready[2]));
  scoreboard u_scoreboard (.clk_i(clk_i),.rst_i(rst_i),.flush_i(back_flush),
    .allocate_mask_i(allocate),.commit_writes_i(writes),.busy_o(busy));
  dispatch u_dispatch (.clk_i(clk_i),.rst_i(rst_i),.flush_i(front_flush),
    .packet_valid_i(valid[2]),.packet_i(packets[2]),.live_operands_i(live_operands),
    .packet_ready_o(ready[2]),.commit_writes_i(writes),.busy_i(busy),.producers_i(producers),
    .block_younger_i(block_younger),.serial_valid_o(serial_valid),.serial_ready_i(serial_ready),
    .allocate_mask_o(allocate),.packet_valid_o(valid[3]),.packet_o(packets[3]),.packet_ready_i(ready[3]));
  execute u_execute (.clk_i(clk_i),.rst_i(rst_i),.flush_i(back_flush),
    .packet_valid_i(valid[3]),.packet_i(packets[3]),.packet_ready_o(ready[3]),
    .packet_valid_o(valid[4]),.packet_o(packets[4]),.packet_ready_i(ready[4]),
    .producers_o(stage_producers[0]),.occupied_o(occupied[0]));
  memory_stage u_memory (.clk_i(clk_i),.rst_i(rst_i),.flush_i(back_flush),
    .packet_valid_i(valid[4]),.packet_i(packets[4]),.packet_ready_o(ready[4]),
    .load_request_valid_o(load_req_valid),.load_request_o(load_req),.load_request_ready_i(load_req_ready),
    .load_response_valid_i(load_rsp_valid),.load_response_i(load_rsp),.load_response_ready_o(load_rsp_ready),
    .packet_valid_o(valid[5]),.packet_o(packets[5]),.packet_ready_i(ready[5]),
    .producers_o(stage_producers[1]),.occupied_o(occupied[1]));
  writeback u_writeback (.clk_i(clk_i),.rst_i(rst_i),.flush_i(back_flush),
    .packet_valid_i(valid[5]),.packet_i(packets[5]),.packet_ready_o(ready[5]),
    .packet_valid_o(valid[6]),.packet_o(packets[6]),.packet_ready_i(ready[6]),
    .producers_o(stage_producers[2]),.occupied_o(occupied[2]));
  commit u_commit (.clk_i(clk_i),.rst_i(rst_i),
    .packet_valid_i(valid[6]),.packet_i(packets[6]),.packet_ready_o(ready[6]),
    .commit_writes_o(writes),.retire_o(retire_o),.trap_valid_o(commit_trap_valid),
    .trap_o(commit_trap),.trap_ready_i(commit_trap_ready),.branch_valid_o(branch_valid),
    .branch_pc_o(branch_pc),.branch_ready_i(branch_ready),.serial_done_o(serial_done),
    .store_request_valid_o(store_req_valid),.store_request_o(store_req),.store_request_ready_i(store_req_ready),
    .store_response_valid_i(store_rsp_valid),.store_response_i(store_rsp),.store_response_ready_o(store_rsp_ready),
    .memory_idle_i(memory_idle),.producers_o(stage_producers[3]),.occupied_o(occupied[3]));
  memory_adapter u_adapter (.clk_i(clk_i),.rst_i(rst_i),
    .load_request_valid_i(load_req_valid),.load_request_i(load_req),.load_request_ready_o(load_req_ready),
    .load_response_valid_o(load_rsp_valid),.load_response_o(load_rsp),.load_response_ready_i(load_rsp_ready),
    .store_request_valid_i(store_req_valid),.store_request_i(store_req),.store_request_ready_o(store_req_ready),
    .store_response_valid_o(store_rsp_valid),.store_response_o(store_rsp),.store_response_ready_i(store_rsp_ready),
    .request_valid_o(data_request_valid_o),.request_o(data_request_o),.request_ready_i(data_request_ready_i),
    .response_valid_i(data_response_valid_i),.response_i(data_response_i),.response_ready_o(data_response_ready_o),
    .idle_o(memory_idle));
  recovery u_recovery (.clk_i(clk_i),.rst_i(rst_i),.serial_valid_i(serial_valid),
    .backend_empty_i(occupied=='0 && memory_idle),.serial_ready_o(serial_ready),.serial_done_i(serial_done),
    .branch_valid_i(branch_valid),.branch_pc_i(branch_pc),.branch_ready_o(branch_ready),
    .commit_trap_valid_i(commit_trap_valid),.commit_trap_i(commit_trap),.commit_trap_ready_o(commit_trap_ready),
    .eei_trap_valid_o(trap_valid_o),.eei_trap_o(trap_o),.eei_trap_ready_i(trap_ready_i),
    .resume_valid_i(resume_valid_i),.resume_pc_i(resume_pc_i),.resume_ready_o(resume_ready_o),
    .redirect_valid_o(redirect_valid),.redirect_pc_o(redirect_pc),.redirect_ready_i(redirect_ready),
    .block_younger_o(block_younger),.stop_fetch_o(stop_fetch),
    .flush_frontend_o(front_flush),.flush_backend_o(back_flush));
endmodule
