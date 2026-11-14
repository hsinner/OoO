// Serialized load completion and formatting; stores remain descriptors until C.
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
  typedef struct packed { packet_t packet; logic valid,sent,done; } state_t;
  state_t q,d;
  logic load_pending;
  word_t shifted;
  always_comb begin
    for (int i=0; i<4; i++)
      producers_o[i]=make_producer(q.packet[i],q.valid && !rst_i && !flush_i,!load_pending);
  end
  always_comb begin
    load_pending=q.valid && is_load(q.packet[0].decoded.op) && !q.packet[0].fault.valid && !q.done;
  end
  always_comb begin
    shifted=load_response_i.read_data >> {q.packet[0].address[1:0],3'b0};
  end
  always_comb begin
    packet_valid_o=q.valid && !load_pending && !rst_i && !flush_i;
  end
  always_comb begin
    packet_o=q.packet;
  end
  always_comb begin
    packet_ready_o=(!q.valid || (packet_valid_o && packet_ready_i)) && !rst_i && !flush_i;
  end
  always_comb begin
    occupied_o=q.valid;
  end
  always_comb begin
    load_request_valid_o=load_pending && !q.sent && !rst_i && !flush_i;
  end
  always_comb begin
    load_request_o='{write:0,aligned_address:{q.packet[0].address[31:2],2'b0},
                     write_data:32'b0,byte_mask:q.packet[0].byte_mask};
  end
  always_comb begin
    load_response_ready_o=load_pending && q.sent && !rst_i;
  end
  always_comb begin
    d=q;

    if (load_request_valid_o && load_request_ready_i) d.sent=1;
    if (load_response_valid_i && load_response_ready_o) begin
      d.done=1;
      d.packet[0].result=shifted;
      case (q.packet[0].decoded.op)
        OP_LB: d.packet[0].result={{24{shifted[7]}},shifted[7:0]};
        OP_LBU: d.packet[0].result={24'b0,shifted[7:0]};
        OP_LH: d.packet[0].result={{16{shifted[15]}},shifted[15:0]};
        OP_LHU: d.packet[0].result={16'b0,shifted[15:0]};
        default: begin end
      endcase
      if (load_response_i.error)
        d.packet[0].fault='{valid:1,kind:FAULT_LOAD_ACCESS,address:q.packet[0].address};
    end

    if (packet_ready_o) begin
      d.valid=packet_valid_i;
      d.sent=0; d.done=0;
      if (packet_valid_i) d.packet=packet_i;
    end
    // Integration only flushes after older data ownership has settled.
    if (rst_i || flush_i) d='0;
  end
  always_ff @(posedge clk_i) begin
    q <= d;
  end
endmodule
