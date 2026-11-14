// Resident EX packet drives four ALUs and singleton control/address calculations.
module execute (
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
  packet_t q,d;
  logic valid_q, valid_d;
  word_t [3:0] a,b,result;
  logic [3:0] taken;
  for (genvar i=0; i<4; i++) begin : g_alu
    alu u_alu (.op_i(q[i].decoded.op), .a_i(a[i]), .b_i(b[i]), .result_o(result[i]));
  end
  always_comb begin
    occupied_o=valid_q;
  end
  always_comb begin
    packet_valid_o=valid_q && !rst_i && !flush_i;
  end
  always_comb begin
    packet_ready_o=(!valid_q || packet_ready_i) && !rst_i && !flush_i;
  end
  always_comb begin
    for (int i=0; i<4; i++) begin
      a[i]=q[i].src1;
      b[i]=q[i].src2;
      case (q[i].decoded.op)
        OP_ADDI,OP_SLTI,OP_SLTIU,OP_XORI,OP_ORI,OP_ANDI,OP_SLLI,OP_SRLI,OP_SRAI,OP_LUI:
          b[i]=q[i].decoded.imm;
        OP_AUIPC: begin a[i]=q[i].pc; b[i]=q[i].decoded.imm; end
        default: begin end
      endcase
    end
  end
  always_comb begin
    packet_o=q;
    taken='0;
    for (int i=0; i<4; i++) begin
      packet_o[i].result=result[i];
      packet_o[i].address=q[i].src1+q[i].decoded.imm;
      packet_o[i].next_pc=q[i].pc+32'd4;
      packet_o[i].next_pc_valid=is_control(q[i].decoded.op);
      case (q[i].decoded.op)
        OP_BEQ: taken[i]=q[i].src1==q[i].src2;
        OP_BNE: taken[i]=q[i].src1!=q[i].src2;
        OP_BLT: taken[i]=$signed(q[i].src1)<$signed(q[i].src2);
        OP_BGE: taken[i]=$signed(q[i].src1)>=$signed(q[i].src2);
        OP_BLTU: taken[i]=q[i].src1<q[i].src2;
        OP_BGEU: taken[i]=q[i].src1>=q[i].src2;
        OP_JAL,OP_JALR: begin taken[i]=1; packet_o[i].result=q[i].pc+32'd4; end
        default: begin end
      endcase
      if (taken[i]) packet_o[i].next_pc=q[i].pc+q[i].decoded.imm;
      if (q[i].decoded.op==OP_JALR)
        packet_o[i].next_pc=(q[i].src1+q[i].decoded.imm)&32'hfffffffe;
      packet_o[i].byte_mask=memory_mask(q[i].decoded.op) << packet_o[i].address[1:0];
      packet_o[i].store_data=q[i].src2 << {packet_o[i].address[1:0],3'b0};
      if (!q[i].fault.valid) begin
        if (taken[i] && packet_o[i].next_pc[1:0]!=0)
          packet_o[i].fault='{valid:1,kind:FAULT_INSN_ALIGN,address:packet_o[i].next_pc};
        if ((is_load(q[i].decoded.op) || is_store(q[i].decoded.op)) &&
            ((memory_mask(q[i].decoded.op)==4'b1111 && packet_o[i].address[1:0]!=0) ||
             (memory_mask(q[i].decoded.op)==4'b0011 && packet_o[i].address[0])))
          packet_o[i].fault='{valid:1,kind:is_load(q[i].decoded.op)?FAULT_LOAD_ALIGN:FAULT_STORE_ALIGN,
                              address:packet_o[i].address};
      end
      producers_o[i]=make_producer(packet_o[i],valid_q && !rst_i && !flush_i,
                                   !is_load(q[i].decoded.op));
    end

  end
  always_comb begin
    d=q; valid_d=valid_q;
    if (packet_ready_o) begin valid_d=packet_valid_i; if (packet_valid_i) d=packet_i; end
    if (rst_i || flush_i) begin d='0; valid_d=0; end
  end
  always_ff @(posedge clk_i) begin
    q <= d;
    valid_q <= valid_d;
  end
endmodule
