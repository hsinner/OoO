#!/usr/bin/env bash
set -euo pipefail
# Interface checks ONLY. These exclusions are local to deliberately empty shells.
# Strict functional lint for implemented modules remains in check_hazards.sh.
modules=(rv32_decode alu fetch decode_stage regfile scoreboard register_stage dispatch execute memory_stage writeback commit memory_adapter recovery core)
for module in "${modules[@]}"; do
  verilator --lint-only -Wall -Wno-UNDRIVEN -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    --top-module "$module" -f rtl/superscalar/skeleton.f
done
printf 'PASS: %s skeleton interfaces parsed/elaborated; NO behavior implemented or simulated\n' "${#modules[@]}"
