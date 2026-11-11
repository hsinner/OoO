#!/usr/bin/env bash
set -euo pipefail
# Run from repo root. Completed RTL gets strict lint, not skeleton suppressions.
python3 tests/superscalar/decode_vectors.py
verilator --lint-only -Wall --top-module rv32_decode rtl/superscalar/rv32_pkg.sv rtl/superscalar/rv32_decode.sv
verilator --binary --timing -Wall --top-module rv32_decode_tb \
  rtl/superscalar/rv32_pkg.sv rtl/superscalar/rv32_decode.sv \
  tests/superscalar/rv32_decode_tb.sv --Mdir build/decode -o decode_test
./build/decode/decode_test
