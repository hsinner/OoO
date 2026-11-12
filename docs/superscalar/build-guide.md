# Start building: your step-by-step RTL implementation guide

Start with the decoder and ALU, then build one functioning lane through all eight
stages before enabling four-lane dispatch. Keep the existing four-lane interfaces
throughout; initially only lane 0 carries valid instructions. This final section
is your practical route through the course, from the first edit to integration.

Thirteen processor modules remain intentionally unfinished. The decoder, ALU,
forwarding and control-hazard units now contain implementations. The decoder
steps below remain useful as a guided reading/reimplementation exercise; you
can inspect the completed rv32_decode.sv and run check_decode.sh. The code below illustrates
structure and leaves the assignment logic for you; it does not complete the RTL.

Your first milestone is: **decode ADDI, calculate its result, and verify both
independently before introducing clocked pipeline behavior.**

## B1. Open these files and understand the vocabulary

| File | Why you need it now |
| --- | --- |
| [rv32_pkg.sv](../../rtl/superscalar/rv32_pkg.sv) | Shared types and field meanings |
| [rv32_decode.sv](../../rtl/superscalar/rv32_decode.sv) | First implementation task |
| [alu.sv](../../rtl/superscalar/alu.sv) | Second implementation task |
| [pipe_reg.sv](../../examples/superscalar/pipe_reg.sv) | Working example of the sequential coding style |
| [Lab workbook](labs.md) | L2–L4 support your first sessions |

In rv32_pkg, focus on word_t (32 bits), reg_idx_t (a five-bit register index),
op_t (an internal operation name), and decoded_t (the decoder output record).
Understand those types before changing them. A register index identifies a
storage location; it is not the value stored there.

Keep the historical root rtl/ design separate from rtl/superscalar/. In
particular, they contain different modules named alu. Use the superscalar file
lists or focused module commands rather than compiling every .sv file together.

## B2. Write a contract before writing logic

For every module, record its inputs, outputs, state, events and default behavior.
For the decoder, the contract is:

| Question | Answer |
| --- | --- |
| What enters? | One instruction word |
| What leaves? | One decoded_t record |
| What state does it own? | None |
| What changes the output? | Changing the instruction input |
| What is the default? | Illegal-instruction record until a supported encoding is recognized |
| What belongs elsewhere? | Register reads, arithmetic execution and retirement |

The decoder is combinational. It needs no clock, state_q/state_d or always_ff.
The generic state-related TODOs in its shell apply only to modules that actually
own state. Similarly, alu.sv is a combinational function; execute.sv owns the
surrounding instruction and its timing.

## B3. Implement one decoder case first

Start with the instruction below, encoded as 0x00700293:

```text
addi x5, x0, 7
```

Identify opcode=instruction[6:0], rd=[11:7], funct3=[14:12], rs1=[19:15], and
the I-type immediate=[31:20]. ADDI has opcode 0010011 and funct3 000. Use the
[official RV32I specification](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
as the authority for encoding and semantics.

| decoded_t field | Expected value for this example |
| --- | --- |
| op | OP_ADDI |
| rs1 | 0 |
| rd | 5 |
| uses_rs1 | 1 |
| uses_rs2 | 0 |
| writes_rd | 1 |
| imm | 0x00000007 |
| serial | 0 |
| fault.valid | 0 |

The decoder names registers. It does not read x0, calculate a result or write x5.
Use this incomplete structure inside the existing module:

```systemverilog
always_comb begin
  // Establish every field before instruction-specific overrides.
  decoded_o = '0;

  // Default: no supported instruction has been recognized.
  decoded_o.op            = OP_ILLEGAL;
  decoded_o.serial        = 1'b1;
  decoded_o.fault.valid   = 1'b1;
  decoded_o.fault.kind    = FAULT_ILLEGAL;
  decoded_o.fault.address = instruction_i;

  // TODO: Recognize ADDI using opcode and funct3.
  // TODO: Extract rs1 and rd.
  // TODO: Construct the sign-extended immediate.
  // TODO: Set source-use and destination flags.
  // TODO: Clear the default fault for a recognized legal instruction.
end
```

Defaults give each field a value on every combinational path. They prevent
accidental retained values and make unrecognized inputs explicit. For an I-type
immediate, the following concatenation produces twenty sign bits plus twelve
instruction bits, totaling 32 bits:

```systemverilog
{{20{instruction_i[31]}}, instruction_i[31:20]}
```

Stop after ADDI is correct. Unimplemented instructions remain unsupported at this
development milestone; that is not a claim of complete RV32I support. Later,
extend the encoding matrix carefully, including ISA-defined hints and FENCE's
specified ignored/reserved-field behavior rather than rejecting every unusual bit.

## B4. Verify the decoded record before expanding it

Write a decoder testbench under tests/superscalar/. This is an assignment to
create a new testbench, not a claim that a completed decoder test already exists.
Check the relevant record fields, not only the operation name.

| Test | What it checks |
| --- | --- |
| ADDI with immediate 7 | Basic field extraction |
| ADDI with immediate −1 | Sign extension |
| ADDI with nonzero rs1 | Register index extraction |
| ADDI with rd=x0 | Destination suppression policy without deleting the instruction |
| Unsupported word at this milestone | Illegal default |
| Different words applied consecutively | No accidental carryover of fields |

A useful bug to catch is uses_rs2=1 for ADDI. That creates a false dependency on
bits belonging to the immediate. Specify your writes_rd convention for x0
consistently; downstream allocation and architectural writes must always exclude x0.

After implementing the module, run this focused lint command from the repo root:

```powershell
wsl -d Ubuntu -- verilator --lint-only -Wall --top-module rv32_decode rtl/superscalar/rv32_pkg.sv rtl/superscalar/rv32_decode.sv
```

This is a validation command to run, not a recorded pass for your future RTL.
Investigate diagnostics. The skeleton script suppresses expected undriven/unused
warnings for shells; those suppressions are not the acceptance criteria for a
completed module. Lint also does not replace behavioral simulation.

## B5. Implement the matching ALU behavior

The existing ALU receives op_i, a_i and b_i and computes result_o. EX will
eventually select a resolved register value and an immediate for ADDI, or two
resolved register values for ADD. Operand selection belongs to EX.

Choose whether ALU accepts OP_ADD and OP_ADDI directly or EX normalizes both to
OP_ADD. Accepting both in the ALU is a straightforward initial convention for
this package. Document that choice and use it consistently in EX and tests.

Implement and check these groups incrementally:

1. ADD/ADDI.
2. SUB.
3. AND, OR and XOR.
4. Logical shifts.
5. Arithmetic right shift.
6. Signed and unsigned comparisons.

| Calculation | Expected result |
| --- | --- |
| 7 + 9 | 0x00000010 |
| 0xffffffff + 1 | 0x00000000 |
| 0 − 1 | 0xffffffff |
| Signed comparison of 0x80000000 less than 0 | True |
| Unsigned comparison of 0x80000000 less than 0 | False |

The ALU remains combinational and does not own validity, register writes,
memory requests or retirement. Explicitly control signed interpretation and
shift amount. Complete the arithmetic boundary tests before integrating EX.

## B6. Learn the clocked-state pattern

Read the actual pipe_reg example. For a stateful module, choose meaningful state
fields first, then use this pattern after declaring state_t:

```systemverilog
// Structural template only: declare a meaningful state_t for your module.
state_t state_q, state_d;

always_comb begin
  state_d = state_q;

  // TODO: Output defaults and event calculations.
  // TODO: Selected next-state changes.
  // TODO: Reset and permitted cancellation selection.
end

always_ff @(posedge clk_i) begin
  state_q <= state_d;
end
```

_q means currently stored state; _d means the selected next state. Blocking
assignments compute combinational values. Nonblocking assignments capture state
at the clock edge. The initial state_d=state_q means hold unless another decision
changes a field. Define outputs on all paths as well as state defaults.

A packet transfers only when valid AND ready are true at the rising edge.
An offered packet stays stable while stalled except for an explicitly permitted
cancellation. A valid level lasting several cycles does not mean several transfers.

| Input accepted | Output accepted | Ordinary one-entry buffer action |
| --- | --- | --- |
| No | No | Hold |
| Yes | No | Fill available storage |
| No | Yes | Remove consumed item |
| Yes | Yes | Replace consumed item |

Add reset and cancellation to each module's event table. This buffer table is
not sufficient for the adapter or commit: an external transaction may remain
owned after its request handshake, and a younger flush cannot erase that ownership.

## B7. Build the register file and scoreboard

Implement [regfile.sv](../../rtl/superscalar/regfile.sv) with committed register
storage, eight reads and four accepted commit writes. Check x0 and the selected
reset policy. Duplicate nonzero destinations in a commit bundle violate this
design's single-writer policy; do not silently choose a winner by loop order.

In [register_stage.sv](../../rtl/superscalar/register_stage.sv), keep the control
packet stable and expose the separate live operand sideband. Handle same-edge
commit bypass. DP samples those live operands when R transfers; it later refreshes
its own retained snapshots from commit. These protect two different waiting locations.

Implement [scoreboard.sv](../../rtl/superscalar/scoreboard.sv) as ownership state.
Allocate only on accepted dispatch; release only on accepted commit or valid
recovery of all remaining writers. Forwarding readiness does not release a name.
If same-edge release/reallocation is permitted, the new allocation survives.

**Checkpoint:** hold an instruction waiting to read x5 while an older instruction
commits x5=7. Demonstrate that the waiting consumer receives seven, and that a
second writer cannot acquire x5 before the ownership rules permit it.

## B8. Integrate one lane through the eight stages

Connect the basic path only after the pure functions, storage and operand rules
are understood. Keep the four-lane packet type and mark lanes 1–3 invalid.
Each stage owns its intended register boundary; do not add another pipe_reg
between modules that already own that storage.

```text
IF -> D -> R -> DP -> EX -> MEM -> WB -> C
```

For this arithmetic milestone, MEM preserves ALU results without issuing data
requests. WB holds completed packets. C alone produces architectural writes and
retirement events. Even a limited milestone must make unsupported behavior
explicit and must not be described as a complete CPU.

Use this first integrated instruction sequence:

```text
addi x5, x0, 7
addi x6, x0, 9
add  x7, x5, x6
```

The target is three ordered accepted retirement events with results seven, nine
and sixteen. Trace each instruction's PC, current owner, operands, result and
accepting edge. Introduce stalls at each boundary. Verify that no instruction
disappears or retires twice. This is expected behavior to demonstrate, not a
simulation result already obtained from the shells.

## B9. Add control flow and trap recovery

Implement branch/jump computation in EX, accepted effects in C, and the
trap/report/resume lifecycle in recovery. Integrate the existing control-hazard
unit under its singleton admission contract. Admission and EX acceptance must
be the same edge; avoid the block_younger combinational feedback trap.

Use each instruction's own PC for targets and link values. Hold a branch event
under backpressure and prove its link write cannot happen early. For faults,
retain metadata until recovery accepts it; recovery retains blocking through
EEI report acceptance and explicit resume-PC delivery.

**Checkpoint:** taken and not-taken branches, jumps, alignment faults, delayed
trap acceptance, delayed resume and stale fetch responses all preserve correct
ownership. The fault PC never becomes a handler address by assumption.

## B10. Add serialized memory and fences

Complete loads in MEM, store authorization in C, and single-transaction ownership
in the adapter. Preserve both the original effective byte address and aligned
bus address. Test byte masks, sign extension, alignment faults and response errors.

Separate request offer, request acceptance, response arrival and response
consumption. Once accepted, a request remains owned even if its valid pulse ends.
Stores must be issued exactly once, then retire on successful completion under
the endpoint contract or report an error. A fence's drain includes all accepted
and buffered memory work, not merely request_valid.

**Checkpoint:** delayed handshakes cannot duplicate stores, misroute responses
or falsely report memory idle. Document the endpoint's ordering and failed-store
guarantees before making precise-error claims.

## B11. Enable four-lane dispatch and execution

Use the verified scalar path as the foundation. Dispatch selects the oldest legal
prefix, never arbitrary ready lanes. It checks older producers, busy destinations
and dependencies within the candidate packet. The existing forwarding unit does
not implement same-packet prefix selection for you.

Freeze a selected offer under EX backpressure. Allocate destinations once on
acceptance, retain the unaccepted suffix and compact it without changing PCs.
Map sources as 2*lane for rs1 and 2*lane+1 for rs2. Core packs producers as EX
lanes 3..0, then MEM, WB and C in the same descending lane order.

**Checkpoint:** exercise prefix lengths 0–4, every older/younger dependency
position, x0, unready/faulted producers, partial dispatch and commit refresh of
retained snapshots. Independent four-wide retirement is one test; dependency
and backpressure correctness require separate evidence.

## B12. Finish with full-core verification and reproducible evidence

Compare accepted architectural effects against an independent expectation/model
under a stated ISA and EEI. Match initial state, memory and fault behavior. A
cycle-level pipeline trace and an architectural reference serve different purposes.
Do not skip mismatches merely because a trap occurred.

Record supported instructions, test commands, source revision, actual tool
versions and remaining limitations. Require useful progress under stated response
assumptions as well as absence of wrong effects. Add performance measurements only
after correctness, using defined workloads and intervals.

Whenever you edit source files, regenerate the HTML so its embedded RTL listings
match the repository:

```powershell
python scripts/build_superscalar_docs.py
python scripts/build_superscalar_docs.py --check
```

Use the architecture reference for contracts, the module walkthrough for port
meaning, and the labs for targeted failure cases. Advance only when you can
explain both the normal path and a stalled or canceled path for the current block.

## B13. Keep this build-order checklist beside your editor

| Order | Work | Gate before advancing |
| --- | --- | --- |
| 1 | Decoder and ALU | Independent combinational behavior and boundary tests |
| 2 | Register file and R | x0, commit writes, live values and same-edge bypass |
| 3 | Scoreboard | Exact allocation/release lifetime |
| 4 | Fetch and stage storage | Request ownership and stable packet transfers |
| 5 | One-lane arithmetic integration | Ordered retirement through eight stages |
| 6 | Serialized branches and recovery | Redirect/link/trap/report/resume correctness |
| 7 | Serialized memory and fences | Exact requests, formatting and ordered effects |
| 8 | Four-lane operation | Prefixes, dependencies, compaction and producer wiring |
| 9 | Complete baseline validation | Independent architectural comparison and coverage |

Architectural invariants to retain throughout: C writes registers; WB holds
completions; accepted DP transfer allocates names; forwarding never releases
ownership; younger ready lanes cannot skip an older blocked lane; MEM sends loads;
C authorizes stores; flushing does not erase accepted external transactions.

## B14. Your next coding session

1. Read decoded_t and the rv32_decode ports.
2. Write the expected decoded record for ADDI x5,x0,7.
3. Implement ADDI recognition and immediate construction.
4. Check positive/negative immediates and source-use flags.
5. Implement and test ADD/ADDI arithmetic in the ALU.
6. Record the supported subset and unfinished cases.

That is enough for the first session. Once those results are verified, continue
to the register file, scoreboard and first clocked stage boundaries. Keep each
step small enough that you can explain exactly what changed and which test would
fail if the new behavior were wrong.
