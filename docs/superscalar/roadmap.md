# Four-wide in-order RV32I roadmap

**Implementation update:** the eight-stage baseline is now implemented. Read
[the actual RTL walkthrough](implementation.md) for current state/signals and
connections. Instructions to build missing stages below can now be followed as
reimplementation exercises. Advanced alternatives remain future extensions.


The [tutorial](tutorial.md) defines the design. Existing OoO RTL is historical,
not a completed implementation milestone below.

| Stage | Deliverable | Acceptance gate |
| --- | --- | --- |
| S0 (this change) | Architecture tutorial and storage example | Review stage contracts and platform assumptions |
| Baseline (implemented) | All stages, helpers, types and integrated core | Strict lint and independent architectural simulation; see validation.md |
| S1 | Single-lane pipeline with all eight stages | Arithmetic retirement comparison, stalls and reset |
| S2 | Complete decode and serialized branches/jumps | Encoding, link values and target/alignment tests |
| S3 | Serialized data memory, fence and trap interface | Widths, byte masks, faults, delayed responses, precise stores |
| S4 | Four-lane ALUs, scoreboard and packet splitting | Every prefix length; RAW/WAW/WAR; stale operands; four-wide retirement |
| S5 | RV32I execution-environment validation | Independent ISA model, instruction coverage and architectural suites |
| S6 | Selected forwarding and performance improvements | Producer priority, load-use hazards and measured IPC/timing |

The baseline now integrates decode, ALU, EX/MEM/WB/C forwarding, scoreboarding,
ordered packet splitting, serialized control/memory and EEI recovery. Full-core
regression compares architectural events to an independent oracle. See
[validation evidence](validation.md) and [implementation walkthrough](implementation.md).

The table retains acceptance targets for learning and broader verification.
An official ISA compliance suite, exhaustive formal proofs, FPGA integration and
measured timing/area remain open. Caches, prediction, privilege, interrupts,
extensions and RV64 require additional explicit scope.
