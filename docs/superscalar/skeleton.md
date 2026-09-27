# Superscalar implementation backbone

Start in [core.sv](../../rtl/superscalar/core.sv). **It is deliberately unfinished.**
The new stage modules have real interface declarations and numbered TODOs, but
no assignments, state transitions, functional tie-offs or instantiated CPU.
Undriven outputs are intentional. Do not run these shells as a processor or
interpret successful interface elaboration as functional verification.

The [architecture tutorial](tutorial.md) remains the design explanation. This
document is the implementation contract/checklist. Types and interfaces are a
proposed repository ABI: change related producers/consumers together if you
discover a better contract while implementing.

## 1. What exists and what you must implement

| File | Present now | Your completion responsibility |
| --- | --- | --- |
| `hazard_pkg.sv` | Implemented hazard types | Preserve compatibility or update its real tests |
| `forwarding_unit.sv` | Implemented/tested resolver | Wire only older producers in prescribed age order |
| `control_hazard_unit.sv` | Implemented/tested singleton/redirect controller | Integrate with commit/EEI and fetch transaction ownership |
| `rv32_pkg.sv` | New shared type declarations only | Review field ownership and EEI/bus choices |
| `rv32_decode.sv` | Empty combinational shell | All 40 instructions, exact legality, immediate/use flags |
| `alu.sv` | Empty combinational shell | Arithmetic, comparisons, shifts, bitwise results |
| `fetch.sv` | Empty sequential shell | PC, requests, response buffering, stale response drain |
| `decode_stage.sv` | Empty sequential shell | Four decoder instances and stable ordered packet |
| `regfile.sv` | Empty sequential shell | Eight read ports, four commit writes, x0 semantics |
| `scoreboard.sv` | Empty sequential shell | Writer allocation/release, x0 invariant and flush cleanup |
| `register_stage.sv` | Empty sequential shell | Held control packet, live operand sideband, commit bypass |
| `dispatch.sv` | Empty sequential shell | Forwarding hookup, oldest prefix, suffix retention, frozen offer |
| `execute.sv` | Empty sequential shell | Four ALUs, singleton target/address, exceptions and producers |
| `memory_stage.sv` | Empty sequential shell | Loads and data formatting; store descriptors only |
| `writeback.sv` | Empty sequential shell | Result holding, no architectural writes |
| `commit.sv` | Empty sequential shell | Ordered retirement, register writes, stores, traps and redirects |
| `memory_adapter.sv` | Empty sequential shell | One outstanding data request, owner and response routing |
| `recovery.sv` | Empty sequential shell | EEI trap/report/resume state around existing control unit |
| `core.sv` | Empty integration shell | Instantiate, wire and verify all contracts below |

The old OoO `rtl/alu.sv` and new skeleton `rtl/superscalar/alu.sv` use the same
module name intentionally in separate designs. **Never concatenate their file
lists into one compilation.** The manifests keep them separate. A future
combined build should rename or namespace the modules first.

## 2. Compile sets and honest status

- `rtl/files.f`: historical OoO experiment only.
- `rtl/superscalar/files.f`: existing implemented hazard modules only.
- `rtl/superscalar/skeleton.f`: shared types, existing hazards and all new shells.

Run the following from the repository root:

```powershell
wsl -d Ubuntu -- bash scripts/check_skeleton.sh
wsl -d Ubuntu -- bash scripts/check_hazards.sh
python scripts/build_superscalar_docs.py --check
```

The first command only parses/elaborates each declared interface. It suppresses
undriven/unused warnings **only for this intentionally empty skeleton build**.
All other warnings remain fatal. The hazard test script still uses strict lint
and actual simulation. No placeholder tests or fake passing CPU are supplied.

As you implement each module, give it a strict lint target without those
suppressions and real behavioral tests. Remove its UNIMPLEMENTED banner only
when its documented responsibilities and relevant tests pass. An elaboration
pass cannot establish reset behavior, handshake stability or ISA correctness.

## 3. Stage ownership and record validity

The package uses a superset `packet_t` to avoid dozens of premature per-stage
types. Lane 0 is oldest, and valid lanes form a compact prefix. Both outer
packet-valid and inner lane-valid must be meaningful; prohibit an outer-valid
packet with no valid lanes. Unowned fields are not architectural evidence.

| Field | Owner that establishes meaning | Consumer |
| --- | --- | --- |
| lane valid, PC, instruction, fetch fault | IF | All later stages |
| decoded fields, illegal fault | D | R/DP/EX/C |
| live RF read values | R sideband | DP on accepted input transfer |
| src1/src2 snapshots | DP | EX; refresh retained suffix from commit |
| result/address/store data/mask/next PC | EX | MEM/WB/C |
| load result/access fault | MEM | Forwarding/WB/C |
| held completion packet | WB | C |
| architectural write and retirement events | C | RF/scoreboard/trace/refresh |
| accepted trap and restart ownership | Recovery | EEI and IF |

Preserve prior faults. A fetch-fault word is not valid instruction data, so its
decode must not overwrite that earlier fault. A faulted producer remains live
and blocks dependent forwarding until valid recovery removes it.

`fault_kind_t` values are symbolic internal labels, not RISC-V `mcause` numeric
encodings. The EEI must define translation if architectural privilege is added.
`fault.address` is the bad PC/effective address for access/alignment faults,
the raw instruction bits for illegal instruction, and zero for ECALL/EBREAK
under this proposed external reporting contract. Preserve the original PC and
instruction separately in `trap_t` in all cases.

## 4. Clock boundaries: do not accidentally build sixteen stages

Each named sequential stage owns one resident packet. Interpret its input as
the previous stage's offer and its output as the current resident instruction's
processed result. Decide explicitly which side of an edge owns every field.
Do not add an output register to every module and then add another `pipe_reg`
between the same modules. That doubles the intended stage storage/latency.

Implement a cycle table for a single instruction before writing the top-level
wiring. EX-to-DP forwarding must come from the currently resident EX operation,
not the incoming DP candidate; otherwise it can form a combinational ALU loop.
DP may need internal suffix/offer state, but it still presents one logical
dispatch boundary. Record additional bubbles or buffers honestly if added.

Use the established pattern, choosing meaningful state per module:

```systemverilog
// Template only. Declare your state_t before using this pattern.
state_t state_q, state_d;
always_comb begin
  state_d = state_q;
  // TODO Defaults, handshake events, next state, flush priorities.
  // TODO Synchronous reset overrides applicable next-state fields.
end
always_ff @(posedge clk_i) begin
  state_q <= state_d;
end
```

Do not paste an empty hold-only block and call the module implemented. Keep all
logic in `always_comb` and only assignments in `always_ff`. Combinational decoder
and ALU do not need a clock or state.

## 5. Top-level wiring map

| Connection | Required rule |
| --- | --- |
| IF → D → R → DP → EX → MEM → WB → C | Stable packet valid/ready except the explicitly separate live RF sideband |
| R indices ↔ RF read values | Source slot `2*lane` = rs1, `2*lane+1` = rs2 |
| R live operands → DP | Sample only with R-to-DP handshake; handle same-edge commit bypass |
| C writes → RF, scoreboard, R and DP | One accepted event supplies state update, busy clear and operand refresh |
| DP allocate mask → scoreboard | Pulse only for actual DP-to-EX transfers with nonzero destinations |
| EX/MEM/WB/C producer arrays → DP | Each module exposes natural lane indices; core reverses lanes per stage |
| DP ↔ recovery serial handshake | A singleton cannot start independently of its EX transfer |
| C load/store adapter links | MEM owns loads; C alone authorizes stores |
| C branch/trap → recovery | Commit-qualified events, not raw EX exceptions |
| Recovery redirect → IF | IF accepts ownership even while stop_fetch is asserted |
| Frontend flush → IF/D/R/DP | Discard only younger contents and preserve required external response ownership |
| Backend trap flush → EX/MEM/WB/scoreboard | Only after all older effects settle; C/RF are not indiscriminately cleared |

Map forwarding producer ports 0..3 to EX lanes 3..0, then MEM, WB and C the
same way. All producers are older than DP consumers under this in-order design.
`occupied_o` must account for any live resident packet, even when output-valid
is low while waiting for memory. Compute backend_empty from EX/MEM/WB/C
occupancy and adapter idle, not merely their output-valid signals. Do not
include the waiting DP singleton itself in this drain condition.

## 6. The singleton handshake trap

The existing control unit raises block_younger in the cycle a singleton starts.
If DP uses that same signal to suppress the singleton's own serial_valid,
you create a combinational loop. Apply block_younger to ordinary younger work,
not to the special admission path that generated it.

Require serial admission and DP-to-EX transfer to be the same edge. DP may only
assert serial_valid when it has selected the singleton and EX can accept;
serial_ready then authorizes that singleton's transfer. EX ready must depend
on capacity, not on serial_valid or block_younger. If you choose a different
two-phase reservation scheme, document who owns a granted-but-not-yet-issued
singleton and update tests before relying on it.

For ordinary ALU dispatch, freeze an offered prefix and its resolved values
through backpressure. Do not grow the prefix or recompute changing forwarded
payloads while valid remains high. Retained suffix operands still need commit
refresh. Busy destination ownership is released only at commit, not forwarding.

## 7. Abstract memory contracts

The top-level instruction interface requests one aligned 16-byte block and
returns four words plus individual access-error bits. Only one request may be
outstanding. Emit a short prefix for a PC near a block end. There is no AXI,
cache or MMU implementation hidden behind these types.

The data interface uses aligned four-byte addresses, four little-endian byte
strobes and one outstanding transaction. The packet retains the original byte
address for extraction and fault reporting. Misaligned halfword/word operations
trap before sending requests. Writes are issued only from C, never MEM.

The adapter tracks owner until response consumption, even when the external
request has disappeared. idle means no held request, accepted transaction or
buffered response. Under serialization MEM and C should never compete; assert
that invariant, but still specify defensive arbitration rather than creating
two simultaneously ready requesters.

Successful acknowledgement must meet the selected EEI's completion/ordering
contract. A failed store must not already have externally visible partial
effects. If the selected bus cannot guarantee that, revise the platform error
contract; a pipeline flush cannot undo a device write. Reset must coordinate
with endpoints or drain outstanding transactions before losing ownership.

## 8. Trap report and resume are different events

Commit produces a stable trap record. Recovery accepts ownership, holds it for
the EEI, and keeps younger work blocked after C releases the faulting packet.
Only after the EEI accepts the report may recovery accept a resume PC. That PC
becomes the existing control-hazard unit's trap redirect destination. The faulting
PC is not implicitly a handler address.

If the EEI never requests resume, remain blocked. Do not clear the controller's
serial busy state merely because the report was delivered. Keep successful
serial_done for ordinary non-control singletons, not branches or faults.
Branch retirement/link write must coincide with acceptance of the corresponding
branch event; losing a branch to an older trap must not write its link register.

The tested control unit only arbitrates qualified events and holds redirects.
`recovery.sv` is the still-missing state machine that owns this longer report/
resume lifecycle. Its unit tests must exercise report stalls, delayed/no resume,
simultaneous branch/trap requests, and stale fetch responses during restart.

## 9. Completion tests by block

| Block | Minimum evidence before completion |
| --- | --- |
| Decoder | Every supported encoding family, reserved functions, immediate extrema, correct source-use flags |
| ALU | Signed boundaries, shifts 0/31, overflow wrap, comparisons and bitwise operations |
| IF | All four block offsets, delayed request/response, stall, redirect with outstanding response |
| D/R | Held-packet stability, fetch-fault preservation, RF same-edge write/read |
| RF/scoreboard | x0, four distinct commits, allocation/release overlap, exact live-writer ownership |
| DP | Prefix lengths 0..4, each lane dependency pair, retained suffix, frozen offer, singleton atomicity |
| EX | All result classes, branch link/target/alignment, no load-address forwarding |
| MEM/adapter | Each width/sign/mask, request exactly once, delayed response and owner retention |
| WB | Simultaneous consume/replace, stalls, faulted writer visibility |
| C | Four-wide retirement, older-prefix-before-fault, authorized store once, stalled events |
| Recovery | Trap/report/resume lifecycle, priority, one-shot flush, pending redirect stability |
| Core | Independent retirement model, memory effects, no wrong-path side effects, coordinated reset |

Do not write a test that passes just because an output stays zero in a shell.
Build tests when behavior is implemented and require them to detect meaningful
errors. The existing hazard tests remain real independent checks of those two
implemented blocks, not substitutes for this matrix.

## 10. Suggested implementation sequence

1. Review types and establish the external memory and EEI contract.
2. Implement decoder and ALU; prove their behavior separately.
3. Implement register file, scoreboard and packet storage conventions.
4. Build a single-lane eight-stage arithmetic path and retirement comparison.
5. Add serialized branches, loads/stores, fences and trap/report/resume handling.
6. Widen to four independent ALUs, then packet splitting and all hazard cases.
7. Integrate the existing forwarding/control units and verify full-core timing.
8. Run instruction coverage, independent ISA comparison and architectural tests
   under the documented EEI before claiming full RV32I support.

The roadmap can be adjusted as you learn, but preserve the distinction between
declared interfaces, implemented behavior, standalone tests and integrated proof.
