# Superscalar hazard validation

Command: `wsl -d Ubuntu -- bash scripts/check_hazards.sh` from the repository.
The script runs warning-fatal Verilator lint for each module, builds the real
SystemVerilog testbench, and runs the resulting executable.

Installed tool reports `Verilator 5.020 2024-01-01 rev (Debian 5.020-1)`.

Observed result:

```text
PASS: 128 source/producer routes, 120 priority pairs, forwarding and control-hazard directed checks
```

Checks cover all eight source ports against all sixteen producer positions,
all 120 youngest/older port pairs, unready and faulted producer blocking,
killed/nonwriting producer exclusion, fallback, busy-without-producer stalls,
x0 and pending/completed load-result readiness.

Control checks cover older-work drain, singleton admission and completion,
branch target and fall-through redirects, stable redirect data under repeated
backpressure, one flush per accepted event, trap priority, pending-event
backpressure and synchronous reset of pending recovery.

The build reported a host/WSL file timestamp clock-skew warning; compilation
completed and the executable passed. This is distinct from an RTL lint warning.

These are standalone module tests, not full-core simulation, instruction
compliance, synthesis or timing closure. Dispatch prefix freezing, same-cycle
commit refresh, scoreboard flush wiring, actual branch semantics, fetch response
draining, and externally visible store ordering still require integration tests.
No complete superscalar CPU is claimed.
