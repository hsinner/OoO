// Direct stimuli against real modules, not substitute CPU/memory models.
module hazard_tb;
  import hazard_pkg::*;
  logic clk = 0;
  logic rst, serial_valid, backend_empty, serial_ready, serial_done;
  logic branch_valid, branch_ready, trap_valid, trap_ready;
  logic [31:0] branch_pc, trap_pc, redirect_pc;
  logic redirect_valid, redirect_ready, block_younger, stop_fetch, flush_frontend, flush_backend;
  source_t [SOURCES-1:0] sources;
  producer_t [PRODUCERS-1:0] producers;
  logic [SOURCES-1:0] ready, forwarded;
  logic [SOURCES-1:0][31:0] values;
  forwarding_unit u_forward (.sources_i(sources), .producers_i(producers),
    .ready_o(ready), .forwarded_o(forwarded), .values_o(values));
  control_hazard_unit u_control (.clk_i(clk), .rst_i(rst),
    .serial_valid_i(serial_valid), .backend_empty_i(backend_empty), .serial_ready_o(serial_ready),
    .serial_done_i(serial_done), .branch_valid_i(branch_valid), .branch_pc_i(branch_pc),
    .branch_ready_o(branch_ready), .trap_valid_i(trap_valid), .trap_pc_i(trap_pc),
    .trap_ready_o(trap_ready), .redirect_valid_o(redirect_valid), .redirect_pc_o(redirect_pc),
    .redirect_ready_i(redirect_ready), .block_younger_o(block_younger), .stop_fetch_o(stop_fetch),
    .flush_frontend_o(flush_frontend), .flush_backend_o(flush_backend));
  task automatic tick;
    #1; clk = 1; #1; clk = 0; #1;
  endtask
  task automatic check(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
  endtask
  initial begin
    sources = '0; producers = '0;
    rst = 1; serial_valid = 0; backend_empty = 1; serial_done = 0;
    branch_valid = 0; trap_valid = 0; branch_pc = 32'h100; trap_pc = 32'h800;
    redirect_ready = 0;
    tick(); rst = 0; #1;
    check(ready == '1 && forwarded == 0 && values == 0, "unused sources");
    // Every source port and every producer port must route correctly.
    for (int s = 0; s < SOURCES; s++) begin
      for (int p = 0; p < PRODUCERS; p++) begin
        sources = '0; producers = '0;
        sources[s] = '{used:1, rs:5'd7, busy:1, fallback_value:32'hdead};
        producers[p] = '{valid:1, writes_rd:1, killed:0, fault:0, ready:1, rd:5'd7, value:32'(p+1)};
        #1; check(ready[s] && forwarded[s] && values[s] == 32'(p+1), "port routing");
      end
    end
    sources = '0; producers = '0;
    sources[0] = '{used:1, rs:5'd7, busy:0, fallback_value:32'd77};
    #1; check(ready[0] && !forwarded[0] && values[0] == 77, "fallback");
    sources[0].busy = 1;
    #1; check(!ready[0], "busy without visible producer must stall");
    // Exhaust every ordered pair; younger unready/faulted must block older ready.
    for (int young = 0; young < PRODUCERS; young++) begin
      for (int old = young+1; old < PRODUCERS; old++) begin
        producers = '0;
        producers[old] = '{valid:1, writes_rd:1, killed:0, fault:0, ready:1, rd:5'd7, value:32'd111};
        producers[young] = '{valid:1, writes_rd:1, killed:0, fault:0, ready:0, rd:5'd7, value:32'd222};
        #1; check(!ready[0] && !forwarded[0], "unready youngest must block");
        producers[young].ready = 1;
        #1; check(ready[0] && values[0] == 222, "youngest wins");
        producers[young].fault = 1;
        #1; check(!ready[0], "fault cannot fall through to old data");
        producers[young].killed = 1;
        #1; check(ready[0] && values[0] == 111, "killed writer excluded");
        producers[young].killed = 0; producers[young].writes_rd = 0;
        #1; check(ready[0] && values[0] == 111, "nonwriter excluded");
      end
    end
    sources[0].rs = 0;
    #1; check(ready[0] && values[0] == 0 && !forwarded[0], "x0");
    // A load producer becomes usable only once its data is ready.
    sources[0].rs = 7; producers = '0;
    producers[4] = '{valid:1, writes_rd:1, killed:0, fault:0, ready:0, rd:5'd7, value:32'd55};
    #1; check(!ready[0], "pending load");
    producers[4].ready = 1;
    #1; check(ready[0] && values[0] == 55, "completed load");

    serial_valid = 1; backend_empty = 0;
    #1; check(!serial_ready, "must drain older work");
    backend_empty = 1;
    #1; check(serial_ready && block_younger && stop_fetch, "singleton admission");
    tick(); serial_valid = 0;
    #1; check(block_younger && !serial_ready, "singleton holds younger work");
    serial_done = 1; tick(); serial_done = 0;
    #1; check(!block_younger, "ordinary singleton releases on commit");
    // Taken and fall-through are both resolved next-PC requests.
    for (int outcome = 0; outcome < 2; outcome++) begin
      serial_valid = 1; tick(); serial_valid = 0;
      branch_pc = outcome == 0 ? 32'h100 : 32'h104;
      branch_valid = 1;
      #1; check(branch_ready && flush_frontend && !flush_backend, "branch acceptance");
      tick(); branch_valid = 0;
      repeat (4) begin
        #1; check(redirect_valid && redirect_pc == branch_pc && block_younger &&
                  !flush_frontend && !branch_ready, "held redirect / no repeated flush");
        tick();
      end
      redirect_ready = 1; tick(); redirect_ready = 0;
      #1; check(!redirect_valid && !block_younger, "redirect consumed once");
    end
    branch_valid = 1; trap_valid = 1;
    #1; check(trap_ready && !branch_ready && flush_backend && flush_frontend, "trap priority");
    tick(); branch_valid = 0; trap_valid = 0;
    #1; check(redirect_valid && redirect_pc == trap_pc, "trap destination");
    // A second request must wait; it cannot mutate the held redirect payload.
    branch_valid = 1; branch_pc = 32'h900;
    #1; check(!branch_ready && redirect_pc == trap_pc, "pending request backpressure");
    branch_valid = 0;
    rst = 1; tick(); rst = 0;
    #1; check(!redirect_valid && !block_younger, "reset clears pending recovery");
    $display("PASS: 128 source/producer routes, 120 priority pairs, forwarding and control-hazard directed checks");
    $finish;
  end
endmodule
