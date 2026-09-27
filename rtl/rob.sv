// Unified ROB/reservation station: eight slots own values, operands and age.
// No slot is reused until retirement, so tags need no generation bit here.
module rob (
  input logic clk_i, rst_i,
  input logic valid_i,
  output logic ready_o,
  input ooo_pkg::word_t pc_i, instruction_i,
  input ooo_pkg::decoded_t decoded_i,
  input ooo_pkg::operand_t a_i, b_i,
  output logic allocate_o,
  output ooo_pkg::tag_t allocate_tag_o,
  output logic issue_valid_o,
  output ooo_pkg::tag_t issue_tag_o,
  output ooo_pkg::alu_op_t issue_op_o,
  output ooo_pkg::word_t issue_a_o, issue_b_o,
  input ooo_pkg::result_t result_i,
  output logic retire_valid_o, retire_fault_o,
  input logic retire_ready_i,
  output ooo_pkg::tag_t retire_tag_o,
  output ooo_pkg::reg_t retire_rd_o,
  output ooo_pkg::word_t retire_pc_o, retire_instruction_o, retire_value_o,
  output logic halted_o
);
  import ooo_pkg::*;
  typedef struct packed {
    entry_t [ROB_DEPTH-1:0] entries;
    tag_t head, tail;
    logic [TAG_W:0] count;
    logic halted;
  } state_t;
  state_t state_q, state_d;
  logic selected, retire_fire;
  tag_t selected_tag;
  operand_t resolved_a, resolved_b;
  // Architectural source indices are consumed by rename, not by this module.
  logic [9:0] unused_source_indices;
  issue_select u_select (.entries_i(state_q.entries), .head_i(state_q.head),
    .valid_o(selected), .tag_o(selected_tag));

  always_comb begin
    unused_source_indices = {decoded_i.rs1, decoded_i.rs2};
    state_d = state_q;
    ready_o = !rst_i && !state_q.halted && state_q.count < (TAG_W+1)'(ROB_DEPTH);
    retire_valid_o = !rst_i && !state_q.halted && state_q.count != 0 && state_q.entries[state_q.head].done;
    retire_fault_o = state_q.entries[state_q.head].illegal;
    retire_tag_o = state_q.head;
    retire_rd_o = state_q.entries[state_q.head].rd;
    retire_pc_o = state_q.entries[state_q.head].pc;
    retire_instruction_o = state_q.entries[state_q.head].instruction;
    retire_value_o = state_q.entries[state_q.head].result;
    retire_fire = retire_valid_o && retire_ready_i;
    // Stop all new activity on the cycle that the fault is accepted.
    if (retire_valid_o && retire_fault_o) ready_o = 1'b0;
    allocate_o = valid_i && ready_o;
    allocate_tag_o = state_q.tail;
    issue_valid_o = selected && !rst_i && !state_q.halted && !(retire_valid_o && retire_fault_o);
    issue_tag_o = selected_tag;
    issue_op_o = state_q.entries[selected_tag].op;
    issue_a_o = state_q.entries[selected_tag].a.value;
    issue_b_o = state_q.entries[selected_tag].b.value;
    halted_o = state_q.halted;
    resolved_a = a_i;
    resolved_b = b_i;

    // A producer may have completed before this consumer was dispatched.
    if (!a_i.ready && state_q.entries[a_i.tag].done) begin
      resolved_a.ready = 1'b1;
      resolved_a.value = state_q.entries[a_i.tag].result;
    end
    if (!b_i.ready && state_q.entries[b_i.tag].done) begin
      resolved_b.ready = 1'b1;
      resolved_b.value = state_q.entries[b_i.tag].result;
    end
    if (result_i.valid && !state_q.halted) begin
      state_d.entries[result_i.tag].done = 1'b1;
      state_d.entries[result_i.tag].result = result_i.value;
      // Broadcast wakes existing consumers and the incoming instruction.
      for (int slot = 0; slot < ROB_DEPTH; slot++) begin
        if (state_q.entries[slot].valid) begin
          if (!state_q.entries[slot].a.ready && state_q.entries[slot].a.tag == result_i.tag) begin
            state_d.entries[slot].a.ready = 1'b1;
            state_d.entries[slot].a.value = result_i.value;
          end
          if (!state_q.entries[slot].b.ready && state_q.entries[slot].b.tag == result_i.tag) begin
            state_d.entries[slot].b.ready = 1'b1;
            state_d.entries[slot].b.value = result_i.value;
          end
        end
      end
      if (!a_i.ready && a_i.tag == result_i.tag) begin
        resolved_a.ready = 1'b1;
        resolved_a.value = result_i.value;
      end
      if (!b_i.ready && b_i.tag == result_i.tag) begin
        resolved_b.ready = 1'b1;
        resolved_b.value = result_i.value;
      end
    end
    if (decoded_i.use_zero || decoded_i.use_pc) begin
      resolved_a.ready = 1'b1;
      resolved_a.value = decoded_i.use_pc ? pc_i : 32'b0;
    end
    if (decoded_i.immediate) begin
      resolved_b.ready = 1'b1;
      resolved_b.value = decoded_i.imm;
    end
    if (issue_valid_o) state_d.entries[selected_tag].issued = 1'b1;
    if (retire_fire) begin
      state_d.entries[state_q.head] = '0;
      state_d.head = state_q.head + 1'b1;
      state_d.count = state_d.count - 1'b1;
      if (retire_fault_o) state_d.halted = 1'b1;
    end
    if (allocate_o) begin
      state_d.entries[state_q.tail] = '{valid: 1'b1, issued: 1'b0,
        done: decoded_i.illegal, illegal: decoded_i.illegal,
        pc: pc_i, instruction: instruction_i, result: 32'b0,
        rd: decoded_i.rd, op: decoded_i.op, a: resolved_a, b: resolved_b};
      state_d.tail = state_q.tail + 1'b1;
      state_d.count = state_d.count + 1'b1;
    end
    if (rst_i) state_d = '0;
  end
  always_ff @(posedge clk_i) begin
    state_q <= state_d;
  end
endmodule
