// Four combinational decoders feeding one D-stage register; earlier faults win.
module decode_stage (
  input logic clk_i, rst_i, flush_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  output logic packet_ready_o,
  output logic packet_valid_o,
  output rv32_pkg::packet_t packet_o,
  input logic packet_ready_i
);
  import rv32_pkg::*;
  packet_t packet_q, packet_d, decoded_packet;
  decoded_t [3:0] decoded;
  logic valid_q, valid_d;
  for (genvar i=0; i<4; i++) begin : g_decode
    rv32_decode u_decode (.instruction_i(packet_i[i].instruction), .decoded_o(decoded[i]));
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
    decoded_packet = packet_i;
    for (int i=0; i<4; i++) begin
      decoded_packet[i].decoded = decoded[i];
      if (packet_i[i].fault.valid) decoded_packet[i].decoded.serial = 1'b1;
      else decoded_packet[i].fault = decoded[i].fault;
    end

    packet_d = packet_q;
    valid_d = valid_q;
    if (packet_ready_o) begin
      valid_d = packet_valid_i;
      if (packet_valid_i) packet_d = decoded_packet;
    end
    if (rst_i || flush_i) begin valid_d=0; packet_d='0; end
  end
  always_ff @(posedge clk_i) begin
    packet_q <= packet_d;
    valid_q <= valid_d;
  end
endmodule
