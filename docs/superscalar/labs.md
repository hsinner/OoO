# Laboratory workbook: build, observe, explain

These assignments guide you through completing the skeleton yourself. They
are not claims that the modules or tests already exist. Each lab names a task,
an expected reasoning checkpoint, and a bug your evidence should catch. Keep
decisions in always_comb and only state assignments in always_ff.

## L1. Establish an engineering notebook

Create your own ownership diagram, memory/EEI assumptions, supported-instruction
matrix and unfinished-behavior list. Record Git revision and actual tool versions
with results. Keep illustrative calculations separate from measured traces.

The repository provides these checks from its root:

```powershell
python scripts/build_superscalar_docs.py --check
wsl -d Ubuntu -- bash scripts/check_skeleton.sh
wsl -d Ubuntu -- bash scripts/check_hazards.sh
```

The first checks documentation, the second elaborates intentionally empty
interfaces, and the third checks implemented hazard units. None executes the
unfinished CPU. They require the corresponding local tools; record environment
details rather than assuming another machine has them.

**Deliverable:** an evidence table separating implemented, elaborated, simulated,
formally checked and integrated behavior. **Checkpoint:** explain why successful
elaboration cannot establish reset behavior, x0 semantics or store ordering.

## L2. Explain one storage slot

Read examples/superscalar/pipe_reg.sv. Draw occupied, input-valid, output-ready,
input-fire and output-fire over cycles covering fill, hold, replace, drain,
reset and kill. Use recognizable payloads A/B to expose loss and duplication.

Choose state first, then default retention, event decisions and reset/kill
override in always_comb. Only copy next state into registers in always_ff.
A full slot can accept B on the same edge A leaves. A stalled A stays unchanged.
After consumption without replacement, valid clears and old data becomes irrelevant.

**Deliverable:** an annotated waveform or paper trace. **Bug to expose:** clearing
valid when ready is low loses A. This lab teaches a buffer, not a complete stage
with external memory ownership.

## L3. Write the decoder matrix before RTL

Files: rv32_pkg.sv and rv32_decode.sv. For every supported operation, list encoding
constraints, immediate format, used sources, destination behavior and serial
classification. Include legal instructions with rd=x0. Derive fields from actual
words, not only assembly labels.

Start with 0x00700293: ADDI x5,x0,7. Expect rs1=0, rd=5, immediate=7,
uses_rs1 set and uses_rs2 clear. Add negative immediates and shift boundaries.
Unsupported encodings follow the documented illegal policy; defined hints and
reserved fields must obey their specific ISA rules.

FENCE has fields base implementations must ignore or treat conservatively.
Do not reject every nonzero reserved-looking field. Use the linked specification.
**Deliverable:** independent expected records. **Bug to expose:** marking ADDI's
rs2 field used, creating a false dependency on immediate bits.

## L4. Test the ALU at boundaries

File: alu.sv. Separate the pure function from EX ownership. Exercise wraparound,
signed/unsigned comparisons, both right shifts, left shifts and bitwise functions.
EX must not treat an arbitrary result for an unsupported internal operation as
a valid instruction result.

| Exercise | Expected 32-bit result |
| --- | --- |
| ADD 0xffffffff, 1 | 0x00000000 |
| SUB 0, 1 | 0xffffffff |
| Signed less-than 0x80000000, 0 | 1 |
| Unsigned less-than 0x80000000, 0 | 0 |
| Logical right shift 0x80000000 by 31 | 1 |
| Arithmetic right shift 0x80000000 by 31 | 0xffffffff |

**Checkpoint:** explain how the same input bits yield different comparisons.
**Bug to expose:** using an unsigned expression for arithmetic right shift.
Do not copy the implementation's exact expression into every expected-value
calculation; that can reproduce the same mistake on both sides of a test.

## L5. Register reads during commit

Files: regfile.sv and register_stage.sv. Establish eight-read/four-write mapping,
x0 behavior, and documented reset behavior for other entries. Exercise distinct
simultaneous writes and reject duplicate nonzero destinations under this policy.

Hold an R packet reading x5 while an older instruction commits x5=7. The control
packet stays stable; live_operands reflects the accepted value. If R transfers
on the same edge, bypass must supply seven. DP then owns its snapshot and must
refresh retained work on later commits.

**Deliverable:** indices, live sideband, commit record and accepted DP operands
in one trace. **Bug to expose:** consuming stale packet.src1 instead of sampling
live_operands. Repeat with x0 to prove writes cannot change zero.

## L6. Scoreboard lifetime

File: scoreboard.sv. Allocate x5 on accepted dispatch. Hold its result ready for
forwarding before commit: busy[5] remains set. Release at accepted commit. Test
simultaneous release/allocation according to your chosen admission policy.

Hold EX not-ready and confirm repeated valid offers do not allocate new owners.
Recovery clears only canceled ownership, while architectural values survive.
**Checkpoint:** readiness describes a value; the busy bit owns a name.
**Bug to expose:** clearing on forwarding admits a second writer too early.
Once stages exist, compare busy state with actual live writers.

## L7. Prefixes, compaction and forwarding

Files: dispatch.sv, forwarding_unit.sv and core.sv. Cover four independent lanes,
every within-packet dependency position, busy destinations, and unready/faulted
older producers. Preserve the resolver's youngest-first producer order.

Use A=ADDI x5,x0,7, B=ADDI x6,x0,9, C=ADD x7,x5,x6 and independent D.
The first prefix can contain A/B. Retained C/D preserve their PCs. D cannot pass
a blocked C. Freeze every already offered prefix while EX is not-ready.

**Deliverable:** accepted lengths 0–4 and exact per-instruction allocation counts.
**Bugs to expose:** growing a stalled offer, allocating twice on compaction,
or using the wrong lane's source slot. A standalone forwarding pass does not
verify DP's separate same-packet dependency checks.

## L8. Fetch under redirection

File: fetch.sv. Exercise all four initial word offsets. Delay request acceptance
and response delivery separately. Redirect before acceptance, after acceptance,
with buffered data and while D stalls. Define cancellation for unaccepted offers;
accepted transactions retain ownership until drained.

stop_fetch must not prevent redirect acceptance or stale-response disposal.
Attach per-word errors to the correct PC. **Deliverable:** cycle-by-cycle owners
and emitted PCs. **Bug to expose:** clearing pending ownership on flush and
mistaking the late old response for new-path instructions. Demonstrate progress
without requiring instantaneous memory responses.

## L9. One arithmetic lane through eight stages

Files: decode_stage.sv, execute.sv, writeback.sv, commit.sv and core.sv with the
previous path. Keep lanes 1–3 invalid for this milestone and preserve eight
logical boundaries. Do not duplicate each stage's storage with another pipe_reg.

For ADDI x5,x0,7; ADDI x6,x0,9; ADD x7,x5,x6, accepted ordered results must
be seven, nine and sixteen. This is an assignment target, not a recorded CPU
simulation. Introduce stalls at each boundary and exercise replacement.

**Deliverable:** strict checks for completed modules, stage ownership traces
and independent retirement comparison. **Bug to expose:** writing the RF at WB
and again at C. Correct always-ready execution is insufficient evidence.

## L10. Loads and adapter ownership

Files: memory_stage.sv and memory_adapter.sv. Initialize distinct bytes and test
each width/sign interpretation. Misaligned halfword/word operations trap before
issuing under this project's policy. Errored responses must not forward success.

Delay request acceptance, response arrival and consumption independently. Count
fires, not valid cycles. Retain client identity even if requester inputs change.
Remain non-idle while a request, transaction or buffered response is owned.

**Deliverable:** request/response/retirement counts reconciled after draining.
**Bug to expose:** equating request_valid==0 with idle, allowing admission while
an older response is still pending.

## L11. Stores and fences

Files: commit.sv and memory_adapter.sv. Verify MEM only prepares descriptors.
C authorizes a store, holds its request until acceptance and waits for response.
Delay completion and prove the same store is not reissued. Exercise masks and
errors under the explicitly chosen endpoint contract.

Place a fence between memory operations. Include accepted-but-unanswered and
buffered-response work in the drain condition. For a posted-write endpoint,
identify what acknowledgement actually guarantees before claiming completion.

**Deliverable:** ordered request, response and retirement records plus endpoint
assumptions. **Bug to expose:** an externally visible store before C authorizes
it. A pipeline flush cannot serve as a fictional memory undo mechanism.

## L12. Branches, traps and resume

Files: execute.sv, commit.sv, recovery.sv and control_hazard_unit.sv. Start with
existing standalone controller tests, then test integration. Singleton admission
and EX transfer must be the same edge, without a block_younger feedback loop.

Check branch outcomes and jumps with each owning lane's PC. Stall branch-event
acceptance and confirm no early link write. Test older trap priority. Independently
stall commit-to-recovery, EEI report, resume and redirect acceptance.

**Checkpoint:** report acceptance does not provide a handler or authorize resume.
**Bugs to expose:** substituting fault PC for restart PC or unblocking younger
work between report delivery and resume. Preserve external transaction ownership
through every cancellation.

## L13. Widen and challenge each lane

Expand verified arithmetic to four lanes. Cover all packet prefix lengths and
older/younger dependency pairs. Check eight sources and sixteen producers,
including reversal within each stage for youngest-first forwarding.

Test generalized commit-prefix behavior with an allowed older prefix and later
fault, even if ordinary serialization makes that packet uncommon. Repeat stalled
partial dispatch and retirement. Trace ordering is program age, not completion
timing.

**Deliverable:** lane-position coverage and accepted effects. **Bug to expose:**
correct lane 0 behavior with lane 2 reading lane 3's source. Scalar correctness
does not establish superscalar wiring correctness.

## L14. Architectural comparison and progress

Align ISA options, initial state, memory and EEI before comparing to a reference.
Compare ordered retirement effects and separate trap events. Do not compare
speculative intermediates as architectural state. A chosen framework may need
more trace fields; our custom retire bundle is not automatically RVFI.

Exercise bounded response delays. Formal liveness requires fairness assumptions:
a core may correctly wait forever if memory never responds. A core that never
retires may avoid wrong retirement trivially, so require useful progress too.

**Deliverable:** reproduction commands, inputs/seeds where applicable, coverage
and limitations. **Bug to expose:** a checker that silently skips mismatches
after a trap instead of preserving a defined architectural stream.

## L15. Optional frontend and cache experiments

After baseline completion, choose a predictor or cache experiment from the
course. Start with a paper trace or algorithm model, then specify its integration
contract before RTL. This is future work, not a substitute implemented in a shell.

For prediction, record lookup index/history, prediction, outcome and training.
Reproduce C7's counter trace and specify recovery. For a cache, derive tag/index/
offset, reproduce C18's calculation and draw miss/evict/refill events.

**Deliverable:** capacity, timing assumptions and invariants. **Bugs to expose:**
training under changed live history or installing a refill under a newer request's
tag. Measure usefulness only after ownership works.

## L16. Optional rename, issue and memory experiments

Extend C23's rename trace with a branch between A and B; cancel B. Identify
surviving mappings and exactly reclaimed allocations. Distinguish a surviving
late result from a canceled result to a reused destination.

Use C24's issue entries to schedule ready work while drawing ROB retirement
separately. Add a load that executes before an older store address is known.
If a conflict appears, identify the incorrect value and every architectural
effect that must be prevented. Define replay before writing queue logic.

**Deliverable:** complete state traces. **Checkpoint:** renaming removes name
conflicts, not RAW dependencies; a ROB orders retirement but does not detect
memory dependence; an LSQ does not replace branch recovery.

## L17. Graduation rubric

Mark each item absent, partial or reproducibly demonstrated. A high performance
score cannot compensate for a failed correctness property.

| Area | Required evidence |
| --- | --- |
| ISA | Supported encodings, exact results and EEI |
| State | Owner and accepting edge for each lasting effect |
| Flow | Stable offers, replacement, compaction and exact acceptance |
| Dependencies | No stale operands, duplicate writers or wrong producer choice |
| Memory | Byte/aligned addresses and complete transaction lifetime |
| Recovery | No wrong-path commit, lost request or invented restart PC |
| RTL | Assignment-only always_ff, complete defaults and strict checks |
| Verification | Independent expectations and meaningful stress cases |
| Performance | Stated workloads, intervals and real measurements |
| Reproducibility | Revision, tools, commands, assumptions and limitations |

Explain one arithmetic dependency, load, store and trap from fetch to final
accepted outcome. If you cannot name a value's owner during a stall, return
to that module's lab. The result should be a processor you can reason about
and debug, not merely a set of plausible module names.
