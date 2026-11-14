// Stable R control packet; live register values are sampled separately by DP.
module register_stage (
  input logic clk_i, rst_i, flush_i,
  input logic packet_valid_i,
  input rv32_pkg::packet_t packet_i,
  output logic packet_ready_o,
  output rv32_pkg::read_indices_t read_indices_o,
  input rv32_pkg::read_values_t read_values_i,
  input rv32_pkg::commit_writes_t commit_writes_i,
  output logic packet_valid_o,
  output rv32_pkg::packet_t packet_o,
  output rv32_pkg::read_values_t live_operands_o,
  input logic packet_ready_i
);
  import rv32_pkg::*;
  packet_t packet_q, packet_d;
  logic valid_q, valid_d;
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
    for (int i=0; i<4; i++) begin
      read_indices_o[2*i] = packet_q[i].decoded.uses_rs1 ? packet_q[i].decoded.rs1 : 5'd0;
      read_indices_o[2*i+1] = packet_q[i].decoded.uses_rs2 ? packet_q[i].decoded.rs2 : 5'd0;
    end
  end
  always_comb begin
    live_operands_o = read_values_i;
    for (int s=0; s<8; s++) begin
      for (int c=0; c<4; c++)
        if (commit_writes_i[c].valid && commit_writes_i[c].rd == read_indices_o[s])
          live_operands_o[s] = commit_writes_i[c].value;
      if (read_indices_o[s] == 0) live_operands_o[s] = '0;
    end

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
