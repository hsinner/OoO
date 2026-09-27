// RV32I integer computation subset. Unsupported encodings retire as faults.
module decode (
  input ooo_pkg::word_t instruction_i,
  output ooo_pkg::decoded_t decoded_o
);
  import ooo_pkg::*;
  always_comb begin
    decoded_o = '0;
    decoded_o.op = ALU_ADD;
    decoded_o.rs1 = instruction_i[19:15];
    decoded_o.rs2 = instruction_i[24:20];
    decoded_o.rd = instruction_i[11:7];
    decoded_o.imm = {{20{instruction_i[31]}}, instruction_i[31:20]};
    case (instruction_i[6:0])
      7'b0110111, 7'b0010111: begin // LUI, AUIPC
        decoded_o.immediate = 1'b1;
        decoded_o.use_zero = instruction_i[6:0] == 7'b0110111;
        decoded_o.use_pc = instruction_i[6:0] == 7'b0010111;
        decoded_o.imm = {instruction_i[31:12], 12'b0};
      end
      7'b0010011, 7'b0110011: begin
        decoded_o.immediate = instruction_i[6:0] == 7'b0010011;
        case (instruction_i[14:12])
          3'b000: decoded_o.op = (!decoded_o.immediate && instruction_i[30]) ? ALU_SUB : ALU_ADD;
          3'b001: decoded_o.op = ALU_SLL;
          3'b010: decoded_o.op = ALU_SLT;
          3'b011: decoded_o.op = ALU_SLTU;
          3'b100: decoded_o.op = ALU_XOR;
          3'b101: decoded_o.op = instruction_i[30] ? ALU_SRA : ALU_SRL;
          3'b110: decoded_o.op = ALU_OR;
          3'b111: decoded_o.op = ALU_AND;
        endcase
        // Validate funct7; in ordinary immediate instructions it is immediate data.
        if (!decoded_o.immediate) begin
          decoded_o.illegal = !(instruction_i[31:25] == 7'b0000000 ||
            (instruction_i[31:25] == 7'b0100000 &&
             (instruction_i[14:12] == 3'b000 || instruction_i[14:12] == 3'b101)));
        end else if (instruction_i[14:12] == 3'b001) begin
          decoded_o.illegal = instruction_i[31:25] != 7'b0000000;
        end else if (instruction_i[14:12] == 3'b101) begin
          decoded_o.illegal = !(instruction_i[31:25] == 7'b0000000 || instruction_i[31:25] == 7'b0100000);
        end
      end
      default: decoded_o.illegal = 1'b1;
    endcase
  end
endmodule
