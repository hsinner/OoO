// Combinational integer ALU. EX supplies resolved operands, not register indices.
// Register and immediate variants share a calculation: EX selects b_i accordingly.
// LUI: b_i = decoded upper immediate (already shifted); a_i is ignored.
// AUIPC: a_i = instruction PC, b_i = decoded upper immediate.
// Branches, jumps, address generation and faults remain responsibilities of EX.
// Non-ALU operations return zero; this is NOT an instruction-valid indication.
module alu (
  input rv32_pkg::op_t op_i,
  input rv32_pkg::word_t a_i, b_i,
  output rv32_pkg::word_t result_o
);
  import rv32_pkg::*;
  logic [4:0] shift_amount;

  always_comb begin
    // RV32 shifts use only the low five bits, selecting a shift from 0 to 31.
    shift_amount = b_i[4:0];
    result_o = '0;
    case (op_i)
      // The 32-bit result naturally discards carry/borrow beyond bit 31.
      OP_ADD, OP_ADDI, OP_AUIPC: result_o = a_i + b_i;
      OP_SUB:                   result_o = a_i - b_i;
      OP_LUI:                   result_o = b_i;

      OP_AND, OP_ANDI: result_o = a_i & b_i;
      OP_OR,  OP_ORI:  result_o = a_i | b_i;
      OP_XOR, OP_XORI: result_o = a_i ^ b_i;

      OP_SLL, OP_SLLI: result_o = a_i << shift_amount;
      OP_SRL, OP_SRLI: result_o = a_i >> shift_amount;
      // >>> sign-fills only when its left operand has signed interpretation.
      OP_SRA, OP_SRAI: result_o = $signed(a_i) >>> shift_amount;

      // Comparisons produce a 32-bit zero or one, not a sign-extended bit.
      OP_SLT,  OP_SLTI:  result_o = {31'b0, ($signed(a_i) < $signed(b_i))};
      OP_SLTU, OP_SLTIU: result_o = {31'b0, (a_i < b_i)};
      default: begin end // EX must not consume this as a non-ALU completion.
    endcase
  end
endmodule
