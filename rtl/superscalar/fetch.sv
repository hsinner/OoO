// One instruction-block transaction; redirect retains stale request ownership.
module fetch (
  input logic clk_i, rst_i,
  input rv32_pkg::word_t reset_pc_i,
  input logic stop_fetch_i, flush_i,
  input logic redirect_valid_i,
  input rv32_pkg::word_t redirect_pc_i,
  output logic redirect_ready_o,
  output logic request_valid_o,
  output rv32_pkg::word_t request_address_o,
  input logic request_ready_i,
  input logic response_valid_i,
  input rv32_pkg::if_response_t response_i,
  output logic response_ready_o,
  output logic packet_valid_o,
  output rv32_pkg::packet_t packet_o,
  input logic packet_ready_i,
  output logic outstanding_o
);
  import rv32_pkg::*;
  typedef struct packed {
    word_t pc, request_pc;
    logic [1:0] phase; // 0 idle, 1 held request, 2 awaiting response.
    logic stale, valid;
    packet_t packet;
  } state_t;
  state_t q, d;
  always_comb begin
    request_valid_o = q.phase == 1 && !rst_i;
  end
  always_comb begin
    request_address_o = {q.request_pc[31:4],4'b0};
  end
  always_comb begin
    response_ready_o = q.phase == 2 && !rst_i;
  end
  always_comb begin
    // Taking redirect ownership does not require memory idle.
    redirect_ready_o = !rst_i;
  end
  always_comb begin
    packet_valid_o = q.valid && !rst_i && !flush_i && !redirect_valid_i;
  end
  always_comb begin
    packet_o = q.packet;
  end
  always_comb begin
    outstanding_o = q.phase != 0;
  end
  always_comb begin
    d=q;

    if (packet_valid_o && packet_ready_i) d.valid=0;
    if (q.phase == 0 && !q.valid && !stop_fetch_i && !flush_i && !redirect_valid_i) begin
      if (q.pc[1:0] != 0) begin
        d.packet='0;
        d.packet[0].valid=1;
        d.packet[0].pc=q.pc;
        d.packet[0].fault='{valid:1, kind:FAULT_INSN_ALIGN, address:q.pc};
        d.valid=1;
      end else begin
        d.request_pc=q.pc;
        d.phase=1;
        d.stale=0;
        d.pc={q.pc[31:4],4'b0}+32'd16;
      end
    end
    if (request_valid_o && request_ready_i) d.phase=2;
    if (response_valid_i && response_ready_o) begin
      d.phase=0;
      d.stale=0;
      if (!q.stale) begin
        d.packet='0;
        for (int i=0; i<4; i++) begin
          if (i + int'(q.request_pc[3:2]) < 4) begin
            d.packet[i].valid=1;
            d.packet[i].pc=q.request_pc+32'(i*4);
            d.packet[i].instruction=response_i.words[i+int'(q.request_pc[3:2])];
            if (response_i.access_error[i+int'(q.request_pc[3:2])])
              d.packet[i].fault='{valid:1, kind:FAULT_INSN_ACCESS, address:d.packet[i].pc};
          end
        end
        d.valid=1;
      end
    end
    // Never withdraw an offered/accepted external transaction on redirect.
    // Drain its response, discard it, and then issue from the replacement PC.
    if (flush_i || redirect_valid_i) begin
      d.valid=0;
      if (d.phase != 0) d.stale=1;
    end
    if (redirect_valid_i && redirect_ready_o) d.pc=redirect_pc_i;
    if (rst_i) begin d='0; d.pc=reset_pc_i; end
  end
  always_ff @(posedge clk_i) begin
    q <= d;
  end
endmodule
