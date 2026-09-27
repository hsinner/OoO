// Scan by distance from the ROB head, never by raw circular tag magnitude.
module issue_select (
  input ooo_pkg::entry_t [ooo_pkg::ROB_DEPTH-1:0] entries_i,
  input ooo_pkg::tag_t head_i,
  output logic valid_o,
  output ooo_pkg::tag_t tag_o
);
  import ooo_pkg::*;
  tag_t candidate;
  always_comb begin
    valid_o = 1'b0;
    tag_o = '0;
    candidate = '0;
    for (int distance = 0; distance < ROB_DEPTH; distance++) begin
      candidate = head_i + tag_t'(distance);
      if (!valid_o && entries_i[candidate].valid && !entries_i[candidate].issued &&
          !entries_i[candidate].illegal && entries_i[candidate].a.ready && entries_i[candidate].b.ready) begin
        valid_o = 1'b1;
        tag_o = candidate;
      end
    end
  end
endmodule
