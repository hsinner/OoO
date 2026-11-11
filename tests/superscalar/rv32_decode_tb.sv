// Direct input vectors against the real decoder; no CPU/memory substitutes.
module rv32_decode_tb;
  import rv32_pkg::*;
  word_t instruction;
  decoded_t decoded, expected;
  string op_name, fault_name;
  int fd, fields, count;
  reg_idx_t rs1, rs2, rd;
  logic used1, used2, writes, serial, fault_valid;
  word_t immediate, address;

  rv32_decode dut (.instruction_i(instruction), .decoded_o(decoded));

  initial begin
    instruction = '0;
    count = 0;
    fd = $fopen("build/decode/vectors.txt", "r");
    if (fd == 0) $fatal(1, "Cannot open generated decoder vectors");
    while (!$feof(fd)) begin
      fields = $fscanf(fd, "%h %s %d %d %d %d %d %d %d %h %d %s %h\n",
                       instruction, op_name, rs1, rs2, rd, used1, used2,
                       writes, serial, immediate, fault_valid, fault_name, address);
      if (fields != 13) $fatal(1, "Malformed vector after case %0d", count);
      #1;
      // Check enum names independently of their package-assigned numeric values.
      if (decoded.op.name() != op_name || decoded.fault.kind.name() != fault_name)
        $fatal(1, "word=%h expected %s/%s got %s/%s", instruction, op_name,
               fault_name, decoded.op.name(), decoded.fault.kind.name());
      expected = '0;
      expected.op = decoded.op; // Names checked above; compare every other bit below.
      expected.rs1 = reg_idx_t'(rs1);
      expected.rs2 = reg_idx_t'(rs2);
      expected.rd = reg_idx_t'(rd);
      expected.uses_rs1 = 1'(used1);
      expected.uses_rs2 = 1'(used2);
      expected.writes_rd = 1'(writes);
      expected.serial = 1'(serial);
      expected.imm = immediate;
      expected.fault.valid = 1'(fault_valid);
      expected.fault.kind = decoded.fault.kind;
      expected.fault.address = address;
      if (decoded !== expected)
        $fatal(1, "word=%h op=%s expected record=%h got=%h",
               instruction, op_name, expected, decoded);
      count++;
    end
    $fclose(fd);
    if (count == 0) $fatal(1, "No decoder cases executed");
    $display("PASS: %0d RV32I decoder vectors, complete records checked", count);
    $finish;
  end
endmodule
