// Writer ownership: commit releases, accepted dispatch allocates; allocation wins.
module scoreboard (
  input logic clk_i, rst_i, flush_i,
  input logic [31:0] allocate_mask_i,
  input rv32_pkg::commit_writes_t commit_writes_i,
  output logic [31:0] busy_o
);
  import rv32_pkg::*;
  logic [31:0] busy_q, busy_d;
  always_comb begin
    busy_o = busy_q;
    busy_d = busy_q;
    for (int i=0; i<4; i++)
      if (commit_writes_i[i].valid) busy_d[commit_writes_i[i].rd] = 1'b0;
    busy_d = busy_d | allocate_mask_i;
    busy_d[0] = 1'b0;
    if (rst_i || flush_i) busy_d = '0;
  end
  always_ff @(posedge clk_i) begin
    busy_q <= busy_d;
  end
endmodule
