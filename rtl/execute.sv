// Three registered result stages expose dependency stalls in the teaching core.
// This is a fixed-latency ALU pipeline, not a multiplier or a timing claim.
module execute (
  input logic clk_i, rst_i,
  input logic valid_i,
  input ooo_pkg::tag_t tag_i,
  input ooo_pkg::alu_op_t op_i,
  input ooo_pkg::word_t a_i, b_i,
  output ooo_pkg::result_t result_o
);
  import ooo_pkg::*;
  result_t [2:0] pipe_q, pipe_d;
  word_t value;
  alu u_alu (.op_i, .a_i, .b_i, .value_o(value));
  always_comb begin
    pipe_d[0] = '{valid: valid_i, tag: tag_i, value: value};
    pipe_d[1] = pipe_q[0];
    pipe_d[2] = pipe_q[1];
    result_o = pipe_q[2];
    if (rst_i) begin
      pipe_d = '0;
      result_o = '0;
    end
  end
  always_ff @(posedge clk_i) begin
    pipe_q <= pipe_d;
  end
endmodule
