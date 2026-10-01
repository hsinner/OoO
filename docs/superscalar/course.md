# Course: from a four-wide pipeline to modern CPU design

This course extends the beginner guide and module walkthroughs. Its practical
project is still the eight-stage, four-wide, in-order RV32I processor. The
advanced lessons are architectural study and optional future projects; they
do not change the current RTL contract or complete any skeleton for you.

“Modern” is not a checklist that every processor must implement. Different
processors trade performance, energy, area, latency and verification cost
differently. This course covers the major relevant design families and their
interfaces; it does not claim exhaustive coverage of every research algorithm
or undocumented commercial implementation. Public documentation is used as
evidence for named examples, not as proof that every configuration uses them.

## C1. Your syllabus and what completion means

Study one unit at a time. Before coding, draw its state and edge events. After
coding, demonstrate a failure-sensitive test: deliberately introducing the bug
the test targets should make that test fail. A module is complete only when
its behavior, integration contract and validation agree.

| Unit | Read and build | Completion evidence |
| --- | --- | --- |
| Foundations | C2–C4; types and elastic storage | Explain cycle ownership and all simultaneous events |
| Frontend | C5–C9; fetch and decode | Fetch/redirect tests and exact decode records |
| Operand path | C10–C13; RF, scoreboard, R, DP, bypass | Correct values under dependencies, stalls and compaction |
| Execution | C14–C15; EX and WB | Correct calculations and no lost/duplicated completion |
| Memory | C16–C20; MEM and adapter | Exact requests, formatting, fault and ownership behavior |
| Retirement | C21–C22; C and recovery | Precise effects, accepted traps and controlled restart |
| Advanced OoO study | C23–C25 | Paper designs for rename, issue and ROB recovery |
| Systems and measurement | C26–C29 | Explicit platform boundary and reproducible evidence |
| Capstone | C30 and the lab workbook | Integrated baseline with independent retirement comparison |

The course supplies explanation and assignments, not finished assignment RTL.
Use the existing beginner examples when a term feels unfamiliar. Do not start
the advanced track by inserting a predictor or rename table into the current
core: first identify every contract it would invalidate.

### Find the architecture lesson for your module

| Repository block | Build now | Study next | Lessons / labs |
| --- | --- | --- | --- |
| rv32_pkg, hazard_pkg | Typed ownership and validity contracts | Sequence tags, prediction and physical-register metadata | C3, C25 / L1 |
| pipe_reg | One-entry elastic storage | Skid buffers and credits | C4 / L2 |
| fetch | Aligned block requests, ordered PCs, stale drain | Fetch queues, BTB, RAS and direction predictors | C5–C8 / L8, L15 |
| rv32_decode | Complete supported encoding matrix | Micro-ops and fusion | C9 / L3 |
| decode_stage | Four ordered decodes, fault preservation | Predecode and decoded-op caches | C9 / L3, L9 |
| regfile | Committed eight-read/four-write interface | Banking, replication and physical registers | C10, C23 / L5, L16 |
| register_stage | Stable control and live operand sideband | Operand read after scheduling | C10, C25 / L5 |
| scoreboard | One writer per nonzero architectural name | Rich scoreboards and rename readiness | C11, C23 / L6 |
| dispatch | Frozen oldest prefix and retained suffix | Resource allocation and issue queues | C12, C24 / L7, L16 |
| forwarding_unit | Youngest older producer resolution | Restricted/clustered bypass and wakeup | C13, C24 / L7 |
| alu | RV32 integer functions | Adder/shifter topology and added execution classes | C14 / L4 |
| execute | Four ALUs, singleton branch/address | Pipelined/iterative and tagged completion | C14–C15 / L9 |
| memory_stage | Serialized load and store descriptor | LSQ, forwarding, disambiguation and replay | C16–C17 / L10, L16 |
| memory_adapter | One outstanding owner | Nonblocking caches, MSHRs and system interfaces | C16, C18–C20 / L10, L15 |
| writeback | Stable ordered completion holding | Result arbitration and PRF writes | C15, C21 / L9 |
| commit | Architectural prefix and authorized stores | ROB retirement and committed maps | C21, C23 / L11, L13 |
| control_hazard_unit | Serialized admission and held redirects | Branch resolution with younger-work cancellation | C6, C22 / L12 |
| recovery | Trap/report/resume lifecycle | Checkpoints, histories and speculative-state recovery | C22–C25 / L12, L16 |
| core | Wiring, capacity and ownership invariants | Translation, coherence, SMT and physical integration | C25–C30 / L9, L13–L17 |

Each advanced column is a design alternative or extension. It is not a TODO
to add all mechanisms simultaneously. The matching module walkthrough gives
the current ports; these lessons explain what an extension would change.

## C2. Scalar, superscalar, in-order and out-of-order are separate choices

A scalar implementation starts at most one instruction per cycle at the chosen
issue boundary. Superscalar widens that opportunity. In-order issue preserves
program order when choosing work; out-of-order issue lets a ready younger
instruction execute while an older instruction waits. Neither width nor issue
order alone determines how many instructions retire each cycle.

Our DP chooses an oldest legal prefix. Consider A waiting for x5, followed by
independent B and C. The baseline holds all three. An OoO scheduler could select
B/C, but would need to retain A, track results by identity, preserve correct
register versions and still handle an earlier fault precisely. A ready-bit
check with permission to skip A does not provide those other mechanisms.

| Architecture family | Scheduling mechanism | Consequence for this project |
| --- | --- | --- |
| Scalar in-order | One oldest instruction | Useful first integration milestone |
| Superscalar in-order | Oldest executable group | Our four-wide target |
| OoO superscalar | Ready instruction selection from a window | Needs new scheduling and retirement machinery |
| VLIW | Compiler places operations in explicit issue groups | Different software/ISA contract; not obtained by widening RV32I |
| SIMD/vector | One operation addresses multiple data elements | Different kind of parallelism; not four scalar lanes |
| SMT | Several hardware threads share execution resources | Needs separate architectural contexts and scheduling policy |

Exercise: explain why four ALUs are insufficient to guarantee four-wide issue.
Expected reasoning includes input bandwidth, dependencies, issue eligibility,
memory/control serialization, downstream capacity and retirement bandwidth.

## C3. Work backwards from architectural effects

The baseline's fundamental rule is that C owns architectural changes. Build a
table of every possible effect before designing datapaths: integer write,
store, next-PC decision, trap report and retirement event. For each, name the
accepting edge and the owner that retains it while waiting.

For example, a store has at least three different moments: EX computes its
descriptor, the external interface accepts its C-authorized request, and the
endpoint returns completion. The memory endpoint may change state before the
processor observes completion. Therefore precise store errors require the
documented endpoint guarantee; a trap cannot undo an arbitrary device effect.

A computation can be speculative without its result being committed. The
baseline mostly avoids that complexity through serialization. In an extended
design, speculation means an assumption permits work before certainty. Each
assumption needs a check, a recovery boundary and a list of effects it is allowed
to cause. “Flush on error” is not a complete specification.

Exercise: for each field in packet_t, label it input fact, derived value,
prediction, exception or accepted event. The current packet contains no prediction
metadata. A future predictor therefore requires a deliberate interface revision.

## C4. Elastic stages, buffers and credit flow

Implement the one-entry storage pattern before implementing eight stages.
Inventory the four combinations of input acceptance and output acceptance:
hold, fill, empty, replace. Add reset and legal cancellation. The next-state
equations must describe all combinations without inferring a latch.

```text
Planning pseudocode for an ordinary one-entry buffer:
next = current
if output accepted: next.valid = false
if input accepted:  next.payload = input; next.valid = true
if reset or authorized kill: next.valid = false
```

This ordering is appropriate for the example buffer, not a universal state
machine. C and the adapter have externally owned transactions that cannot be
discarded by an ordinary younger-work kill. Keep decisions in always_comb;
always_ff contains only assignments from selected next state.

A combinational ready chain can run from C back toward IF. It is logically
convenient but may become a timing problem. A skid buffer provides extra holding
capacity when backpressure takes time to propagate. A credit protocol instead
tracks available receiver slots; sending consumes a credit, returning capacity
restores one. Both need explicit capacity accounting and reset coordination.

Optional design exercise: insert a registered control boundary on paper. If one
extra item can arrive before the sender observes stop, where is that item stored?
If you cannot name a slot, merely registering ready loses data. Document whether
the added buffer changes the eight-stage latency or only provides elasticity.

## C5. Fetch bandwidth, alignment and queues

Files: fetch.sv, rv32_pkg.sv and core.sv. The baseline requests a 16-byte aligned
block and permits one outstanding instruction request. The PC chooses the first
useful word. PCs at offsets 0, 4, 8 and 12 initially expose four, three, two and
one useful words respectively. Each emitted lane keeps its own PC and error bit.

Plan separate state for an offered request, an accepted transaction and a
buffered response. Do not overwrite an unaccepted request address. If a redirect
cancels an offer, define the cancellation rule explicitly; an already accepted
request still has to be drained. Stale responses are discarded by ownership,
not by guessing whether their data looks like an instruction.

A fetch queue decouples memory delivery from decode consumption. It smooths
bursts but cannot create average bandwidth. If a deliberately hypothetical port
delivers four useful instructions every four cycles, its average ceiling is one
instruction per cycle before branches and other losses. Four decoder lanes do
not remove that limit.

BOOM's documented frontend uses a fetch buffer to decouple fetch from decode,
and carries instruction-boundary concerns for compressed instructions. Our
base-only design has fixed four-byte instruction boundaries; adding C changes
alignment, cross-block assembly and fault attribution. See the
[BOOM fetch description](https://docs.boom-core.org/en/latest/sections/instruction-fetch-stage.html).

Lab question: redirect after request acceptance, delay its response, and hold D
not-ready. Identify who owns the old transaction, new PC and any buffered words.
The answer must not require memory to cancel an accepted request magically.

## C6. Branch prediction: direction and target are different questions

Baseline: serialize control flow and redirect at commit. Optional prediction
tries to keep fetch busy before a branch is resolved. A direction predictor
estimates taken/not-taken. A branch target buffer, or BTB, caches target/type
information indexed by fetch address. A return-address stack, or RAS, predicts
returns by matching the nesting pattern of calls and returns. None supplies
architectural truth; execution checks the actual outcome and target.

BOOM documents a fast next-line predictor containing a BTB, direction information
and RAS support. That is a useful concrete decomposition, not a required topology
for this project. See [BOOM next-line prediction](https://docs.boom-core.org/en/latest/sections/branch-prediction/nl-predictor.html).

For a first experimental predictor, write down these records: lookup PC, predicted
next PC, predicted branch lane, valid/type, update PC and actual next PC. Add a
token connecting the prediction to the instruction that will check it. If a
packet contains multiple control transfers, the earliest predicted taken one
determines which later lanes belong to the selected path.

Example: lanes at 0x100, 0x104, 0x108, 0x10c include a predicted-taken branch at
0x104. Do not dispatch 0x108/0x10c as its fall-through path while fetching the
target as though both were one ordered stream. Preserve prediction metadata
until resolution and test both correct and incorrect direction/target cases.

Do not remove baseline serialization just to make a predictor appear useful.
First specify age-based cancellation, wrong-path memory restrictions and recovery.
Prediction is a frontend feature whose correctness obligations span the core.

## C7. Direction algorithms: counters, history and TAGE

A two-bit saturating counter has four confidence states. For a teaching design,
predict taken for states 2/3; increment toward 3 on taken and decrement toward 0
on not-taken. One unusual outcome does not flip a strongly held prediction.
Aliasing occurs when distinct branch PCs share the same entry.

Global history records recent branch outcomes. Gshare combines PC bits with
history using XOR to index counters. TAGE uses tagged tables with different
history lengths; longer matching histories can supply a prediction while a
base/alternate prediction remains available. Tags reduce false matches; usefulness
state helps manage replacement. These families and their history recovery are
described in [BOOM backing prediction](https://docs.boom-core.org/en/latest/sections/branch-prediction/backing-predictor.html).

For your counter exercise, initialize state 1 and process T,T,N,T,N,N:

| Step | State before | Prediction | Actual | State after |
| --- | --- | --- | --- | --- |
| 1 | 1 | N | T | 2 |
| 2 | 2 | T | T | 3 |
| 3 | 3 | T | N | 2 |
| 4 | 2 | T | T | 3 |
| 5 | 3 | T | N | 2 |
| 6 | 2 | T | N | 1 |

This trace has four wrong predictions. It is an arithmetic exercise, not a
benchmark. Repeat with a different initial state before drawing conclusions.

Before any history-based RTL experiment, define when history shifts, when tables
train and how wrong-path history is restored. Keep lookup-time metadata for the
eventual update; indexing with whatever history exists at resolution can train
the wrong entry. Compare policies using identical traces, storage accounting,
warmup rules and a stated misprediction metric.

## C8. Perceptrons, hybrid prediction and prediction cost

A perceptron predictor represents history outcomes as −1/+1. It computes a
weighted sum including a bias, predicts from its sign, and adjusts weights
when wrong or insufficiently confident. It can learn some long-history
correlations with storage growing linearly with history length, but a single
perceptron cannot represent every pattern. The original algorithm and training
rules are in [Jiménez and Lin's paper](https://www.cs.utexas.edu/~lin/papers/hpca01.pdf).

Try a toy arithmetic example: bias=1, weights=[2,−1], history=[+1,−1]. The sum
is 1+2+1=4, predicting taken when nonnegative. That calculation explains the
datapath; it is not a selected hardware configuration. Bound weight widths,
define saturation and account for adder depth before attempting RTL.

A hybrid combines predictors or uses a chooser/corrector. Its extra lookup,
training and recovery state must earn its cost. A more accurate answer arriving
too late may still waste fetch cycles. Measure wrong-path instructions, redirect
latency and lookup timing alongside accuracy. Indirect branches may require
target-history prediction rather than only a better conditional-direction table.

Study assignment: write a one-page comparison of a PC counter table, gshare,
TAGE and a perceptron. For each, name what is indexed, what is stored, how it
predicts, how it trains and what must be restored on a wrong path. Select one
simple future experiment; do not combine every family into the first core.

## C9. Decode, predecode, micro-ops and fusion

Files: rv32_decode.sv and decode_stage.sv. Begin with a legal-encoding matrix,
then immediate assembly, source-use flags and serialized class. Each valid lane
receives one decoded record. Preserve an earlier fetch fault rather than decoding
untrusted instruction bits into a new competing cause.

Predecode moves some classification closer to fetch, such as identifying possible
control flow. It can shorten a later decision path but produces metadata that
must stay associated with the correct bytes. The full decoder still establishes
the supported instruction's meaning and legality.

A micro-op is an implementation's internal work item. It need not correspond
one-to-one with an ISA instruction. Splitting one instruction into multiple
micro-ops needs shared identity and precise exception/retirement handling. Fusion
combines suitable work internally while preserving the original software effects.
A decoded-op cache stores reusable decoded work; it additionally needs tags,
validity and an instruction-coherence policy. These are optional design families,
not hidden features of our packet_t.

For this course's baseline, retain one RV32I instruction per lane. Exercise:
compare ADD, ADDI, LUI, SW and BEQ. For each, list source fields actually used,
destination behavior, immediate interpretation and special treatment. Then
explain why instruction bits in the rs2 position do not always name a dependency.

When adding extensions later, revisit fetch alignment, decode legality, internal
operation width, exception reporting and tests together. Accepting new opcodes
without implementing their full execution contract does not add ISA support.

## C10. Architectural and physical register files

Files: regfile.sv and register_stage.sv. The current file stores committed x0–x31.
Its logical interface has eight reads and four commit writes. Same-edge writes
must be visible through the specified bypass path when R transfers operands.
Do not rely on simulator statement order or a device's unspecified RAM behavior.

An explicitly renamed OoO design instead uses physical register identities for
different versions of a software register. BOOM documents a physical register
file with bypass networks and provisioned read/write ports. Those requirements
depend on execution resources; they are not simply “twice the ISA register count.”
See [BOOM register files and bypass](https://docs.boom-core.org/en/latest/sections/reg-file-bypass-network.html).

For a future physical design, compare three choices on paper. A fully multiported
file offers broad access at routing/storage cost. Banking divides storage into
groups with fewer ports but creates conflicts. Replication can provide more
reads, but accepted writes must update every copy consistently. Clustering keeps
values near selected execution units and makes cross-cluster communication
explicit. None is a free replacement for the current logical interface.

Exercise: assign eight read indices to two hypothetical banks using index bit
zero. Count conflicts if each bank has two read ports. Explain how DP or a later
read stage would stall/replay without dropping instructions. This identifies an
interface change before choosing a physical register-file implementation.

## C11. Scoreboarding and its exact limits

File: scoreboard.sv. Our table is deliberately small: a busy bit means one
dispatched writer owns a future architectural update. Source readiness is
resolved separately using forwarding. At most one writer per nonzero name is
allowed, so a single bit can identify whether that name remains owned.

The word scoreboard also describes richer designs that track instruction
completion, functional resources or multiple entries. Do not transfer claims
about such a scoreboard to our busy vector. The OpenHW CV32A65X design documents
a scoreboard/commit organization that is useful for comparison; it is not the
same module or the same width as this repository. See the
[OpenHW design document](https://docs.openhwgroup.org/projects/cva6-user-manual/04_cv32a65x/design/design.html).

Write the current allocation/release equation before implementation. If release
and allocation of the same name are allowed on one edge, the new owner survives.
Then ensure DP uses the matching policy: accepting a new owner with an equation
that clears the bit creates an invisible writer. A conservative delay is valid
if consistently specified; an inconsistent same-edge shortcut is not.

Exercise: A writes x5, B reads x5, C writes x5. Mark the first edge each can
dispatch under the baseline, assuming A can forward before commit. B may use
forwarding while busy[5] remains set. C must wait for name ownership, not merely
for the value to become available. This explains why renaming can improve a
different design without being required to make this one correct.

## C12. Dispatch: a greedy prefix algorithm

File: dispatch.sv. A candidate instruction must satisfy source availability,
destination ownership, within-packet dependence rules and resource capacity.
Walk oldest to youngest and stop at the first failure. This is a greedy prefix
selection algorithm: accepting a younger ready lane after that failure is a
different scheduling policy.

```text
Planning pseudocode, not completed RTL:
selected = empty
for lane from oldest to youngest:
    if lane is invalid: stop
    if source unresolved or destination busy: stop
    if depends on destination in selected: stop
    if destination duplicates selected destination: stop
    if serial/resource rule prevents admission: stop
    append lane to selected
freeze selected payload when offering it to EX
allocate destinations only on accepted transfer
retain and compact the unaccepted suffix
```

Use the current R live-operand sideband only on accepted R-to-DP transfer.
Maintain retained snapshots with accepted commit writes. These two protections
cover different waiting locations. When an offer is stalled at EX, it must not
expand or change values because another source later becomes ready.

A reservation station or issue queue would allow instructions to wait individually
after resource allocation. That requires identities, readiness tracking, fair
selection and cancellation beyond this algorithm. C24 studies it separately.

Exercise: A writes x5; B is independent; C reads x5; D is independent. With no
older hazards, the first prefix is A/B. C blocks D in that cycle. Trace the
retained PCs after compaction and show that every allocation occurs exactly once.

## C13. Forwarding networks and load-use timing

File: forwarding_unit.sv; producer descriptions come from EX/MEM/WB/C. The
implemented resolver scans youngest matching older producer first. An unready
or faulted match blocks the source. Selecting an older ready match would return
the wrong version. Killed writers are absent; x0 and unused operands need no
producer value.

The priority multiplexer is only part of the timing path. Include destination
comparison, validity checks, source selection and DP prefix decisions. A fully
connected network can become expensive as producer and consumer counts grow.
A restricted network reduces connections but requires stalls when a value has
no available route. Additional bypass registers add latency and require changes
to the resident-producer/consumer timing model.

For a hypothetical nonserialized load-use experiment, a load's EX address is
not its value. A consumer must wait until MEM has accepted usable data, unless
the design explicitly predicts availability and implements replay. The current
serialized memory policy prevents younger dispatch until the load completes;
therefore a standalone resolver test does not demonstrate integrated load-use
throughput.

Exercise: draw the path from a resident EX ADD through its value multiplexer to
DP's frozen next offer. Then remove the register separating incoming DP from
resident EX on the drawing. Explain the resulting self-dependency/logic-loop
risk. Only use resident older operations as forwarding producers.

## C14. ALUs, address units and variable-latency execution

Files: alu.sv and execute.sv. The baseline supports integer arithmetic/logic,
comparisons and shifts, plus singleton branch/address calculation. Use narrow,
explicit control choices: operation class chooses operands; operation chooses
the function; validity/fault rules choose whether the result is usable.

A ripple-carry adder propagates carry across successive bits. Carry-lookahead
and parallel-prefix families combine generate/propagate information to shorten
logical carry depth at different wiring/area costs. A logarithmic barrel shifter
can select shifts of 1, 2, 4, 8 and 16 positions. Writing '+' or a shift in RTL
allows synthesis mapping; it does not prove which physical topology was selected.

Pipelined units may accept new work before prior results finish. Iterative units
reuse hardware and often accept less frequently. Latency and initiation interval
are distinct. A future multiplier/divider requires the M extension and new
functional tests; it is not part of RV32I. Variable-latency completion also needs
an owner/tag and arbitration if multiple results arrive together. BOOM's
[execution documentation](https://docs.boom-core.org/en/latest/sections/execution-stages.html)
illustrates functional units, execution ports and kill handling.

Exercise: suppose a future unit has latency four and initiation interval one.
Draw four overlapping operations. Then compare an iterative unit with both
values four. Explain what storage distinguishes their owners and what happens
when an older trap cancels a result that returns later. No such unit is added
to the baseline by this lesson.

## C15. Completion, writeback arbitration and retirement bandwidth

File: writeback.sv. In this design WB holds ordered completed packets, forwards
usable results and waits for C. It does not write architectural registers.
Keep output stability, consume/replace and fault preservation as its central
properties. Do not turn a valid resident instruction into multiple completions
just because C is stalled for several cycles.

In a more decoupled design, results from independent units can collide at a
limited number of write ports. Arbitration chooses which transfers are accepted;
the others need holding space or a protocol guaranteeing they cannot collide.
Fixed latency does not eliminate collisions when different units have different
latencies. Plan admission, result buffering and fairness together.

Example design exercise: two hypothetical units complete on the same edge, but
there is one result port. Give each result a valid flag and immutable identity.
Select one; retain the other. Now introduce a kill affecting only the retained
one. Your design must discard it without allowing its tag to wake consumers.
If it can be retried, distinguish retrying a transfer from recomputing an
instruction with side effects.

Four-wide execution with one-wide commit can accumulate pressure even when all
operations are independent. Conversely, four commit lanes cannot retire past
an oldest unfinished operation. Measure retirement, not just ALU activity, when
describing useful throughput.

## C16. Load/store formatting and ownership

Files: memory_stage.sv, memory_adapter.sv and commit.sv. For the baseline, loads
are sent from MEM, stores only from C, and the adapter owns one transaction.
Separate the original byte address from the aligned bus address. Byte offset
selects where data belongs; operation width selects how many bytes; signedness
selects extension after extraction.

Example: SB of 0xaa to byte address 0x201 uses aligned address 0x200, byte mask
0010 and write data 0x0000aa00. A load response word 0xa1b2c3d4 at 0x200 gives
LBU at 0x201 the result 0x000000c3. These are little-endian examples from our
selected interface contract. Check misaligned halfword/word accesses before
sending transactions, according to the baseline's trapping policy.

Track offered request, accepted request and buffered response separately. A
ready external request port does not imply the sole outstanding slot is free.
Response ownership survives a request-valid pulse ending. Do not route a
response to whichever client happens to be requesting now.

Lab: delay every handshake independently. Count accepted requests, accepted
responses and retired memory instructions. Explain differences while work is
pending, then reconcile them after draining. Inject a response error and confirm
the instruction traps rather than forwarding fabricated successful data.

## C17. Store buffers, load queues and memory dependence

A future store queue retains address, data, age and commit permission separately.
A load queue tracks issued loads so ordering violations can be detected. A
younger load may need data from the youngest older overlapping store. Unknown
older store addresses create a choice: wait conservatively or speculate and
recover if a conflict is later discovered. BOOM documents load/store queues,
store-to-load forwarding and memory-order recovery in its
[LSU description](https://docs.boom-core.org/en/latest/sections/load-store-unit.html).

Byte overlap is the useful exercise here. Suppose older S1 stores four bytes
at 0x200, then S2 stores one byte at 0x201, and L loads the four bytes at 0x200.
The newest older provider for byte 1 is S2, while S1 supplies the other bytes.
A design can merge byte providers or conservatively delay this load; it cannot
forward all four bytes from S1 after ignoring S2. Unready store data is different
from an unknown store address, and both need explicit handling.

A dependence predictor guesses which loads should wait for stores. A store-set
family associates historically conflicting loads and stores so later executions
can be ordered. That guess may improve scheduling, but actual address checks
and replay are still needed for correctness. Do not treat a predictor miss as
permission to retire a wrong value. The original
[store-set paper](https://people.eecs.berkeley.edu/~kubitron/cs252/handouts/papers/p142-chrysos.pdf)
explains learning dependence sets and using them to constrain scheduling.

This is an advanced redesign: the baseline serializes memory and has no LSQ.
Before implementing it, revise exception ownership, completion identity, request
capacity and replay scope. A speculative load to side-effecting MMIO is not
equivalent to a harmless cacheable-memory lookup.

## C18. Caches: tags, data and misses

A cache stores copies of memory blocks near the core. Divide an address into
block offset, set index and tag. The selected set contains candidate ways;
valid tags determine a hit, and offset selects bytes within the matching line.
A miss needs a refill and possibly eviction of modified data. Instruction and
data caches can have separate ports, capacity and policies.

For a hypothetical 4 KiB, two-way cache with 32-byte lines, there are 64 sets:
4096/(2×32)=64. Offset uses five bits, index six, leaving 21 tag bits for a
32-bit physical address. At 0x12a4, offset is 4, index is 21 and tag is 2.
These dimensions are a calculation exercise, not selected repository parameters.

A blocking cache waits for its current miss before servicing more work. A
nonblocking cache tracks misses in miss-status holding registers, or MSHRs;
requests for the same line may merge under the controller's rules. gem5's
[classic cache documentation](https://www.gem5.org/documentation/general_docs/memory_system/classic_caches/)
provides an inspectable example with MSHRs and a write buffer.

For your first optional cache assignment, draw miss allocation, refill receipt,
tag/data installation and requester response as separate events. Test the case
where the requester was canceled but an accepted refill still arrives. Never
install a wrong line because the current request address has already changed.
Adding a cache also requires deciding which addresses are cacheable and how
instruction modifications become visible; those are platform contracts.

## C19. Replacement, writes and prefetching

Replacement selects a victim when a set is full. LRU tracks recent use;
tree-PLRU approximates recency using tree bits; random selection reduces recency
state. RRIP assigns a prediction of how far away reuse is and preferentially
evicts lines predicted to be reused late. gem5 documents these policy families
and update operations in its [replacement guide](https://www.gem5.org/documentation/general_docs/memory_system/replacement_policies/).

Write-through propagates writes onward; write-back permits dirty cached data
until eviction/cleaning. Write-allocate fetches or allocates a missing line for
a store; no-write-allocate sends the miss onward under its chosen policy. Match
store completion and fence behavior to the selected path. “Data reached L1”
does not automatically describe visibility to all required observers.

Prefetching predicts future accesses. Next-line prefetching requests a nearby
line; a stride mechanism remembers address differences for a stream or load PC
and predicts repeated steps. Confidence and throttling help avoid wasting
bandwidth. See the inspectable [gem5 stride prefetcher](https://doxygen.gem5.org/develop/stride_8hh.html).

Exercise: with two ways and addresses mapping to the same set, compare traces
A,B,A,C and A,B,C,A. Record hits, fills and evictions before debating a policy.
For prefetching, count useful, late and unused requests separately. Account for
pollution: a useless prefetched line can evict useful demand data. Do not prefetch
device accesses or cross permission boundaries without an explicit system policy.

## C20. Memory ordering and coherence solve different problems

Coherence coordinates copies of an individual memory location across caches.
Consistency defines allowed observations across memory operations. A machine
can have coherent caches while permitting some cross-address reorderings.
FENCE orders specified memory and I/O operation classes; it is not simply an
instruction that invalidates every cache. The baseline conservatively drains
memory, relying on the endpoint's documented completion guarantees. See the
[RV32I ordering specification](https://docs.riscv.org/reference/isa/unpriv/rv32.html).

MESI names Modified, Exclusive, Shared and Invalid permissions/states. A writer
must obtain suitable ownership; other copies may need invalidation before the
write is considered ordered. Requests and acknowledgements require transient
states in addition to the four familiar letters. The
[gem5 MESI example](https://www.gem5.org/documentation/general_docs/ruby/MESI_Two_Level/)
shows an implemented protocol organization.

For an optional two-agent paper exercise, let both cache a shared line and then
let one request a write. List who holds copies, which messages revoke permission,
and when the writer may proceed. Now delay an acknowledgement. Four enum values
alone cannot express the outstanding ownership transition.

The current core has no coherent cache subsystem, atomics or multicore platform.
Treat coherence as a system extension. Even single-core integration must account
for DMA or devices if they share memory. Do not label every cached result
globally visible without defining the relevant observers and completion rules.

## C21. Commit, ROBs and precise exceptions

File: commit.sv. The baseline's in-order packet progression keeps completions
ordered, so C can retire a legal oldest prefix. At a fault, only already permitted
older effects remain; the faulting lane does not retire normally and younger
effects do not become architectural. Branch/link acceptance and store ownership
must obey the separate event rules in the workbook.

An OoO reorder buffer allocates entries in program order and marks them complete
as results arrive. Retirement examines the head, so a ready younger entry cannot
pass an unfinished older one. Entries retain identity and exception information;
some designs store result data there, while explicit physical-register designs
store values elsewhere. BOOM describes a banked ROB and oldest exception handling
in its [ROB documentation](https://docs.boom-core.org/en/latest/sections/reorder-buffer.html).

Paper exercise: allocate A,B,C,D; let D, B and C finish in that order while A
waits. The completion order is D/B/C, but the retirement prefix is empty. When
A finishes successfully, eligible entries may retire up to commit width. If A
instead faults, none of B/C/D may become architectural. This is why readiness
alone is not a retirement policy.

For ring storage, define head, tail, occupancy and wrap behavior. A reused slot
must not accept a late result belonging to its previous owner. Slot index alone
can be insufficient; generation/identity and cancellation protocols need review.

## C22. Recovery, checkpoints and transient execution

Files: recovery.sv and control_hazard_unit.sv. The current controller handles
qualified redirect events. Recovery must hold a trap report, wait for the EEI
to accept it, wait for an explicit resume PC, and retain blocking until restart
ownership is transferred. The faulting PC is not an invented handler address.

A speculative extension needs a definition of younger work: sequence identity,
branch masks or another unambiguous age mechanism. A checkpoint may retain
rename mappings, history and allocation information. Recovery must cancel
queued instructions, suppress late completions, restore speculative state and
drain irrevocable transactions under their protocol.

Build a recovery ledger with one row per structure: pipeline packet, predictor
history, rename map, free list, issue slot, ROB entry, LSQ entry and external
request. For each, choose restore, invalidate, retain or drain. Explain why that
action cannot erase an older accepted effect. A single global clear bit is
rarely an adequate description after speculation is introduced.

Architectural rollback does not necessarily remove microarchitectural traces
such as cache or predictor changes. Therefore precise exceptions alone are not
a security-isolation proof. An advanced design must specify permissions before
side effects, which operations may speculate, and any isolation/partitioning
requirements. This is an additional design review, not a claim that the current
unfinished core has a particular exploit or mitigation.

Exercise: a canceled load response arrives after its queue slot was reused.
Explain how identity checking prevents both an incorrect register write and
an incorrect wakeup. Then identify the remaining external request owner.

## C23. Renaming: give each value a distinct identity

This is an advanced replacement for busy-name ownership, not a missing baseline
module. A speculative rename map translates architectural names to physical
registers. A free list supplies a fresh destination. The instruction retains
the replaced destination identity so retirement can eventually reclaim it.
Within a wide rename bundle, older mapping changes must be visible to younger
source lookups. BOOM explains this explicit-renaming design, free lists and
recovery in its [rename documentation](https://docs.boom-core.org/en/latest/sections/rename-stage.html).

Work this original trace by hand. Initially x5→p5 and x6→p6; p32 and p33 are
free. A is ADDI x5,x5,1. It reads p5, allocates p32 and changes x5→p32. B is
ADD x6,x5,x6. It must read p32 and p6, then allocate p33 and change x6→p33.
Reading B's x5 from the map before A's update would select the wrong version.

Keep A's old destination p5 and B's old destination p6 with their retirement
records. Do not immediately free a replaced mapping at rename: an older reader
may still require that value. Do not free A's newly allocated p32 when A commits;
it remains the committed/current value until a later replacement makes it stale.

Your exercise deliverable is a map/free-list/ROB table after rename, completion,
commit and branch recovery. Include a canceled allocation and prove it is
reclaimed exactly once. Replacing our regfile with a larger array without these
ownership rules is not register renaming.

## C24. Tomasulo-style scheduling, wakeup and selection

Tomasulo-style scheduling associates pending work with producer identities,
allowing consumers to wait for tagged results instead of blocking an entire
in-order pipeline. Contemporary designs often separate physical renaming,
issue queues and ordered retirement. This describes a family of mechanisms;
it does not imply a particular implementation uses one literal shared bus.

An issue entry needs operation/identity, source tags, readiness and resource
class. Wakeup marks matching operands ready; selection grants compatible ready
entries to available ports. Static priority is simple but can disadvantage some
entries; age preference helps prioritize older work. Fast wakeup predicts a
known-latency result's availability, while uncertain-latency work needs a later
readiness event. See [BOOM issue queues](https://docs.boom-core.org/en/latest/sections/issue-units.html).

Exercise: entries A needs p10, B needs ready p11/p12, C needs A's future p13.
Choose B when A waits. When p10 arrives, A can issue; C still waits for p13.
Now give B and A only one compatible port. Selection must grant at most one
instruction per port and at most one port per instruction, unless an explicit
multi-part operation says otherwise.

Speculative wakeup creates a recovery obligation if the promised result does
not arrive. Retaining/replaying dependents is different from merely clearing
their ready bits after they have already executed. Before adding it, define
which descendants retry and how stores or architectural effects remain protected.

## C25. Connecting the advanced machine without pretending it is eight stages

The advanced design might look like this conceptual flow:

```text
Predict / Fetch -> Decode -> Rename -> Dispatch into queues
                                     |          |
                                     v          v
                              ROB allocation   Issue / operand read
                                     ^          |
                                     |          v
                                  completion <- Execute / LSU
                                     |
                                ordered commit
```

That is a different architecture from IF→D→R→DP→EX→MEM→WB→C. In particular,
physical operand read may happen after scheduling, and completion may arrive
out of order. The names dispatch, issue and writeback must be redefined rather
than stretched to hide extra storage and ownership boundaries.

An advanced instruction's minimum journey needs a stable identity connecting
rename allocation, issue entry, result, exception, memory operation and ROB
completion. Allocate resources atomically or specify rollback when allocation
partially fails. An instruction cannot own a physical destination but disappear
because the ROB was full after the free-list allocation occurred.

Exercise: draw admission when ROB has space, issue queue has space, but no free
physical destination remains. Then reverse the constrained resource. In both
cases, prove there is no leaked allocation and no half-admitted instruction.
For wide dispatch, decide whether an accepted prefix is allowed and how younger
mapping updates are withheld for the unaccepted suffix.

Only start this optional capstone after baseline verification. Preserve its
separate manifest and documentation so baseline results remain reproducible.

## C26. Translation, privilege, interrupts and extensions

The existing external EEI does not implement privilege. A future operating-system
platform needs architectural trap state, privilege transitions, permission checks,
interrupt handling and the appropriate return/fence instructions. These are ISA
extensions/platform commitments, not extra flags on an existing fault record.

Address translation maps virtual pages to physical pages. A TLB caches mappings
and permissions; a miss may require a page-table walk. A cached mapping is not
valid forever: address-space changes and translation fences must participate
in invalidation. Use the ratified
[RISC-V privileged specification](https://docs.riscv.org/reference/isa/priv/supervisor.html)
as the authority when selecting a translation mode and permission behavior.

For a paper extension, label each address in fetch/LSU as virtual or physical.
State where permissions are checked, which address is reported on each fault,
and who owns a page walk when the requesting instruction is canceled. A cache
hit cannot excuse a failed permission check. Keep translation misses distinct
from data-cache misses in both state machines and performance counters.

Extension planning also changes width and state: RV64 widens relevant integer
semantics; M adds multiply/divide; A adds atomic operations; C changes instruction
length; floating-point and vector extensions add architectural state and exception
rules. SMT duplicates per-thread architectural/rename/recovery context while
sharing selected resources. These are follow-on projects, not baseline milestones.

## C27. Verification is a hierarchy of different evidence

First verify pure functions such as decode/ALU. Then verify stateful contracts:
retained offers, exact acceptance counts, reset, flush and ownership. Next test
interacting modules and finally compare the ordered architectural effects of
the full machine against an independent model.

An ISA model such as [Spike](https://github.com/riscv-software-src/riscv-isa-sim)
models architectural execution; it does not validate this pipeline's cycle
timing. Align ISA options, initial state, memory map and trap behavior before
comparison. Compare retired effects, not arbitrary intermediate register writes.
Explain any deliberate environment difference rather than hiding it in a matcher.

Formal verification checks properties over modeled behaviors under explicit
assumptions. RVFI is a defined observation interface; the current retire_bundle_t
is not automatically RVFI-compatible. Review the actual
[RVFI specification](https://github.com/YosysHQ/riscv-formal/blob/main/docs/source/rvfi.rst)
before building a wrapper or making a formal-coverage claim.

| Property | Useful evidence | What it does not establish alone |
| --- | --- | --- |
| Decoder meaning | Expected records for legal/illegal families | Pipeline ordering |
| Stable output under stall | Directed test/assertion excluding allowed cancellation | Correct instruction result |
| Exactly-once request | Acceptance counters and owner checks | Endpoint ordering guarantees |
| Precise commit | Fault-prefix and independent architectural comparison | Physical timing closure |
| Liveness | Progress under explicitly fair response assumptions | Progress when memory never responds |

Exercise: list assumptions in a testbench that could hide bugs. Examples include
always-ready receivers, immediate memory responses and never placing dependencies
in lane 3. Replace each with a deliberate stress case when behavior exists.

## C28. Measure bottlenecks before optimizing

Record retired instructions, cycles and elapsed measurement interval. IPC is
retired instructions/cycles; CPI is cycles/retired instructions for a nonempty
interval. Report clock frequency separately. A design with higher IPC can still
run a workload slower if its clock period grows enough.

For a hypothetical four-wide ideal path retiring 400 instructions in 100 cycles,
IPC is 4. Add 100 unoverlapped stall cycles and IPC becomes 2. Real stalls can
overlap, so adding raw “stall reason” counters is not necessarily total delay.
Define exclusive categories or report overlaps explicitly.

Separate useful measurements: empty frontend, blocked oldest source, destination
busy, singleton drain, memory wait, commit backpressure and wrong-path work in
an advanced design. Count accepted events instead of valid levels when measuring
work. A request held valid for five cycles is still one request if accepted once.

Design experiment: compare width one, two and four using the same program and
environment. Report instruction count, cycles, stalls and, when available,
synthesized timing/area. Do not claim four times the performance from four ALUs.
Use dependent arithmetic, independent arithmetic, branches and memory streams
as distinct workload classes. No performance result is supplied for this skeleton.

## C29. RTL to implementation: synthesis, timing, power and reproducibility

Synthesis interprets RTL and maps it into implementation resources. Place/route
adds physical wiring; timing analysis evaluates constrained paths. A simulator's
zero-delay combinational calculation does not demonstrate that a design meets
a clock period. Select a target technology and constraints before making frequency,
area or power claims.

For this project, inspect likely long paths: EX forwarding through DP selection,
multiport RF/bypass logic, packet-wide prefix checks and ready propagation.
An optimization that breaks a path with storage changes cycle ownership and may
add latency. Update diagrams, forwarding tables and tests alongside that edit.

Clock enables express when state need not update; physical clock gating requires
appropriate technology support and a glitch-safe flow. Do not construct a gated
clock with arbitrary combinational logic. Reset distribution, clock-domain
crossings and endpoint reset ownership need separate review if a future bus or
memory controller uses another clock. The current simple synchronous shell is
not evidence that those system concerns are already solved.

Keep tool versions, source revision, target, constraints, commands and reports
with measured results. Use independent manifests for the historical OoO experiment
and active superscalar design. The permissive skeleton elaboration command is
only for shells; completed modules need strict checks and behavioral evidence.

## C30. Your two capstones and advancement gates

**Baseline capstone:** complete one lane through all eight stages, then add
serialized control/memory/traps, then widen arithmetic and test every prefix
length. Integrate the existing hazard units under their contracts. Deliver the
RTL, supported-instruction matrix, environment specification, reproducible tests,
waveform explanations and honest limitations. Passing source elaboration alone
does not finish any behavioral milestone.

**Advanced capstone:** choose one extension based on a measured bottleneck.
Examples are a fetch queue, a blocking cache, a predictor with recovery, or a
separate renamed OoO experiment. Describe the old and new contracts before
coding. A new mechanism must preserve architectural results while adding its
own recovery and resource-accounting tests.

| Proposed improvement | Prerequisite you must explain | New evidence required |
| --- | --- | --- |
| Fetch queue | Accepted fetch ownership and ordered PCs | Capacity, redirects and stale responses |
| Prediction | Instruction age and cancellation | Wrong direction/target and recovery stalls |
| Cache | Endpoint and cacheability contract | Hits, misses, evictions, errors and cancellation |
| Nonserialized loads | Completion identity and ordered effects | Dependencies, forwarding and precise faults |
| Renamed OoO | Maps, free list, issue, ROB and memory policy | No leaks, stale wakeups or wrong-path commit |
| Multicore | Shared-memory contract and coherence | Ownership races and ordering tests |

Read the next lab workbook as your practical checklist. Each lab asks for a
concrete artifact and a checkable outcome. Its expected reasoning is provided
without filling in your SystemVerilog implementation.
