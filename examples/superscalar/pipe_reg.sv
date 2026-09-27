// One-entry elastic register, NOT a CPU stage implementation.
// Synchronous active-high reset; transfer on valid && ready at an edge.
// kill_i suppresses both interfaces and clears state at the next edge.
module pipe_reg #(
  parameter int unsigned WIDTH = 32
) (
  input  logic clk_i, rst_i, kill_i,
  input  logic valid_i,
  output logic ready_o,
  input  logic [WIDTH-1:0] data_i,
  output logic valid_o,
  input  logic ready_i,
  output logic [WIDTH-1:0] data_o
);
  logic valid_q, valid_d;
  logic [WIDTH-1:0] data_q, data_d;
  always_comb begin
    // Replace an occupied entry only when downstream consumes it.
    ready_o = (!valid_q || ready_i) && !rst_i && !kill_i;
    valid_o = valid_q && !rst_i && !kill_i;
    data_o = data_q;
    valid_d = valid_q;
    data_d = data_q;
    if (ready_o) begin
      valid_d = valid_i;
      if (valid_i) data_d = data_i;
    end
    // All control and reset selection stays in always_comb.
    if (rst_i || kill_i) begin
      valid_d = 1'b0;
      data_d = '0;
    end
  end
  always_ff @(posedge clk_i) begin
    valid_q <= valid_d;
    data_q <= data_d;
  end
endmodule
