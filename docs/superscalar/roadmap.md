# Four-wide in-order RV32I roadmap

The [tutorial](tutorial.md) defines the design. Existing OoO RTL is historical,
not a completed implementation milestone below.

| Stage | Deliverable | Acceptance gate |
| --- | --- | --- |
| S0 (this change) | Architecture tutorial and storage example | Review stage contracts and platform assumptions |
| S1 | Single-lane pipeline with all eight stages | Arithmetic retirement comparison, stalls and reset |
| S2 | Complete decode and serialized branches/jumps | Encoding, link values and target/alignment tests |
| S3 | Serialized data memory, fence and trap interface | Widths, byte masks, faults, delayed responses, precise stores |
| S4 | Four-lane ALUs, scoreboard and packet splitting | Every prefix length; RAW/WAW/WAR; stale operands; four-wide retirement |
| S5 | RV32I execution-environment validation | Independent ISA model, instruction coverage and architectural suites |
| S6 | Selected forwarding and performance improvements | Producer priority, load-use hazards and measured IPC/timing |

Standalone forwarding and control-hazard modules now exist with directed tests.
They are prerequisites for S4/S6 and control-flow integration, not completion
of those milestones. EX/MEM/WB/C forwarding is part of the target design now;
S6 validates integrated paths and performance. See tutorial sections 21–23.

No S1–S6 completion, ISA compliance or hardware performance is claimed yet.
Each stage must include working RTL, tests, interface documentation and tutorial
updates. Caches, prediction, privilege, interrupts, extensions, RV64 and physical
implementation require additional explicit scope.
