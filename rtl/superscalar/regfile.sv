// Committed 32x32 register file. R provides explicit same-edge commit bypass.
module regfile (
  input logic clk_i, rst_i,
  input rv32_pkg::read_indices_t read_indices_i,
  output rv32_pkg::read_values_t read_values_o,
  input rv32_pkg::commit_writes_t commit_writes_i
);
  import rv32_pkg::*;
  word_t [31:0] regs_q, regs_d;
  always_comb begin
    regs_d = regs_q;
    for (int i=0; i<4; i++)
      if (commit_writes_i[i].valid && commit_writes_i[i].rd != 0)
        regs_d[commit_writes_i[i].rd] = commit_writes_i[i].value;
    regs_d[0] = '0;
    if (rst_i) regs_d = '0; // Teaching-platform reset policy: all registers zero.
    for (int i=0; i<8; i++)
      read_values_o[i] = read_indices_i[i] == 0 ? '0 : regs_q[read_indices_i[i]];
  end
  always_ff @(posedge clk_i) begin
    regs_q <= regs_d;
  end
endmodule
