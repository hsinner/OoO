# Superscalar validation

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
The subsequent full-core section records the implemented pipeline integration.

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

## ALU validation — 2026-11-12

Run `wsl -d Ubuntu -- bash scripts/check_alu.sh` from the repository root.
Strict Verilator lint and simulation passed: `PASS: 16936 ALU vectors`.
Tests cover all 21 supported operation names, boundary operand cross-products,
deterministic pseudorandom operands (seed 0x32a1), all 32 shift amounts with
upper shift-operand bits set/clear, and the zero default for every other named
operation after a nonzero result. Expected values come from Python unbounded
integer arithmetic with explicit truncation and division-based right shifts.

This is standalone functional evidence, not exhaustive proof, integrated EX
verification, FPGA synthesis or timing closure. The host/WSL build emitted a
timestamp clock-skew warning; compilation and execution completed successfully.


## Full-core integration — 2026-11-14

All nineteen RTL files in `rtl/superscalar/skeleton.f` now form the functional
baseline. The historical manifest name is retained for compatibility. Strict
lint has no suppressed unused/undriven/combinational-loop warnings.

Run from the repository root:

```powershell
wsl -d Ubuntu -- bash scripts/check_core.sh
python scripts/check_repo.py
python scripts/build_superscalar_docs.py --check
```

The program generator creates 499 words and an independent sequential Python
oracle produces 495 expected retirement/trap events. It covers all forty RV32I
operations, both outcomes of each branch, forwarding/dependencies, destination
conflicts, jump/link behavior, byte/halfword/word memory operations, signed and
unsigned loads, loads to x0, FENCE, ECALL/EBREAK, illegal instructions, alignment
and access faults, and EEI resume. Four hundred arithmetic instructions use a
fixed random seed so failures can be reproduced. This is directed plus randomized
integration testing, not an official architectural certification suite.

Observed runs (same program, different deterministic bus/EEI timing schedules):

| Timing seed | Cycles | Architectural events | Four-wide retirement cycles | Request/trap stalled cycles | Pipeline stalled channels/cycles | Redirects with outstanding fetch |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 1924 | 495 | 66 | 90 | 546 | 6 |
| 7 | 1918 | 495 | 66 | 88 | 546 | 6 |
| 19 | 1906 | 495 | 66 | 85 | 543 | 2 |

The test checks ordered PC/instruction events, accepted register results,
memory trace fields, fault kind/address, and every final data-memory byte.
It also checks stable held pipeline packets/requests/trap reports, compact lane
prefixes, and x0 register/scoreboard invariants. The memory and EEI endpoints
are explicitly simulation-only environments; the processor stages are real RTL.

The host/WSL build can report timestamp clock-skew warnings. These are distinct
from RTL warnings; the simulator executable must still finish with PASS.
No synthesis, FPGA resource use, timing closure, physical implementation, or
exhaustive formal/ISA compliance result is claimed. The external platform must
honor one outstanding transaction per port, stable valid/ready handshakes,
coordinated reset and failed-store-without-side-effect semantics.

For the entire active regression on Linux/WSL, run `make check-superscalar`.
The older `make check` still checks only the historical OoO experiment.
