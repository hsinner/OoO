// WB completion holding only: architectural writes belong exclusively to C.
module writeback (
  input logic clk_i, rst_i, flush_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  output logic packet_ready_o,
  output logic packet_valid_o,
  output rv32_pkg::packet_t packet_o,
  input logic packet_ready_i,
  output hazard_pkg::producer_t [3:0] producers_o,
  output logic occupied_o
);
  import rv32_pkg::*;
  packet_t packet_q, packet_d;
  logic valid_q, valid_d;
  always_comb begin
    for (int i=0; i<4; i++)
      producers_o[i] = make_producer(packet_q[i], packet_valid_o, 1'b1);
  end
  always_comb begin
    packet_ready_o = (!valid_q || packet_ready_i) && !rst_i && !flush_i;
  end
  always_comb begin
    packet_valid_o = valid_q && !rst_i && !flush_i;
  end
  always_comb begin
    packet_o = packet_q;
  end
  always_comb begin
    occupied_o = valid_q;
  end
  always_comb begin

    packet_d = packet_q;
    valid_d = valid_q;
    if (packet_ready_o) begin
      valid_d = packet_valid_i;
      if (packet_valid_i) packet_d = packet_i;
    end
    if (rst_i || flush_i) begin valid_d=0; packet_d='0; end
  end
  always_ff @(posedge clk_i) begin
    packet_q <= packet_d;
    valid_q <= valid_d;
  end
endmodule
