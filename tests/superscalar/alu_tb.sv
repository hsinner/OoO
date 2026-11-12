// Direct tests of the real superscalar ALU using an independent integer oracle.
module alu_tb;
  import rv32_pkg::*;
  op_t op, candidate;
  word_t a, b, result, expected;
  string op_name;
  int fd, fields, count;
  logic found;
  alu dut (.op_i(op), .a_i(a), .b_i(b), .result_o(result));

  initial begin
    op = OP_ILLEGAL;
    a = '0;
    b = '0;
    count = 0;
    fd = $fopen("build/alu/vectors.txt", "r");
    if (fd == 0) $fatal(1, "Cannot open ALU vectors");
    while (!$feof(fd)) begin
      fields = $fscanf(fd, "%s %h %h %h\n", op_name, a, b, expected);
      if (fields != 4) $fatal(1, "Malformed vector after %0d", count);
      // Resolve enum names rather than depending on package numeric assignments.
      found = 1'b0;
      candidate = candidate.first();
      for (int i = 0; i < candidate.num(); i++) begin
        if (candidate.name() == op_name) begin
          op = candidate;
          found = 1'b1;
        end
        candidate = candidate.next();
      end
      if (!found) $fatal(1, "Unknown vector operation %s", op_name);
      #1;
      if (result !== expected)
        $fatal(1, "%s a=%h b=%h expected=%h got=%h", op_name, a, b, expected, result);
      count++;
    end
    $fclose(fd);
    if (count == 0) $fatal(1, "No ALU tests executed");
    $display("PASS: %0d ALU vectors", count);
    $finish;
  end
endmodule
