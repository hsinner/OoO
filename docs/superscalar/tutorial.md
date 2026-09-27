# Building a four-wide, eight-stage RV32I processor

Design revision: 2026-09-27. This is the active design tutorial. The target is a
four-wide **in-order superscalar** processor. The previous OoO backend remains
historical work; it does not implement this architecture.

## 1. Define the machine before writing RTL

The pipeline has exactly these eight logical stages:

```text
IF → D → R → DP → EX → MEM → WB → C

IF   Instruction fetch     D    Decode
R    Register access       DP   Dispatch and hazard checks
EX   Execute              MEM  Memory processing
WB   Writeback holding    C    Architectural commit
```

Four-wide means up to four suitable instructions can advance, execute and retire
per cycle. It does not mean every cycle performs four instructions. A packet
contains individually ordered instructions; it is not one atomic architectural
operation. Eight stages describe logical work and register boundaries, not a
guarantee of eight-cycle completion under stalls.

Use the following initial policies. They are our design choices, not ISA rules.

| Property | Starting design |
| --- | --- |
| Ordering | In-order dispatch, pipeline progression, memory effects and commit |
| Width | Four lanes; implement one lane first using all eight stages |
| Execution | Four integer ALUs; one shared branch/address datapath |
| Register file | Committed 32×32 storage, up to eight reads and four writes |
| Hazards | Busy-bit scoreboard; no EX/MEM/WB forwarding initially |
| Register writers | At most one dispatched writer per nonzero architectural register |
| Memory | One load/store unit; one outstanding data transaction |
| Special operations | Loads, stores, control flow, fences and trap-producing operations serialize |
| Speculation | No predicted branches, no out-of-order scheduler, no register renaming |
| Architectural updates | Register changes and store authorization occur at commit |

Serialization means an operation waits for older backend work to drain, issues
alone, and blocks younger dispatch until it commits or traps. This simplifies
the first implementation substantially. Independent ALU packets still execute
four-wide; memory-heavy code will be much slower until later optimizations.

## 2. RV32I and the execution environment

The ISA target includes all 40 base instructions:

| Group | Instructions |
| --- | --- |
| Upper immediate | LUI, AUIPC |
| Register arithmetic | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| Immediate arithmetic | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| Conditional branches | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Jumps | JAL, JALR |
| Loads | LB, LH, LW, LBU, LHU |
| Stores | SB, SH, SW |
| Ordering/environment | FENCE, ECALL, EBREAK |

CSR operations and FENCE.I are separate extensions. Multiplication, compressed
instructions, atomics, floating point and vectors are also outside this initial
scope. Consult the [versioned RV32I specification](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
for encodings and semantics. A four-wide microarchitecture does not change them.

Choose a little-endian execution environment for the first implementation. Trap
misaligned halfword/word data accesses before issuing their transactions. Treat
unsupported/reserved encodings as illegal-instruction events by project policy.
Do not invent a production reset PC, memory map, bus or FPGA target: make those
integration choices explicit before implementing their adapters.

Initially expose an external trap interface with PC, instruction, cause and
relevant fault address. A simulator monitor may terminate execution or supply a
restart PC after pipeline state is cleared. ECALL and EBREAK generate distinct
events. This boundary is an execution-environment design, not machine-mode CSR,
interrupt, MRET or OS support. Full CPU validation must include this contract.

## 3. The important distinction: writeback versus commit

If a younger ADD writes x5 before an older load reports a fault, the machine
cannot present precise architectural state without an undo mechanism. Naming
a later stage commit does not make an early register-file write safe.

Here WB stores completed results and metadata in an ordered holding register.
C makes architectural register updates, emits retirement events, and authorizes
stores. EX and MEM compute results but do not modify the architectural register
file. Consumers initially wait until the producer commits.

There is no general reorder buffer or out-of-order issue queue. Ordered elastic
pipeline registers retain packets; a stalled older packet prevents younger
packets from passing it. A four-entry WB packet register is enough to hold its
results until C can accept them. Any future variable-latency unit that allows
completion to bypass older work requires revisiting this ordering mechanism.

## 4. Packets and per-instruction metadata

Carry metadata for every instruction, not just a shared packet PC.

| Field | Purpose |
| --- | --- |
| valid, pc, instruction | Identity, ordering and fault attribution |
| rs1, rs2, rd and use/write flags | Accurate hazard checks and register effects |
| operation, immediate, class | Decode result and resource requirements |
| src1_value, src2_value | R supplies read values; DP captures and refreshes internal snapshots |
| result, address, store_data, byte_mask | Execution and memory effects |
| redirect_valid, redirect_pc | EX computes; C authorizes control-flow change |
| exception_valid, cause, fault_address | Fault record retained until ordered handling |
| optional trace sequence | Verification identity, not a rename tag |

Lane 0 is oldest. Compact valid lanes toward it. With lane 0 as the low bit,
legal masks are 0000, 0001, 0011, 0111 and 1111. A valid mask with holes needs
compaction before admission; physical slot numbers must not distort program age.

If only two lanes dispatch, retain the other two with their original PCs and
compact them to lanes 0 and 1. Never redispatch consumed lanes. The first DP
buffer can refuse a new input packet while a suffix remains, accepting a bubble
rather than adding complex same-cycle suffix refill and merge behavior.

## 5. Instruction fetch

IF owns the fetch PC, request state, response buffer and access-error metadata.
Four 32-bit instructions need 16 useful bytes per cycle for sustained width.
A narrower instruction interface still works but becomes a throughput limit.

A four-byte-aligned PC is not necessarily 16-byte aligned. At address 0x...0C,
one aligned 16-byte block contains only one instruction at or after the PC.
Emit that instruction, then fetch the next block. A later instruction buffer
can combine adjacent responses. Do not silently round the PC down and execute
the three earlier words.

Start with one outstanding fetch request. Hold request valid/address until
accepted; then wait for a response. Buffer that response when D stalls. Never
assume a fixed memory latency or increment request state without a handshake.

A redirect can arrive while an old request is outstanding. Mark that request
discard-on-return, drain its response, then request the pending redirect PC.
With one request this is easier than generation tags. A future multi-request
frontend needs identities and cancellation generations that cannot alias live
responses. Reset must coordinate with the endpoint or drain old transactions.

Restrict instruction fetch to executable side-effect-free memory. Associate
fetch errors with the affected PC. If the external response gives only a block
error rather than per-word status, document how the adapter attributes it;
do not attach one arbitrary error PC to all four lanes.

## 6. Decode

Instantiate a single-instruction decoder four times. Extract opcode, function
fields, register names, source-use flags, immediate, instruction class and legal
encoding status. Validate the complete encoding so an unsupported instruction
does not accidentally execute as an ADD.

Not every apparent register field is a source. LUI reads no register, AUIPC
uses its own PC, immediate arithmetic does not read rs2, and a store really
does read rs2. Reads of x0 return zero. A destination of x0 suppresses a register
write but does not suppress a load's access or its faults.

These bit-concatenation sketches help test immediate extraction independently:

```systemverilog
imm_i = {{20{insn[31]}}, insn[31:20]};
imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
imm_u = {insn[31:12], 12'b0};
imm_j = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
```

Record decode faults rather than raising them immediately. Older valid lanes
must still be allowed to commit. Classify faulting instructions as serialized
operations at DP for the initial design.

## 7. Register access and stale operands

R reads the committed register file. Four two-source instructions require eight
logical reads; four-wide commit requires up to four writes. A small flip-flop
array is an understandable first implementation. An FPGA block RAM does not
magically acquire this number of ports from a convenient RTL array declaration.

A read value is a snapshot. An older instruction can commit while a packet
waits, leaving a stored operand stale even after its busy bit clears. This is
an important consequence of placing register access before dispatch.

Keep the R register-index/control packet stable while stalled, but read the
register file continuously using those indices. Treat these live read values
as an operand-acquisition sideband, not part of the held handshake payload.
DP samples them only on an accepted R-to-DP transfer. A commit while R waits
naturally changes the values eventually sampled. This internal sideband is
not an AXI-style stable-data transaction.

DP then owns operand snapshots. For each used source in its held packet,
compare accepted commit destinations and refresh matching values. Apply the
commit bypass to incoming read values on the transfer edge too, covering a
same-edge register write/read collision. Only accepted nonfaulting commit
writes refresh operands; x0 always resolves to zero. Refresh is internal DP
state maintenance, not a transfer to EX. DP exposes EX valid only once selected
operands are ready and cannot change through an older pending writer.

Initially allow a one-cycle delay after readiness changes. If commit at edge E
updates the source and clears busy state, DP sees both new values during the
next cycle and dispatches at E+1. Do not bypass newly cleared readiness in the
same cycle without also supplying the corresponding new operand value.

## 8. Dispatch: accept an oldest prefix

DP checks instructions from oldest to youngest and stops at the first blocked
lane. It never searches past a stalled instruction for independent younger work.
That is the defining in-order scheduling policy here.

```text
selected = 0
destinations_selected_this_cycle = empty
for each lane, oldest first:
    if invalid: stop
    if serialized: apply singleton/drain rule, then stop
    if a used nonzero source is busy: stop
    if its written nonzero destination is busy: stop
    if a source matches an earlier selected destination: stop  # RAW
    if destination matches an earlier selected destination: stop  # WAW
    if EX has no room for the packet: stop
    select the lane and remember its nonzero written destination
```

Resource reservation is atomic with actual dispatch. Set busy bits only when
instructions transfer to EX, not when decoded or tentatively selected. Clear
busy bits on accepted commit writes. If a later optimized design clears and
allocates the same bit in one cycle, allocation must win. The initial design
simply waits a cycle before reusing the destination.

An ALU prefix before a serialized operation may dispatch first. Retain the
serialized instruction and its suffix until EX, MEM, WB and C are empty of
older work. Dispatch it alone to lane 0 and inhibit all younger dispatch until
its commit/trap completes. This applies to data accesses, branches, jumps,
fences and environment/faulting instructions.

## 9. RAW, WAW and WAR examples

RAW is a read that needs an older write's result. WAW is two writers to the
same name. WAR is a younger write that follows an older read of that name.

```text
lane 0: add x5,  x1, x2
lane 1: sub x6,  x3, x4
lane 2: xor x7,  x5, x8
lane 3: and x9, x10, x11
```

With no earlier hazards, lanes 0 and 1 dispatch. Lane 2 needs lane 0's result,
so lane 3 also waits despite being independent. When x5 commits and the retained
operand refreshes, old lanes 2 and 3 can dispatch together as the new prefix.

```text
lane 0: addi x5, x0, 1
lane 1: addi x5, x0, 2
lane 2: add  x6, x5, x7
```

The first writer dispatches alone. The second waits for its commit, then the
consumer waits for the second writer. A single busy bit works because multiple
dispatched writers to the same nonzero register are forbidden. Removing that
rule requires counts or explicit producer ownership, not just another bypass.

WAR needs no extra stall when the older instruction's operands are already
captured: `add x6,x5,x1` and `addi x5,x0,7` may dispatch together when otherwise
ready. The older read is safe before the younger write commits. If the older
reader is blocked, prefix selection prevents the younger writer from passing.

## 10. Execute

EX contains four parallel integer ALU datapaths. Each valid lane computes one
operation. Arithmetic results are 32 bits. Signed comparisons and arithmetic
right shifts require explicit signed interpretation; shifts use the proper
amount bits. Keep the decoder and ALU independently testable.

A shared target/address datapath serves serialized instructions routed to
lane 0. EX computes effective address, store data, branch condition, target
and link result. It records locally detectable exceptions without committing
them. An ALU packet passes through MEM with no memory request; it does not
skip the ordered pipeline or pass an older packet.

When MEM cannot accept, hold the EX packet stable. An occupied stage may consume
and replace its packet on one edge only when the valid/ready protocol permits.
Completion of combinational arithmetic alone is not a transfer event.

## 11. Memory and the adapter contract

MEM issues load requests and waits for responses. Data operations are serialized,
so no older data access is outstanding and no younger instruction has issued.
This is a conservative starting point for both ordinary memory and device reads.

Define a request channel with valid/ready, address, write flag, write data and
byte strobes, plus a response channel with valid/ready, read data and error.
One outstanding transaction needs no multi-entry response ID, but the adapter
must still track request acceptance separately from response completion.

For an aligned 32-bit little-endian word bus, retain the original low address
bits locally. A byte store shifts its data by eight times the byte offset and
sets one strobe; a halfword sets two adjacent strobes; a word sets four. Loads
extract the addressed bytes and sign- or zero-extend. Trap misaligned halfword
and word accesses before sending a request. If the selected bus instead takes
byte addresses, document that convention explicitly at its boundary.

Do not resend an accepted request simply because the response is delayed.
Buffer the response if downstream stalls. Attach access errors to the original
instruction PC and effective address. Loading into x0 still performs the access
and reports errors even though its register result is discarded.

MEM does not send stores. It validates and packages their address/data/mask,
then passes the descriptor through WB to C. C sends the authorized store through
the shared adapter. This backward control connection is intentional: logical
instruction stages do not forbid control signals between nonadjacent blocks.

## 12. Writeback holding

WB captures result packets, destination flags, PCs, exception records and
store/control descriptors. It exposes valid/ready to C. It neither writes
architectural registers nor clears scoreboard bits. While C waits, WB holds
its packet and backpressure propagates toward EX.

Calling it result writeback means writing completed values into this holding
register. Document that interpretation in the RTL. Later forwarding may use
WB values, but the first implementation waits for commit.

Transfer whole packets from WB into a C packet register. C then owns partial
retirement and retains any suffix until finished. WB cannot overwrite C's
remaining lanes. This avoids adding partial-transfer semantics to every earlier
stage boundary.

## 13. Commit, faults and store authorization

C accepts up to four oldest completed ordinary instructions. Each accepted
nonzero register destination updates the committed file and clears its busy bit.
Emit one retirement event per instruction; the trace must agree with state
updates exactly, not one cycle before or after a stalled commit.

For an exception in lane k, only lanes before k may retire. Wait for those
older effects to complete, report the trap separately, and discard lane k and
younger work. The serialized-special policy normally makes faulting operations
singletons, but keeping the per-lane rule explicit prevents incorrect packet-
wide retirement. Recovery also clears any busy state owned by discarded work.

A store singleton first checks local exceptions, then authorizes one adapter
request. Set a `store_sent` flag on request acceptance. Keep the instruction
pending until response; on success retire it, and on failure report its fault.
Never issue a second request because C or the trace consumer is stalled.

Precise store errors require a platform contract: a failed store must not have
already produced partially visible effects. A bus with late imprecise write
errors needs a separately documented policy; clearing valid cannot undo an
external write. Once a store is authorized and outstanding, do not flush it
or reset only the core while losing track of the transaction.

The simplest retirement trace is passive and always observed. If it uses
ready/valid, make trace acceptance part of the commit transaction so a held
instruction cannot modify state repeatedly.

## 14. Control flow, fences and recovery

Drain older backend work before issuing a branch/jump singleton. EX computes
its resolved next PC; C applies it after successful completion. Discard younger
prefetched instructions and restart fetch at that PC, including fall-through
for a not-taken branch. This deliberately accepts control-flow bubbles to make
the first recovery protocol easy to verify.

Use each instruction's own PC for relative addressing and link values. Check
target alignment for the selected base-only instruction alignment. JALR's low-
bit masking rule does not mean two-byte-aligned fetch is legal without an
appropriate extension. Test target arithmetic separately from pipeline control.

FENCE drains previous data activity and prevents younger access until ordering
is satisfied. With a strongly ordered adapter whose acknowledgements meet the
execution environment's completion semantics, serialization can supply the
ordering. A posted-write path may need a further drain acknowledgement. One
outstanding request alone does not prove visibility at the final observer.

Write a priority table before coding recovery: an older trap overrides a younger
redirect; successful redirect cancels only younger work; coordinated reset
overrides internal transfers. Outstanding memory responses need their own drain
or cancellation protocol. Clearing pipeline valid bits is not the whole flush.

## 15. SystemVerilog pipeline control

Every packet boundary has valid, ready and payload. Transfer occurs on a rising edge
with both handshake signals high. A producer must keep its payload stable while
stalled. A one-entry elastic register may accept when empty or when its current
entry is being consumed. Chained ready logic can become a physical timing path;
adding buffering later must preserve the protocol. The live register-read
sideband described in section 7 is sampled at the R-to-DP transfer; it is not
part of the stable control packet.

Use synchronous active-high reset and the requested next-state convention:

```systemverilog
always_comb begin
  valid_d = valid_q;
  payload_d = payload_q;
  if (ready_o) begin
    valid_d = valid_i;
    if (valid_i) payload_d = payload_i;
  end
  if (rst_i || kill_i) begin
    valid_d = 1'b0;
    payload_d = '0;
  end
end

always_ff @(posedge clk_i) begin
  valid_q <= valid_d;
  payload_q <= payload_d;
end
```

This sketch omits output equations. The complete [pipeline register example](../../examples/superscalar/pipe_reg.sv)
is a storage primitive, not an implemented CPU stage. Its kill input clears
the whole register; the core must generate appropriate kills without erasing
older surviving instructions or an authorized outstanding store.

Blocking assignments belong in combinational next-state logic. Nonblocking
assignments belong in the sequential state transfer. Assign defaults on every
path to avoid latches. Keep reset decisions, conditions, arithmetic and cases
out of `always_ff`. Packed structs help readability but do not establish SRAM
inference or a viable multiport register file on a particular physical target.

## 16. Example pipeline timing

For independent ALU packets A and B with no stalls, the intended logical stage
occupancy is below. Actual fetch interface latency may introduce gaps.

| Cycle | A | B |
| --- | --- | --- |
| 1 | IF | — |
| 2 | D | IF |
| 3 | R | D |
| 4 | DP | R |
| 5 | EX | DP |
| 6 | MEM | EX |
| 7 | WB | MEM |
| 8 | C | WB |
| 9 | retired | C |

Each packet may contain four independent operations. Once filled, the target is
four retirement events per cycle if fetch, ports and every ready signal support
that rate. If B reads A's destination, B waits in DP until commit refreshes its
value and clears busy state. Following packets queue behind it.

This table is a design target, not measured performance. Measure IPC as accepted
retirement events divided by cycles over a defined program interval. Memory
serialization, branches, dependencies and insufficient instruction bandwidth
all reduce achieved IPC.

## 17. Module layout and how to start

The following is a proposed future layout, not a list of implemented modules:

```text
rtl/superscalar/
  rv32_pkg.sv          operations, packets and exception types
  rv32_decode.sv       single decoder, replicated four times
  regfile.sv           committed storage and commit write ports
  scoreboard.sv        busy bits allocated by DP and released by C
  fetch.sv             PC, request/response and redirect handling
  register_stage.sv    register reads and commit refresh
  dispatch.sv          prefix checks, suffixes and serialization
  execute.sv           four ALUs and shared address/target logic
  memory_stage.sv      load processing and store descriptors
  writeback.sv         completed packet holding
  commit.sv            architectural effects and trap/redirect events
  memory_adapter.sv    chosen external protocol and error semantics
  core.sv              eight-stage wiring and recovery
```

First specify packet fields, then implement the decoder and ALU with directed
tests. Reuse arithmetic knowledge from the earlier work, not its renaming and
oldest-ready scheduler. Connect all eight stages with one enabled lane and an
independent retirement checker. Add serialized branches and memory before
widening; this exposes stage-control bugs without four-lane interactions.

Next enable four independent ALU lanes. Implement prefix dispatch and retained
suffixes, then add scoreboard hazards and commit refresh. Finally test special
operations mixed with ALU prefixes. Keep a working regression after every step.
Do not create dozens of empty modules and count them as hardware progress.

The [roadmap](roadmap.md) gives the milestone gates. At this revision only the
tutorial and storage example exist for the new architecture.

## 18. Verification and acceptance tests

Compare retirement order, PCs, destination writes, memory effects and traps
against an independent architectural model. EX results alone are insufficient:
the architectural machine exists at commit. Full RV32I claims also need the
selected execution environment and appropriate architectural test coverage.

| Area | Directed test |
| --- | --- |
| Width | Four independent instructions dispatch and retire per cycle after filling |
| Prefixes | Admit 0, 1, 2, 3, 4 lanes and preserve every suffix exactly |
| RAW | All earlier/later lane pairs, both source positions, across packets |
| WAW | Same name within a packet and across pipeline stages |
| WAR | Older captured reader with younger writer; blocked-reader case |
| x0 | No register changes; loads to x0 still access and fault |
| Stale sources | Commit during R/DP stalls and during R-to-DP transfer |
| Handshakes | Stall every boundary; no lost, duplicated or changing payload |
| Memory | All widths, masks, signed loads, delayed responses and errors |
| Store precision | One authorized request; older fault prevents younger store |
| Fetch | Every word offset in a block; stale response after redirect |
| Control | Taken/not-taken, links, target masking and alignment |
| Exceptions | Retire older valid prefix only; no younger architectural effect |
| Fence | Earlier effects ordered before later accesses through the actual adapter |
| Reset | Coordinated endpoint/core reset and outstanding-response handling |

Assert valid-prefix masks, no dispatch past blocked older work, and exactly
one live writer for every busy bit. Assert every store request is authorized
and every accepted instruction retires once or is discarded by a valid recovery.
Liveness assumes the external memory eventually responds and downstream
eventually accepts; permanent external backpressure legitimately stalls a core.

The included storage example is lint-checked only at this tutorial stage. No
complete superscalar RTL, simulation, ISA compliance or timing result is claimed.
The historical OoO regression cannot validate the new architecture.

## 19. Optimize only after the protocol works

Later forwarding can use EX/MEM/WB values. Select the youngest older matching
producer; if it is not ready, do not forward an older matching value instead.
The initial one-writer restriction simplifies this logic while it remains in
force. Load-use dependencies still need a response before any valid forwarding.

Same-packet dependent ALUs require a combinational lane-to-lane path or splitting
the packet across cycles. A chain through four ALUs may destroy clock timing.
Keep split-and-wait until measurements justify extra bypass logic.

Memory overlap needs queued store ownership and ordering checks; prediction
needs wrong-path recovery; multiple simultaneous writers need stronger producer
tracking. These are separate changes, not prerequisites for in-order superscalar
execution. None should be introduced by simply dropping an existing stall.

Physical implementation should examine register-file ports, dependency compares,
ready-chain length and commit fanout. Select a board or ASIC library before
writing timing constraints. More lanes are valuable only if wiring, resource
cost and clock frequency produce a real workload benefit.

## 20. References and reproducible next steps

Primary references checked on 2026-09-27:

- [RISC-V ratified specifications](https://docs.riscv.org/): authoritative index.
- [RV32I versioned chapter](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html): encoding and behavior authority.
- [RVWMO memory model](https://docs.riscv.org/reference/isa/unpriv/rvwmo.html): ordering rules for memory-system validation.

Stage allocation, serialization, scoreboard policy and adapter contracts above
are proposed implementation choices. Test them rather than treating an ISA
reference as proof of this particular microarchitecture.

```powershell
python scripts/build_superscalar_docs.py
python scripts/build_superscalar_docs.py --check
wsl -d Ubuntu -- verilator --lint-only -Wall --top-module pipe_reg examples/superscalar/pipe_reg.sv
```

The next implementation step is a single-lane version of all eight stages with
architectural writes at commit. Widen that proven protocol to four lanes rather
than duplicating an unverified whole processor four times.
