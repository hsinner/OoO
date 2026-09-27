// Combinational DP operand resolver. Does NOT perform packet-prefix selection.
// Producers MUST be older than every DP consumer and ordered youngest first:
// EX lane 3..0, MEM lane 3..0, WB lane 3..0, C lane 3..0.
// Keep a writer visible while its result is unready or faulted. Otherwise an
// older matching value could be selected incorrectly. Killed writers are absent.
module forwarding_unit (
  input hazard_pkg::source_t [hazard_pkg::SOURCES-1:0] sources_i,
  input hazard_pkg::producer_t [hazard_pkg::PRODUCERS-1:0] producers_i,
  output logic [hazard_pkg::SOURCES-1:0] ready_o, forwarded_o,
  output logic [hazard_pkg::SOURCES-1:0][31:0] values_o
);
  import hazard_pkg::*;
  logic [SOURCES-1:0] found;
  always_comb begin
    ready_o = '0;
    forwarded_o = '0;
    values_o = '0;
    found = '0;
    for (int s = 0; s < SOURCES; s++) begin
      if (!sources_i[s].used || sources_i[s].rs == 0) begin
        ready_o[s] = 1'b1;
      end else begin
        ready_o[s] = !sources_i[s].busy;
        values_o[s] = sources_i[s].fallback_value;
        for (int p = 0; p < PRODUCERS; p++) begin
          if (!found[s] && producers_i[p].valid && producers_i[p].writes_rd &&
              !producers_i[p].killed && producers_i[p].rd != 0 &&
              producers_i[p].rd == sources_i[s].rs) begin
            found[s] = 1'b1;
            ready_o[s] = producers_i[p].ready && !producers_i[p].fault;
            forwarded_o[s] = ready_o[s];
            // A matching unready/faulted producer blocks even if an older one
            // is ready. Zero invalid data to make accidental consumption clear.
            values_o[s] = ready_o[s] ? producers_i[p].value : 32'b0;
          end
        end
      end
    end
  end
endmodule
