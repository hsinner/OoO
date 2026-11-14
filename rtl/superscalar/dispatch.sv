// Oldest-prefix in-order dispatch with retained suffix and frozen stalled offer.
module dispatch (
  input logic clk_i, rst_i, flush_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  input rv32_pkg::read_values_t live_operands_i,
  output logic packet_ready_o,
  input rv32_pkg::commit_writes_t commit_writes_i,
  input logic [31:0] busy_i,
  input hazard_pkg::producer_t [hazard_pkg::PRODUCERS-1:0] producers_i,
  input logic block_younger_i,
  output logic serial_valid_o,
  input logic serial_ready_i,
  output logic [31:0] allocate_mask_o,
  output logic packet_valid_o,
  output rv32_pkg::packet_t packet_o,
  input logic packet_ready_i
);
  import rv32_pkg::*;
  typedef struct packed {
    logic valid, frozen;
    packet_t packet, offer;
    logic [2:0] count;
  } state_t;
  state_t q,d;
  packet_t refreshed, selected;
  hazard_pkg::source_t [7:0] sources;
  logic [7:0] ready, unused_forwarded;
  logic [7:0][31:0] values;
  logic [31:0] selected_writers;
  logic stopped, singleton;
  logic [2:0] count;
  forwarding_unit u_forward (.sources_i(sources), .producers_i(producers_i),
    .ready_o(ready), .forwarded_o(unused_forwarded), .values_o(values));
  always_comb begin
    packet_valid_o=q.frozen || (count!=0 && !block_younger_i);
    if (singleton) packet_valid_o=serial_valid_o && serial_ready_i;
    if (rst_i || flush_i) packet_valid_o=0;
  end
  always_comb begin
    packet_ready_o=!q.valid && !rst_i && !flush_i;
  end
  always_comb begin
    packet_o=q.frozen ? q.offer : selected;
  end
  always_comb begin
    // Refresh a waiting suffix before a committed producer disappears.
    refreshed=q.packet;
    for (int i=0; i<4; i++) begin
      for (int c=0; c<4; c++) begin
        if (commit_writes_i[c].valid && commit_writes_i[c].rd != 0) begin
          if (q.packet[i].decoded.rs1 == commit_writes_i[c].rd) refreshed[i].src1=commit_writes_i[c].value;
          if (q.packet[i].decoded.rs2 == commit_writes_i[c].rd) refreshed[i].src2=commit_writes_i[c].value;
        end
      end
      sources[2*i]='{used:q.packet[i].decoded.uses_rs1, rs:q.packet[i].decoded.rs1,
        busy:busy_i[q.packet[i].decoded.rs1], fallback_value:refreshed[i].src1};
      sources[2*i+1]='{used:q.packet[i].decoded.uses_rs2, rs:q.packet[i].decoded.rs2,
        busy:busy_i[q.packet[i].decoded.rs2], fallback_value:refreshed[i].src2};
    end
  end
  always_comb begin
    selected='0;
    count=0;
    selected_writers='0;
    stopped=!q.valid;
    singleton=q.valid && (q.packet[0].decoded.serial || q.packet[0].fault.valid);
    for (int i=0; i<4; i++) begin
      if (!q.packet[i].valid) stopped=1;
      if (i>0 && (q.packet[i].decoded.serial || q.packet[i].fault.valid || singleton)) stopped=1;
      if (!q.packet[i].fault.valid) begin
        if (!ready[2*i] || !ready[2*i+1]) stopped=1;
        if (q.packet[i].decoded.uses_rs1 && selected_writers[q.packet[i].decoded.rs1]) stopped=1;
        if (q.packet[i].decoded.uses_rs2 && selected_writers[q.packet[i].decoded.rs2]) stopped=1;
        if (q.packet[i].decoded.writes_rd &&
            (busy_i[q.packet[i].decoded.rd] || selected_writers[q.packet[i].decoded.rd])) stopped=1;
      end
      if (!stopped) begin
        selected[i]=refreshed[i];
        selected[i].src1=values[2*i];
        selected[i].src2=values[2*i+1];
        if (q.packet[i].decoded.writes_rd && !q.packet[i].fault.valid)
          selected_writers[q.packet[i].decoded.rd]=1;
        count=count+1'b1;
      end
    end
  end
  // Singleton valid is independent of block_younger: the controller raises
  // block_younger during this very handshake. EX ready depends only on capacity.
  always_comb begin
    serial_valid_o=singleton && count!=0 && packet_ready_i && !rst_i && !flush_i;
  end
  always_comb begin
    d=q;
    d.packet=refreshed;

    allocate_mask_o='0;
    if (packet_valid_o && !packet_ready_i && !q.frozen) begin
      d.frozen=1;
      d.offer=selected;
      d.count=count;
    end
    if (packet_valid_o && packet_ready_i) begin
      for (int i=0; i<4; i++)
        if (packet_o[i].valid && packet_o[i].decoded.writes_rd && !packet_o[i].fault.valid)
          allocate_mask_o[packet_o[i].decoded.rd]=1;
      d.packet='0;
      for (int i=0; i<4; i++)
        if (i+(q.frozen ? int'(q.count) : int'(count))<4)
          d.packet[i]=refreshed[i+(q.frozen ? int'(q.count) : int'(count))];
      d.valid=d.packet[0].valid;
      d.frozen=0;
    end
    if (packet_valid_i && packet_ready_o) begin
      d.valid=1;
      d.packet=packet_i;
      for (int i=0; i<4; i++) begin
        d.packet[i].src1=live_operands_i[2*i];
        d.packet[i].src2=live_operands_i[2*i+1];
      end
    end
    if (rst_i || flush_i) begin d='0; allocate_mask_o='0; end
  end
  always_ff @(posedge clk_i) begin
    q <= d;
  end
endmodule
