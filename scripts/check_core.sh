#!/usr/bin/env bash
set -euo pipefail
python3 tests/superscalar/core_vectors.py
verilator --lint-only -Wall --top-module core -f rtl/superscalar/skeleton.f
verilator --binary -j 2 --timing -Wall --top-module core_tb -f rtl/superscalar/skeleton.f \
  tests/superscalar/core_tb.sv --Mdir build/core -o core_test
for seed in 1 7 19; do ./build/core/core_test +seed="$seed"; done
