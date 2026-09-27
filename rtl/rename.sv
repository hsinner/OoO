// Implicit renaming: speculative values live in the ROB, committed ones here.
module rename (
  input logic clk_i, rst_i,
  input ooo_pkg::reg_t rs1_i, rs2_i,
  output ooo_pkg::operand_t a_o, b_o,
  input logic allocate_i,
  input ooo_pkg::reg_t rd_i,
  input ooo_pkg::tag_t allocate_tag_i,
  input logic commit_i,
  input ooo_pkg::reg_t commit_rd_i,
  input ooo_pkg::tag_t commit_tag_i,
  input ooo_pkg::word_t commit_value_i
);
  import ooo_pkg::*;
  typedef struct packed {
    logic [31:0] mapped;
    tag_t [31:0] tags;
    word_t [31:0] registers;
  } state_t;
  state_t state_q, state_d;
  always_comb begin
    a_o = '{ready: !state_q.mapped[rs1_i], tag: state_q.tags[rs1_i], value: state_q.registers[rs1_i]};
    b_o = '{ready: !state_q.mapped[rs2_i], tag: state_q.tags[rs2_i], value: state_q.registers[rs2_i]};
    state_d = state_q;
    if (commit_i && commit_rd_i != 0) begin
      state_d.registers[commit_rd_i] = commit_value_i;
      // A younger writer may already own the mapping. Do not erase it.
      if (state_q.mapped[commit_rd_i] && state_q.tags[commit_rd_i] == commit_tag_i)
        state_d.mapped[commit_rd_i] = 1'b0;
    end
    // Allocation wins over retirement when both name the same destination.
    if (allocate_i && rd_i != 0) begin
      state_d.mapped[rd_i] = 1'b1;
      state_d.tags[rd_i] = allocate_tag_i;
    end
    if (rst_i) state_d = '0;
  end
  always_ff @(posedge clk_i) begin
    state_q <= state_d;
  end
endmodule
