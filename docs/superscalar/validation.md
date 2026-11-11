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

## Decoder validation — 2026-11-11

Run from the repo root:

```powershell
wsl -d Ubuntu -- bash scripts/check_decode.sh
```

Strict Verilator lint and simulation passed:

```text
PASS: 99496 RV32I decoder vectors, complete records checked
```

The independent vector generator encodes instructions from supplied operands and
compares their expected records against the real RTL. Coverage includes all 40
operations, every register index, exhaustive signed I/S/B immediates, all shift
amounts, U/J boundaries and bit positions, all OP funct7/funct3 combinations,
shift function restrictions, unsupported opcodes/functions, FENCE variants and
SYSTEM restrictions. A known ADDI word is also checked independently of the
encoder, before and after an illegal word. This is not exhaustive coverage of
all 32-bit instruction words, formal proof, or integrated ISA compliance.

Decoder conventions: unused register indices are zero; writes_rd excludes x0;
source-use flags indicate operand roles even for x0; shift immediates contain
only the shift amount. Loads to x0 remain serialized loads. ECALL/EBREAK keep
their own op names and carry FAULT_ECALL/FAULT_BREAKPOINT with address zero.
Unsupported encodings produce a canonical OP_ILLEGAL record with no operand or
write flags and the instruction bits as fault.address. FENCE ignores encoded
rs1/rd and handles all fm/pred/succ variants conservatively via serialization;
FENCE.I, CSR, privileged instructions and other extensions are not implemented.

The WSL build emitted a file timestamp clock-skew warning; strict RTL lint,
compilation and the executable completed successfully. Fetch faults must still
take precedence over this decoder's record when decode_stage is implemented.
