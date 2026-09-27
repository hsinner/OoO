// Interface specification only. This package implements no processor behavior.
package rv32_pkg;
  localparam int LANES = 4;
  localparam int XLEN = 32;
  typedef logic [XLEN-1:0] word_t;
  typedef logic [4:0] reg_idx_t;
  typedef logic [LANES-1:0] lane_mask_t;
  typedef word_t [LANES-1:0] lane_values_t;
  typedef reg_idx_t [7:0] read_indices_t;
  typedef word_t [7:0] read_values_t;

  typedef enum logic [5:0] {
    OP_ILLEGAL, OP_LUI, OP_AUIPC,
    OP_ADD, OP_SUB, OP_SLL, OP_SLT, OP_SLTU, OP_XOR, OP_SRL, OP_SRA, OP_OR, OP_AND,
    OP_ADDI, OP_SLTI, OP_SLTIU, OP_XORI, OP_ORI, OP_ANDI, OP_SLLI, OP_SRLI, OP_SRAI,
    OP_BEQ, OP_BNE, OP_BLT, OP_BGE, OP_BLTU, OP_BGEU, OP_JAL, OP_JALR,
    OP_LB, OP_LH, OP_LW, OP_LBU, OP_LHU, OP_SB, OP_SH, OP_SW,
    OP_FENCE, OP_ECALL, OP_EBREAK
  } op_t;
  // Symbolic internal causes, NOT privileged mcause encodings. An EEI adapter
  // must translate these if privileged architectural state is added later.
  typedef enum logic [3:0] {
    FAULT_NONE, FAULT_INSN_ALIGN, FAULT_INSN_ACCESS, FAULT_ILLEGAL,
    FAULT_BREAKPOINT, FAULT_LOAD_ALIGN, FAULT_LOAD_ACCESS,
    FAULT_STORE_ALIGN, FAULT_STORE_ACCESS, FAULT_ECALL
  } fault_kind_t;
  typedef struct packed {
    logic valid;
    fault_kind_t kind;
    word_t address; // Relevant address/instruction bits per specification.
  } fault_t;
  typedef struct packed {
    op_t op;
    reg_idx_t rs1, rs2, rd;
    logic uses_rs1, uses_rs2, writes_rd;
    logic serial; // Memory/control/fence/system/illegal instruction.
    word_t imm;
    fault_t fault;
  } decoded_t;
  // A single superset keeps stage interfaces understandable. Fields are only
  // meaningful after their owning stage (see skeleton.md ownership table).
  typedef struct packed {
    logic valid;
    word_t pc, instruction;
    decoded_t decoded;
    word_t src1, src2;
    word_t result, address, store_data;
    logic [3:0] byte_mask;
    logic next_pc_valid;
    word_t next_pc;
    fault_t fault;
  } lane_t;
  typedef lane_t [LANES-1:0] packet_t; // lane 0 oldest, compact valid prefix.
  typedef struct packed {
    logic valid; // Accepted architectural register write this edge.
    reg_idx_t rd;
    word_t value;
  } reg_write_t;
  typedef reg_write_t [LANES-1:0] commit_writes_t;
  typedef struct packed {
    logic valid; // Passive event, no ready: receiver must observe every cycle.
    word_t pc, instruction;
    logic writes_rd;
    reg_idx_t rd;
    word_t value;
    logic memory;
    logic memory_write;
    word_t address, memory_data;
    logic [3:0] byte_mask;
  } retire_t;
  typedef retire_t [LANES-1:0] retire_bundle_t;
  typedef struct packed {
    word_t pc, instruction;
    fault_t fault;
  } trap_t;
  // Abstract instruction port: one outstanding aligned 16-byte block request.
  // Each word has its own access-error bit. This is not an AXI implementation.
  typedef struct packed {
    lane_values_t words;
    lane_mask_t access_error;
  } if_response_t;
  // Abstract data port: aligned 4-byte address, little endian, one outstanding.
  // Original effective address remains in the instruction for trap/trace use.
  typedef struct packed {
    logic write;
    word_t aligned_address, write_data;
    logic [3:0] byte_mask;
  } mem_request_t;
  typedef struct packed {
    word_t read_data;
    logic error;
  } mem_response_t;
endpackage
