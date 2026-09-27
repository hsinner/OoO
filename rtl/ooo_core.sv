// Start here: instruction-stream backend, NOT a complete RV32I processor.
// Input and retirement transfers occur on valid && ready at the rising edge.
// Reset is synchronous, active high; hold for at least one rising edge.
module ooo_core (
  input logic clk_i, rst_i,
  input logic instruction_valid_i,
  output logic instruction_ready_o,
  input ooo_pkg::word_t instruction_i, pc_i,
  output logic retire_valid_o,
  input logic retire_ready_i,
  output logic retire_fault_o,
  output ooo_pkg::reg_t retire_rd_o,
  output ooo_pkg::word_t retire_pc_o, retire_instruction_o, retire_value_o,
  output logic halted_o,
  output logic issue_valid_o,
  output ooo_pkg::tag_t issue_tag_o
);
  import ooo_pkg::*;
  decoded_t decoded;
  operand_t a, b;
  logic allocate, commit, rename_allocate;
  tag_t allocate_tag, retire_tag;
  alu_op_t issue_op;
  word_t issue_a, issue_b;
  result_t result;
  always_comb begin
    commit = retire_valid_o && retire_ready_i && !retire_fault_o;
    rename_allocate = allocate && !decoded.illegal;
  end
  decode u_decode (.instruction_i, .decoded_o(decoded));
  rename u_rename (.clk_i, .rst_i, .rs1_i(decoded.rs1), .rs2_i(decoded.rs2),
    .a_o(a), .b_o(b), .allocate_i(rename_allocate), .rd_i(decoded.rd),
    .allocate_tag_i(allocate_tag), .commit_i(commit), .commit_rd_i(retire_rd_o),
    .commit_tag_i(retire_tag), .commit_value_i(retire_value_o));
  rob u_rob (.clk_i, .rst_i, .valid_i(instruction_valid_i), .ready_o(instruction_ready_o),
    .pc_i, .instruction_i, .decoded_i(decoded), .a_i(a), .b_i(b),
    .allocate_o(allocate), .allocate_tag_o(allocate_tag), .issue_valid_o, .issue_tag_o,
    .issue_op_o(issue_op), .issue_a_o(issue_a), .issue_b_o(issue_b), .result_i(result),
    .retire_valid_o, .retire_fault_o, .retire_ready_i, .retire_tag_o(retire_tag),
    .retire_rd_o, .retire_pc_o, .retire_instruction_o, .retire_value_o, .halted_o);
  execute u_execute (.clk_i, .rst_i, .valid_i(issue_valid_o), .tag_i(issue_tag_o),
    .op_i(issue_op), .a_i(issue_a), .b_i(issue_b), .result_o(result));
endmodule
