module alu (
  input ooo_pkg::alu_op_t op_i,
  input ooo_pkg::word_t a_i, b_i,
  output ooo_pkg::word_t value_o
);
  import ooo_pkg::*;
  always_comb begin
    value_o = '0;
    case (op_i)
      ALU_ADD:  value_o = a_i + b_i;
      ALU_SUB:  value_o = a_i - b_i;
      ALU_SLL:  value_o = a_i << b_i[4:0];
      ALU_SLT:  value_o = {31'b0, $signed(a_i) < $signed(b_i)};
      ALU_SLTU: value_o = {31'b0, a_i < b_i};
      ALU_XOR:  value_o = a_i ^ b_i;
      ALU_SRL:  value_o = a_i >> b_i[4:0];
      ALU_SRA:  value_o = $unsigned($signed(a_i) >>> b_i[4:0]);
      ALU_OR:   value_o = a_i | b_i;
      ALU_AND:  value_o = a_i & b_i;
      default:  value_o = '0;
    endcase
  end
endmodule
