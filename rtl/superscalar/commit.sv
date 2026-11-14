// Ordered architectural effects. Store, branch and trap events retain ownership.
module commit (
  input logic clk_i, rst_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  output logic packet_ready_o,
  output rv32_pkg::commit_writes_t commit_writes_o,
  output rv32_pkg::retire_bundle_t retire_o,
  output logic trap_valid_o,
  output rv32_pkg::trap_t trap_o,
  input logic trap_ready_i,
  output logic branch_valid_o,
  output rv32_pkg::word_t branch_pc_o,
  input logic branch_ready_i,
  output logic serial_done_o,
  output logic store_request_valid_o,
  output rv32_pkg::mem_request_t store_request_o,
  input logic store_request_ready_i,
  input logic store_response_valid_i,
  input rv32_pkg::mem_response_t store_response_i,
  output logic store_response_ready_o,
  input logic memory_idle_i,
  output hazard_pkg::producer_t [3:0] producers_o,
  output logic occupied_o
);
  import rv32_pkg::*;
  typedef struct packed { packet_t packet; logic valid,sent,done; } state_t;
  state_t q,d;
  logic stop,retire_lane;
  int count;
  logic [31:0] unused_store_read_data;
  always_comb begin
    for (int i=0; i<4; i++) producers_o[i]=make_producer(q.packet[i],q.valid && !rst_i,1'b1);
  end
  always_comb begin
    occupied_o=q.valid;
  end
  always_comb begin
    // Deliberate bubble between commit packets.
    packet_ready_o=!q.valid && !rst_i;
  end
  always_comb begin
    store_request_o='{write:1,aligned_address:{q.packet[0].address[31:2],2'b0},
                      write_data:q.packet[0].store_data,byte_mask:q.packet[0].byte_mask};
  end
  always_comb begin
    store_response_ready_o=q.valid && q.sent && !q.done && !rst_i;
  end
  always_comb begin
    unused_store_read_data=store_response_i.read_data;
    trap_valid_o=q.valid && q.packet[0].valid && q.packet[0].fault.valid && !rst_i;
    trap_o='{pc:q.packet[0].pc,instruction:q.packet[0].instruction,fault:q.packet[0].fault};
    branch_valid_o=q.valid && q.packet[0].valid && !q.packet[0].fault.valid && is_control(q.packet[0].decoded.op) && !rst_i;
    branch_pc_o=q.packet[0].next_pc;
    store_request_valid_o=q.valid && q.packet[0].valid && !q.packet[0].fault.valid && is_store(q.packet[0].decoded.op) && !q.sent && !rst_i;
  end
  always_comb begin
    d=q;

    commit_writes_o='0; retire_o='0;

    serial_done_o=0;

    if (store_response_valid_i && store_response_ready_o) begin
      d.done=1;
      if (store_response_i.error)
        d.packet[0].fault='{valid:1,kind:FAULT_STORE_ACCESS,address:q.packet[0].address};
    end
    stop=!q.valid || rst_i;
    count=0;
    retire_lane=0;
    for (int i=0; i<4; i++) begin

      retire_lane=0;
      if (!q.packet[i].valid) stop=1;
      if (!stop) begin
        if (q.packet[i].fault.valid) begin
          // First retire any older prefix. Present a stable trap only at lane 0.
          if (i==0) begin

            if (trap_ready_i) d='0;
          end
          stop=1;
        end else if (is_control(q.packet[i].decoded.op)) begin
          if (i==0) begin retire_lane=branch_ready_i; end
          stop=1;
        end else if (is_store(q.packet[i].decoded.op)) begin
          if (i==0) begin

            if (store_request_valid_o && store_request_ready_i) d.sent=1;
            retire_lane=q.done;
          end
          stop=1;
        end else if (q.packet[i].decoded.op==OP_FENCE) begin
          retire_lane=memory_idle_i;
          stop=1;
        end else retire_lane=1;
        if (retire_lane) begin
          count++;
          commit_writes_o[i]='{valid:q.packet[i].decoded.writes_rd,
                               rd:q.packet[i].decoded.rd,value:q.packet[i].result};
          retire_o[i]='{valid:1,pc:q.packet[i].pc,instruction:q.packet[i].instruction,
            writes_rd:q.packet[i].decoded.writes_rd,rd:q.packet[i].decoded.rd,value:q.packet[i].result,
            memory:is_load(q.packet[i].decoded.op)||is_store(q.packet[i].decoded.op),
            memory_write:is_store(q.packet[i].decoded.op),address:q.packet[i].address,
            memory_data:is_store(q.packet[i].decoded.op)?q.packet[i].store_data:q.packet[i].result,
            byte_mask:q.packet[i].byte_mask};
          if (q.packet[i].decoded.serial && !is_control(q.packet[i].decoded.op)) serial_done_o=1;
        end
      end
    end
    if (count!=0) begin
      d.packet='0; d.sent=0; d.done=0;
      for (int i=0; i<4; i++) if (i+count<4) d.packet[i]=q.packet[i+count];
      d.valid=d.packet[0].valid;
    end
    if (packet_valid_i && packet_ready_o) begin d='0; d.valid=1; d.packet=packet_i; end
    if (rst_i) d='0;
  end
  always_ff @(posedge clk_i) begin
    q <= d;
  end
endmodule
