// Shared types. Fixed small sizes keep the first implementation inspectable.
package ooo_pkg;
  localparam int ROB_DEPTH = 8;
  localparam int TAG_W = $clog2(ROB_DEPTH);
  typedef logic [31:0] word_t;
  typedef logic [4:0] reg_t;
  typedef logic [TAG_W-1:0] tag_t;
  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND
  } alu_op_t;
  typedef struct packed {
    alu_op_t op;
    reg_t rs1, rs2, rd;
    word_t imm;
    logic immediate, use_pc, use_zero, illegal;
  } decoded_t;
  typedef struct packed {
    logic ready;
    tag_t tag;
    word_t value;
  } operand_t;
  typedef struct packed {
    logic valid, issued, done, illegal;
    word_t pc, instruction, result;
    reg_t rd;
    alu_op_t op;
    operand_t a, b;
  } entry_t;
  typedef struct packed {
    logic valid;
    tag_t tag;
    word_t value;
  } result_t;
endpackage
