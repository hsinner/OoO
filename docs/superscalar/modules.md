# A guided tour of the actual files

Read a module as a contract: what question it answers, which information it
owns, what event changes its state, and what must remain true when it stalls.
The source appendix below embeds the current repository files verbatim. These
listings are regenerated from the files, so declarations are not hand-copied.

## M1. Shared types: rv32_pkg and hazard_pkg

[rv32_pkg.sv](../../rtl/superscalar/rv32_pkg.sv) defines the language spoken by
the stage interfaces. It is a package, not an instantiated hardware stage.
An enum such as OP_ADD gives a bit pattern a readable internal name. A packed
struct gathers related bits; an array repeats that record for multiple lanes.
Changing a field changes every connected module's contract.

`decoded_t` distinguishes source indices from source-use flags: an immediate's
bits may occupy the rs2 bit positions without naming a real source. Using those
bits as a dependency would create false stalls. `lane_t` carries both decoded
fault information and the accumulated instruction fault. Define the propagation
rule explicitly: later stages must preserve an earlier valid fault.

[hazard_pkg.sv](../../rtl/superscalar/hazard_pkg.sv) separates the consumer query
from the producer description. A source has `used`, `rs`, `busy` and a fallback
value. A producer has validity, destination, value, and separate killed/fault/ready
flags. Ready is about availability; fault is about whether the result is usable;
killed is about whether that instruction still exists. They are not synonyms.

## M2. rv32_decode: translate one word

[rv32_decode.sv](../../rtl/superscalar/rv32_decode.sv) has no clock because it
answers a pure combinational question. The stage using it supplies storage.
Start from a safe illegal result, recognize a legal encoding, then fill the
operation, source-use flags, destination behavior, immediate and serial class.
An opcode selects an instruction family; function fields distinguish members.
Checking only the opcode is insufficient to reject unsupported encodings.

For ADD, both sources matter. For ADDI, only rs1 matters and the other ALU input
comes from an immediate. For a store, rs1 forms the address and rs2 supplies
data, with no integer destination. For LUI, neither source register is used.
These differences affect dependency checking as much as arithmetic.

Begin with a hand-written decode table and explicit expected records for a few
real instruction words. Then extend coverage to every supported family and
boundary. The versioned ISA linked in the architecture reference is the authority
for bit encodings; this module's shell is not an encoding reference.

## M3. alu: a calculation without ownership

[alu.sv](../../rtl/superscalar/alu.sv) computes a value from an operation and two
operands. It should not know whether an instruction is valid, retiring, stalled,
or writing x0. EX chooses operands and decides whether the result is meaningful.
This separation makes the arithmetic easy to test independently.

Treat addition/subtraction as fixed-width arithmetic. Explicitly distinguish
signed comparisons and arithmetic shifts from unsigned comparisons and logical
shifts. A barrel shifter is a combinational network selecting shifted bit
positions; it need not take one clock per bit. Whether that network meets a
future timing target must be measured after synthesis, not assumed here.

Test extreme bit patterns as well as small positive integers. A design that
adds 2+3 correctly can still mishandle a negative comparison or shift by 31.

## M4. fetch: own a request until it is finished

[fetch.sv](../../rtl/superscalar/fetch.sv) connects the instruction port to D.
`request_valid_o` offers an aligned block address; `request_ready_i` accepts it.
`response_valid_i` later offers words and per-word errors; `response_ready_o`
accepts that separate response. Request acceptance does not mean data arrived.

Plan state for the desired PC, offered/accepted request, buffered response,
word offset and stale-response disposition. With only one outstanding request,
there is no need for multiple transaction tags, but ownership still exists.
`outstanding_o` must reflect unfinished instruction-port ownership according to
the implemented contract, not merely the current request-valid pulse.

A redirect may arrive while old-path memory is answering. Accept responsibility
for the new PC, mark the old response for discard, and drain it. Do not interpret
the late response as the first block of the new path. `stop_fetch_i` prevents new
sequential work; it must not prohibit the actions needed to complete recovery.

## M5. decode_stage: four decoders plus one stage boundary

[decode_stage.sv](../../rtl/superscalar/decode_stage.sv) applies per-instruction
decode to the resident packet. It retains original PCs, instruction bits and
lane validity. Invalid lanes must not become fake illegal instructions. A valid
lane already carrying a fetch error must preserve that error.

Its packet handshake is the ordinary pipeline contract: hold a stalled offer,
accept replacement when capacity permits, and cancel younger state on the
appropriate flush. Four combinational decoder instances do not require four
sequential cycles. Nor should you insert another register between each decoder
and this stage's own storage.

## M6. regfile: committed state with many ports

[regfile.sv](../../rtl/superscalar/regfile.sv) is the architectural storage for
x0–x31. Eight read indices select up to eight values simultaneously; four accepted
commit records may write distinct nonzero destinations at an edge. These are
logical ports. A particular FPGA's memory blocks may not directly provide this
combination, so physical implementation is a later platform decision.

Writes to x0 have no effect and reads of x0 return zero. The single-writer rule
should prevent duplicate nonzero destinations in one commit bundle; assert this
instead of silently relying on loop order to select a winner. Define startup
initialization in the implementation/EEI without assuming software can rely on
unspecified register contents.

Read-during-write behavior matters. A consumer accepting its operands on the
same edge as an older commit must receive the new value via explicit bypass
where the R contract requires it. Do not rely on a vendor RAM's accidental
read-first or write-first behavior.

## M7. scoreboard: ownership, not result storage

[scoreboard.sv](../../rtl/superscalar/scoreboard.sv) owns one busy bit per register.
DP supplies allocation events; C supplies release events through accepted writes.
The table contains no arithmetic results. Forwarding becoming ready does not
clear a busy bit, because the instruction still owns its architectural write.

Reason about simultaneous release and allocation. If the design permits a new
writer to take a name on the same edge the old writer commits, the next state
must remain busy for the new owner. A conservative extra stall is also possible,
but must be consistent with DP's admission rule. Never lose a new allocation
because a later assignment clears the same bit.

Recovery may clear ownership only when it has canceled every remaining owner
represented by the bits. The architectural register values themselves survive.
Check busy[0]=0 after every event and compare the table against live writers in
integration tests.

## M8. register_stage: stable indices, live values

[register_stage.sv](../../rtl/superscalar/register_stage.sv) holds the control
packet and drives `read_indices_o`. Source slot 2*lane is rs1; slot 2*lane+1 is
rs2. `read_values_i` returns the selected committed values. Accepted
`commit_writes_i` provide the same-edge bypass information.

`packet_o` must remain stable while stalled. The explicitly separate
`live_operands_o` may change as older instructions commit. DP samples that
sideband only when accepting the packet. This is an intentional exception for
the sideband, not permission to mutate an ordinary stalled packet.

Without this separation, a packet can wait long enough for its producer to
commit and disappear from forwarding, yet still carry an obsolete snapshot.
The pipeline then has no producer to correct the stale value. DP's later commit
refresh solves the same problem for its retained suffix.

## M9. forwarding_unit: resolve eight questions

[forwarding_unit.sv](../../rtl/superscalar/forwarding_unit.sv) is already
implemented. For each source it handles unused/x0 first, establishes the
committed fallback, then scans producers youngest to oldest. `found` prevents
an older match replacing the first match. A first match that is unready or
faulted blocks the source; it does not permit searching for an obsolete value.

`ready_o` says a source value is usable. `forwarded_o` distinguishes an actual
producer match from the fallback/x0 paths. `values_o` is meaningful for execution
only when the relevant source is ready. It is not a dispatch-valid signal.

The module does not inspect dependencies between instructions still in DP.
DP must separately prevent a younger lane reading a destination produced by an
older lane selected in the same cycle. There is no same-cycle chained ALU
forwarding across the four newly dispatched lanes in this starting design.

## M10. dispatch: choose the oldest legal prefix

[dispatch.sv](../../rtl/superscalar/dispatch.sv) holds the waiting suffix,
refreshes snapshots from commit, asks the resolver about older producers, and
walks lanes from oldest to youngest. Stop at the first blocked source, busy
destination, within-packet dependency or unavailable resource. The allowed
selection is a prefix, not a set of arbitrary ready instructions.

For a candidate lane, compare its sources and destination with older lanes
already selected. A dependency on an older selected destination cannot use its
future ALU result yet. A second writer to the same nonzero name cannot share
the packet either. An independent younger lane still waits behind a blocked one.

Once offering a packet to EX, freeze its selected lanes and values until
acceptance. On that edge, pulse `allocate_mask_o`, remove the accepted prefix,
and compact the suffix. Refresh remaining snapshots without changing an already
offered payload. A singleton requires serial admission and EX acceptance at
the same edge; the workbook explains how to avoid the block_younger loop.

## M11. execute: establish result meaning

[execute.sv](../../rtl/superscalar/execute.sv) chooses ALU operands and uses four
ALU instances for ordinary integer lanes. It also handles the one admitted
branch/address operation. A PC-relative calculation must use the owning lane's
PC. Store data comes from the source value, not the computed effective address.

EX establishes result, effective address, store formatting and resolved next-PC
fields as applicable. It detects applicable alignment faults. For a conditional
branch, a target alignment fault is relevant only if the branch is taken. For
a jump, keep link-value computation separate from permission to commit it.

`producers_o` describes resident older instructions in natural lane order.
Arithmetic can be ready, but a load address is not load data. A faulted writer
remains a visible blocking producer. `occupied_o` describes ownership even if
an output is temporarily not offered. The core reorders producer arrays for DP.

## M12. memory_stage: complete loads and retain stores

[memory_stage.sv](../../rtl/superscalar/memory_stage.sv) distinguishes pass-through
ALU work, load transactions and store descriptors. A load needs state recording
whether its request has been accepted. Otherwise a stalled instruction can issue
the same read repeatedly. Some reads may have device effects, so serialization
and exact request ownership matter even when no register result is used.

After response acceptance, select the addressed byte/halfword from the aligned
word and extend it according to the operation. Preserve the original effective
address for faults and trace; the bus-aligned address is a different value.
A response error must become an instruction fault, not a ready zero result.

Stores pass their descriptors onward without sending writes here. MEM must
retain occupancy during a pending load even if `packet_valid_o` is low. Otherwise
the control unit could incorrectly conclude that all older work has drained.

## M13. writeback: a completion buffer

[writeback.sv](../../rtl/superscalar/writeback.sv) holds the packet between MEM
and C and exposes its producers. Its name is historical terminology: this
project's register file is written by C. The WB stage must not allocate or
release a busy name, issue a store, or emit a retirement event.

The difficult cases are consume-and-replace, a stalled downstream, and a flush
with a resident packet. Preserve fault metadata. A packet being complete does
not imply its faulted result is usable for forwarding. Begin its tests with a
downstream stall and verify the whole offered record stays unchanged.

## M14. commit: one place authorizes permanent effects

[commit.sv](../../rtl/superscalar/commit.sv) owns the oldest packet and any cursor
needed for partial retirement. `commit_writes_o` and `retire_o` describe accepted
events, not persistent offers. Repeating them while stalled would count or write
the same instruction again. Trap and branch channels, in contrast, use valid/
ready and retain their records until accepted.

For an ordinary integer lane, authorize the nonzero destination write and trace
together. For a store, send its request once, retain ownership while waiting,
and retire only after success; an error becomes a trap. For a branch/jump, couple
retirement and any link write with the accepted branch event. A fence waits
for the memory completion contract. Successful non-control singletons pulse
`serial_done_o`; branches and faults use recovery instead.

At the first fault, finish only the permitted older prefix and transfer the trap
record to recovery. The faulting instruction is not a normal retirement. There
is intentionally no generic flush input that lets younger control erase this
ordering owner or its accepted store.

## M15. memory_adapter: remember who must receive the answer

[memory_adapter.sv](../../rtl/superscalar/memory_adapter.sv) joins MEM's load
channel and C's store channel onto one abstract external data channel. The
request payload says what to do; retained owner state says where the response
belongs. Ownership lasts until response consumption, not just request acceptance.

For example, if a load request is accepted and the external bus becomes ready
again, this does not authorize a store request: the load still owns the sole
outstanding slot. A buffered response also keeps the adapter non-idle until its
consumer accepts it. Never route by whichever client is requesting this cycle.

Serialization should prevent simultaneous clients. Assert that invariant, and
choose/document defensive arbitration before implementation. The abstract port
is not AXI or a cache. Its ordering, failed-store and reset guarantees must be
met by whatever real environment is selected later.

## M16. control_hazard_unit: one serialized operation and one redirect

[control_hazard_unit.sv](../../rtl/superscalar/control_hazard_unit.sv) is already
implemented. Its state contains serial_busy, redirect_valid and redirect_pc.
It admits a singleton only when the backend is empty and no conflicting control
event/pending redirect exists. Admission blocks younger work in that same cycle.

An accepted branch or trap event flushes the appropriate younger state and
stores a redirect. The redirect is then held until IF accepts responsibility.
Trap wins simultaneous new requests when the redirect slot is empty. An already
pending redirect is not overwritten; the integration must not present a newly
discovered older fault that should have preceded an already committed branch.

This controller's trap input is a restart PC. It has no full trap-record port
and cannot report an exception to the environment or wait for a later response
by itself. Those missing duties belong to recovery, described next.

## M17. recovery: report, wait, then restart

[recovery.sv](../../rtl/superscalar/recovery.sv) must wrap the control unit and
own the longer trap lifecycle. A useful planning sequence is: accept the commit
trap, hold an EEI report, wait for report acceptance, wait for resume, offer the
chosen restart PC, and wait for IF to accept that redirect. These are proposed
state responsibilities, not implemented state encodings.

Keep younger dispatch/fetch blocked throughout, including the interval after C
has handed off the trap but the environment has not supplied a resume PC.
`eei_trap_ready_i` only acknowledges the report. It does not select a handler or
authorize resumption. Accept `resume_pc_i` only at the defined resume handshake.

Older effects must already be settled before removing backend ownership.
If cleanup is deferred until the control unit accepts the eventual trap redirect,
the retained work must remain blocked meanwhile. Never use a flush to abandon
an accepted memory transaction. Tests must delay report, resume and redirect
acceptance independently to expose gaps in this ownership chain.

## M18. core: integration is a correctness task

[core.sv](../../rtl/superscalar/core.sv) must instantiate and connect all of these
blocks. It currently contains ports and TODOs only. The external instruction,
data, trap, resume and retirement interfaces are the proposed system boundary.
They do not provide a reset vector, memory map or privileged environment.

Wire ordinary packet channels forward and capacity information backward. Send
accepted commit writes to RF, scoreboard, R bypass and DP refresh. Pack the
forwarding array as EX[3..0], MEM[3..0], WB[3..0], C[3..0]. Compute backend_empty
from actual ownership in EX/MEM/WB/C and adapter idle; DP itself is excluded.

Review every feedback path for a combinational cycle. Drawing arrows is not
enough: mark which arrows pass through stored state. Finally, run an instruction
stream and compare accepted architectural effects with an independent reference.
Module-level arithmetic tests alone cannot detect a wrongly wired commit path.

## M19. pipe_reg: learn the storage pattern

[pipe_reg.sv](../../examples/superscalar/pipe_reg.sv) is a working generic example,
not another mandatory stage to insert between every pair of modules. `valid_q`
records whether it owns an item; `data_q` stores that item. The ready equation
allows a free slot or replacement of an item accepted downstream.

All decisions, including reset/kill selection, are in always_comb. The always_ff
block only assigns next-state values to current-state registers. When neither
replacement nor kill/reset occurs, defaults retain the old state. When the
consumer accepts and no new item replaces it, valid clears and the old data bits
become irrelevant. This is how a bubble is represented without inventing a NOP.

## M20. Read a cycle table correctly

This illustrative table uses “cycle” to mean the interval when an instruction
resides in a named stage. Transfers happen at the following rising edge. Assume
fetch supplies the required words, all four lanes are independent ALU operations,
and all consumers accept without stalls. A–D name instructions, not stages.

| Cycle | IF | D | R | DP | EX | MEM | WB | C |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | A–D | empty | empty | empty | empty | empty | empty | empty |
| 2 | E–H | A–D | empty | empty | empty | empty | empty | empty |
| 3 | I–L | E–H | A–D | empty | empty | empty | empty | empty |
| 4 | M–P | I–L | E–H | A–D | empty | empty | empty | empty |
| 5 | Q–T | M–P | I–L | E–H | A–D | empty | empty | empty |
| 6 | U–X | Q–T | M–P | I–L | E–H | A–D | empty | empty |
| 7 | Y–AB | U–X | Q–T | M–P | I–L | E–H | A–D | empty |
| 8 | AC–AF | Y–AB | U–X | Q–T | M–P | I–L | E–H | A–D |

The edge after cycle 8 can retire A–D under these assumptions. This is a
pipeline illustration, not a throughput claim for the unimplemented fetch port.
Request/response latency can leave IF empty and change the table immediately.
Do not include memory wait time implicitly in a claimed fixed eight-cycle latency.

If C stops accepting, WB first retains its work. Occupied buffers then propagate
backpressure toward IF. It need not halt every stage on the very first cycle:
empty intermediate slots can still fill. A global stall wire is simpler to draw
but is a different control scheme that must preserve all the same ownership.

## M21. Critical paths and physical cost

A cycle is long enough only if data can propagate through its combinational
logic before the next edge's setup requirement. A critical path is the slowest
such path under the chosen implementation. More stages do not automatically
make a CPU faster if one stage contains nearly all of the difficult decisions.

DP is a likely design challenge: eight source queries compare against sixteen
producer descriptions, then priority selection, prefix eligibility and resource
checks determine an offer. The product 8×16 describes 128 potential source/
producer comparisons, not a measured gate count or delay. The register file's
eight reads/four writes and wide packet routing also have physical costs.

Synthesis maps RTL into cells or FPGA resources; placement/routing determine
actual interconnect; timing analysis checks the clock constraint. No target
device, clock frequency, area or power result is supplied for this skeleton.
Optimize only after correctness, then measure. Adding a pipeline boundary to
fix timing changes latency and forwarding ownership, so update the cycle table
and stage specification together.

## M22. A short vocabulary to keep nearby

| Term | Meaning in this project |
| --- | --- |
| Architectural | Visible in the program's committed register/memory behavior |
| Microarchitecture | The internal stages, storage and scheduling implementing that behavior |
| Resident | Currently owned by a particular stage's storage |
| Offer | Valid payload waiting for the receiving side to accept |
| Fire / acceptance | valid AND ready at the relevant clock edge |
| Backpressure | A receiver's lack of capacity prevents its sender from transferring |
| Prefix | Consecutive oldest lanes up to the first excluded lane |
| Suffix | Remaining younger lanes after removing a prefix |
| RAW | A reader needs an older writer's result |
| WAW | Two instructions want to write the same register name |
| WAR | A younger write must not change an older instruction's required input |
| Structural hazard | Two operations need a resource that cannot serve both |
| Serialize | Drain older backend work, run one operation, block younger dispatch until completion/recovery |
| Retire / commit | Accept the instruction's permanent architectural effects in order |
| Precise trap | Older effects are complete and faulting/younger normal effects are absent |
| EEI | Execution environment interface: platform rules outside the base instruction semantics |
| Elaboration | Resolve modules, parameters and types; not evidence of correct execution |

When debugging, write down a specific instruction PC, its current owner, its
validity and the edge event you expect. This turns “the pipeline is broken”
into a checkable question such as “why did PC 0x108 allocate x7 twice while EX
was stalled?” Keep a separate list of observed results and design intentions.
