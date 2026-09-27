#!/usr/bin/env bash
set -euo pipefail
verilator --lint-only -Wall --top-module forwarding_unit -f rtl/superscalar/files.f
verilator --lint-only -Wall --top-module control_hazard_unit -f rtl/superscalar/files.f
mkdir -p build/hazards
verilator --binary --timing -Wall --top-module hazard_tb -f rtl/superscalar/files.f tests/superscalar/hazard_tb.sv --Mdir build/hazards -o hazard_test
./build/hazards/hazard_test
