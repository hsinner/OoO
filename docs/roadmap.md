# Implementation sequence

Historical OoO roadmap. Follow the [current superscalar roadmap](superscalar/roadmap.md)
for new development.

Each milestone must include working RTL, module contracts, tutorial updates,
directed tests and differential checks before the next one begins.

| Stage | Deliverable | Exit evidence |
| --- | --- | --- |
| 0 (implemented) | Integer OoO stream backend | Local checks in validation.md |
| 1 | Fetch handshake, branch/jump unit, conservative stop-at-branch frontend | Taken/not-taken, JALR masking, alignment policy, blocked fetch responses |
| 2 | Byte-addressable loads/stores with ordered memory execution | All widths, sign extension, byte masks, delayed responses, faults, no speculative stores |
| 3 | Complete chosen RV32I execution environment | Instruction-by-instruction coverage, trap contract, fence behavior, ISA suite and independent ISA model |
| 4 | Separate physical register file, map, busy table, free list | Exhaustion, WAW/WAR chains, precise rollback, zero-register invariants |
| 5 | Speculative frontend and recovery checkpoints | Nested branches, all simultaneous completion/redirect/commit cases, no leaked registers or stale results |
| 6 | Load/store queues and disambiguation | Youngest older matching store, partial overlap, replay, fault versus violation priority |
| 7 | Caches and nonblocking misses | MSHR exhaustion, same-line merge, refill/eviction ordering, backpressure |
| 8 | Superscalar rename, issue and retirement | Within-bundle dependencies, port conflicts, ordered retirement prefix, recovery under width |
| 9 | Selected M/A/C and privileged facilities | Extension-specific reference tests; LR/SC progress and memory litmus tests where applicable |
| 10 | Translation and protection, chosen OS platform | TLB invalidation, page faults, PMP, interrupt routing and platform boot validation |
| 11 | Advanced prediction and prefetch experiments | Reproducible workload improvements against simpler predictors with area/timing costs |
| 12 | FPGA/ASIC implementation | Constraints, synthesis, timing, CDC/reset review, equivalence, board or physical implementation evidence |

RV64, floating point, vector execution, multicore coherence and simultaneous
multithreading are separate architectural projects, not automatic consequences
of increasing a parameter. Choose them from workload and platform requirements.
