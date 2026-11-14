#!/usr/bin/env bash
set -euo pipefail
# Separate manifest from the historical root rtl/alu.sv.
python3 tests/superscalar/alu_vectors.py
verilator --lint-only -Wall --top-module alu rtl/superscalar/hazard_pkg.sv rtl/superscalar/rv32_pkg.sv rtl/superscalar/alu.sv
verilator --binary --timing -Wall --top-module alu_tb \
  rtl/superscalar/hazard_pkg.sv rtl/superscalar/rv32_pkg.sv rtl/superscalar/alu.sv \
  tests/superscalar/alu_tb.sv --Mdir build/alu -o alu_test
./build/alu/alu_test
