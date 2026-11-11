// Combinational RV32I decoder: one instruction in, one description out.
// No register reads, execution, pipeline state or architectural side effects.
// Unused register indices are zero. writes_rd excludes x0; uses_rs* describe
// operand roles even when the encoded source is x0. Shift immediates are shamt.
// FENCE conservatively serializes all memory (including reserved fm variants);
// its ignored rs1/rd fields create no dependencies. FENCE.I/CSR/M/C are excluded.
module rv32_decode (
  input rv32_pkg::word_t instruction_i,
  output rv32_pkg::decoded_t decoded_o
);
  import rv32_pkg::*;
  logic [6:0] opcode, funct7;
  logic [2:0] funct3;
  word_t imm_i, imm_s, imm_b, imm_u, imm_j;

  always_comb begin
    opcode = instruction_i[6:0];
    funct3 = instruction_i[14:12];
    funct7 = instruction_i[31:25];
    imm_i = {{20{instruction_i[31]}}, instruction_i[31:20]};
    imm_s = {{20{instruction_i[31]}}, instruction_i[31:25], instruction_i[11:7]};
    imm_b = {{19{instruction_i[31]}}, instruction_i[31], instruction_i[7],
             instruction_i[30:25], instruction_i[11:8], 1'b0};
    imm_u = {instruction_i[31:12], 12'b0};
    imm_j = {{11{instruction_i[31]}}, instruction_i[31], instruction_i[19:12],
             instruction_i[20], instruction_i[30:21], 1'b0};

    // Every combinational path assigns every field. OP_ILLEGAL remains selected
    // unless the complete supported opcode/function combination is recognized.
    decoded_o = '0;
    decoded_o.op = OP_ILLEGAL;
    case (opcode)
      7'b0110111: begin // LUI
        decoded_o.op = OP_LUI;
        decoded_o.writes_rd = 1'b1;
        decoded_o.imm = imm_u;
      end
      7'b0010111: begin // AUIPC: EX adds this immediate to the owning lane's PC.
        decoded_o.op = OP_AUIPC;
        decoded_o.writes_rd = 1'b1;
        decoded_o.imm = imm_u;
      end
      7'b1101111: begin // JAL
        decoded_o.op = OP_JAL;
        decoded_o.writes_rd = 1'b1;
        decoded_o.serial = 1'b1;
        decoded_o.imm = imm_j;
      end
      7'b1100111: begin // JALR permits only funct3=000.
        if (funct3 == 3'b000) decoded_o.op = OP_JALR;
        decoded_o.uses_rs1 = 1'b1;
        decoded_o.writes_rd = 1'b1;
        decoded_o.serial = 1'b1;
        decoded_o.imm = imm_i;
      end
      7'b1100011: begin // Conditional branches; 010/011 are not base branches.
        case (funct3)
          3'b000: decoded_o.op = OP_BEQ;
          3'b001: decoded_o.op = OP_BNE;
          3'b100: decoded_o.op = OP_BLT;
          3'b101: decoded_o.op = OP_BGE;
          3'b110: decoded_o.op = OP_BLTU;
          3'b111: decoded_o.op = OP_BGEU;
          default: begin end
        endcase
        decoded_o.uses_rs1 = 1'b1;
        decoded_o.uses_rs2 = 1'b1;
        decoded_o.serial = 1'b1;
        decoded_o.imm = imm_b;
      end
      7'b0000011: begin // Loads: address generation and access faults occur later.
        case (funct3)
          3'b000: decoded_o.op = OP_LB;
          3'b001: decoded_o.op = OP_LH;
          3'b010: decoded_o.op = OP_LW;
          3'b100: decoded_o.op = OP_LBU;
          3'b101: decoded_o.op = OP_LHU;
          default: begin end
        endcase
        decoded_o.uses_rs1 = 1'b1;
        decoded_o.writes_rd = 1'b1;
        decoded_o.serial = 1'b1;
        decoded_o.imm = imm_i;
      end
      7'b0100011: begin // Stores read rs1 for address and rs2 for store data.
        case (funct3)
          3'b000: decoded_o.op = OP_SB;
          3'b001: decoded_o.op = OP_SH;
          3'b010: decoded_o.op = OP_SW;
          default: begin end
        endcase
        decoded_o.uses_rs1 = 1'b1;
        decoded_o.uses_rs2 = 1'b1;
        decoded_o.serial = 1'b1;
        decoded_o.imm = imm_s;
      end
      7'b0010011: begin // Register/immediate arithmetic.
        case (funct3)
          3'b000: decoded_o.op = OP_ADDI;
          3'b010: decoded_o.op = OP_SLTI;
          3'b011: decoded_o.op = OP_SLTIU;
          3'b100: decoded_o.op = OP_XORI;
          3'b110: decoded_o.op = OP_ORI;
          3'b111: decoded_o.op = OP_ANDI;
          3'b001: if (funct7 == 7'b0000000) decoded_o.op = OP_SLLI;
          3'b101: begin
            case (funct7)
              7'b0000000: decoded_o.op = OP_SRLI;
              7'b0100000: decoded_o.op = OP_SRAI;
              default: begin end
            endcase
          end
          default: begin end
        endcase
        decoded_o.uses_rs1 = 1'b1;
        decoded_o.writes_rd = 1'b1;
        decoded_o.imm = imm_i;
        if (funct3 == 3'b001 || funct3 == 3'b101)
          decoded_o.imm = {27'b0, instruction_i[24:20]};
      end
      7'b0110011: begin // Register/register: check both function fields.
        case ({funct7, funct3})
          10'b0000000_000: decoded_o.op = OP_ADD;
          10'b0100000_000: decoded_o.op = OP_SUB;
          10'b0000000_001: decoded_o.op = OP_SLL;
          10'b0000000_010: decoded_o.op = OP_SLT;
          10'b0000000_011: decoded_o.op = OP_SLTU;
          10'b0000000_100: decoded_o.op = OP_XOR;
          10'b0000000_101: decoded_o.op = OP_SRL;
          10'b0100000_101: decoded_o.op = OP_SRA;
          10'b0000000_110: decoded_o.op = OP_OR;
          10'b0000000_111: decoded_o.op = OP_AND;
          default: begin end
        endcase
        decoded_o.uses_rs1 = 1'b1;
        decoded_o.uses_rs2 = 1'b1;
        decoded_o.writes_rd = 1'b1;
      end
      7'b0001111: begin
        // The base FENCE rule ignores rd/rs1 and conservatively handles all fm,
        // predecessor and successor combinations. No Zifencei support here.
        if (funct3 == 3'b000) decoded_o.op = OP_FENCE;
        decoded_o.serial = 1'b1;
      end
      7'b1110011: begin
        // Exact encodings avoid accepting CSR, privileged or reserved SYSTEM.
        case (instruction_i)
          32'h00000073: begin
            decoded_o.op = OP_ECALL;
            decoded_o.fault.valid = 1'b1;
            decoded_o.fault.kind = FAULT_ECALL;
          end
          32'h00100073: begin
            decoded_o.op = OP_EBREAK;
            decoded_o.fault.valid = 1'b1;
            decoded_o.fault.kind = FAULT_BREAKPOINT;
          end
          default: begin end
        endcase
        decoded_o.serial = 1'b1;
      end
      default: begin end
    endcase

    // Canonicalize fields according to their roles, not their bit positions.
    if (decoded_o.uses_rs1) decoded_o.rs1 = instruction_i[19:15];
    if (decoded_o.uses_rs2) decoded_o.rs2 = instruction_i[24:20];
    if (decoded_o.writes_rd) decoded_o.rd = instruction_i[11:7];
    decoded_o.writes_rd = decoded_o.writes_rd && (decoded_o.rd != 5'd0);

    // Invalid function combinations must not leak tentative dependencies/writes.
    if (decoded_o.op == OP_ILLEGAL) begin
      decoded_o = '0;
      decoded_o.op = OP_ILLEGAL;
      decoded_o.serial = 1'b1;
      decoded_o.fault.valid = 1'b1;
      decoded_o.fault.kind = FAULT_ILLEGAL;
      decoded_o.fault.address = instruction_i;
    end
  end
endmodule
