# Your first complete mental model of this processor

Read this guided introduction before the detailed design reference. You do
not need to know what a scoreboard, retirement packet or handshake is yet.
We will define each one, show why it exists, and connect it to the actual files.

**Project status:** the forwarding and control-hazard units have working RTL
and standalone tests. The rest of the new processor is a set of typed, deliberately
unfinished skeletons. This guide describes the machine you are going to build;
its worked cycle examples are design illustrations, not recorded CPU simulations.
The documentation expansion does not fill in the unfinished hardware for you.

## A1. What a processor actually does

A program is a sequence of instructions stored as bits in memory. Each instruction
asks the processor to do a small operation: add two values, read memory, write
memory, or choose a different next instruction. The processor repeatedly reads
instructions, works out their meaning, obtains their inputs and applies their
effects in the order required by the program.

Imagine this short program, with decimal constants:

```text
addi x5, x0, 7      # x5 gets 0 + 7
addi x6, x0, 9      # x6 gets 0 + 9
add  x7, x5, x6     # x7 gets 7 + 9 = 16
```

x5 is a register name, not the number five used as arithmetic data. A register
is a small storage location inside the processor. x0 is special: reading it
always returns zero, and writing it changes nothing. Memory is a much larger
addressed storage space reached through a separate interface.

The **program counter**, or PC, identifies an instruction's address. An ordinary
base RV32I instruction occupies four bytes, so straight-line addresses might be
0x100, 0x104 and 0x108. These are illustrative addresses, not a selected reset
address for this project. A branch or jump can choose another next PC.

The ISA is the software contract. The pipeline is our chosen way of implementing
that contract. RV32I does not require four lanes or eight stages. Those are
microarchitectural decisions we must make correct and then measure.

## A2. The three kinds of storage you must distinguish

| Storage | Example | What it represents |
| --- | --- | --- |
| Architectural register file | x5 contains 7 after commit | Program-visible register state |
| Pipeline registers | An unfinished ADD and its inputs are waiting in EX | Work in progress, not yet architectural state |
| External memory | Bytes addressed by a load/store | Program data/instructions with separately ordered effects |

“Register stage” refers to reading architectural registers. “Pipeline register”
refers to a hardware storage boundary between cycles. They are not the same
thing. A register file holds many named values; a pipeline register holds a
packet of instruction information moving through this particular implementation.

If EX computes 16 for x7, the pipeline may know the result before x7 in the
architectural register file contains 16. Forwarding can let another instruction
use that result early. Commit is the point where the register file is updated.
Keep these moments separate whenever reading a waveform.

## A3. Bits, signed values, addresses and byte order

RV32 data values are 32-bit patterns. Hexadecimal is a compact way to write
them: each hex digit represents four bits. 0x00000010 is decimal 16. The pattern
0xffffffff is unsigned 4294967295 or signed −1 depending on the operation.
The storage bits do not change when you choose a signed interpretation.

Addition keeps its low 32 result bits. For example, 0xffffffff + 1 produces
0x00000000. SLT compares signed values; SLTU compares unsigned values. A logical
right shift inserts zeros, while an arithmetic right shift repeats the sign bit.
These choices must be explicit in SystemVerilog; do not assume every logic
vector automatically carries a signed interpretation.

Our proposed memory interface is little endian: the least significant byte
occupies the lowest addressed byte. If a memory word is 0xa1b2c3d4 at address
0x200, its bytes are:

| Byte address | Stored byte |
| --- | --- |
| 0x200 | 0xd4 |
| 0x201 | 0xc3 |
| 0x202 | 0xb2 |
| 0x203 | 0xa1 |

LB at 0x200 produces 0xffffffd4 after sign extension. LBU produces 0x000000d4.
Neither load is asking for the numeric address 0x200 as its result. Address
generation and returning the data at that address are separate operations.

## A4. What a clock edge means

Combinational logic computes from current inputs during a cycle. At a rising
clock edge, sequential storage captures its selected next state. All pipeline
registers conceptually capture together; the source-code order of different
modules does not determine which instruction moves first.

If R holds instruction A before an edge and D holds B, that edge may move A
into DP and B into R. A has not instantly passed through DP and EX as well.
Those later movements require later edges unless explicitly designed as a
combinational path.

Our naming convention is `_q` for current registered state and `_d` for the
next-state value. `_i` is an input port and `_o` is an output port. Start an
always_comb block with defaults, compute next state using blocking assignments,
then use only nonblocking state assignments inside always_ff. Synchronous reset
takes effect at a clock edge, not immediately when its signal changes.

An unimplemented module with an undriven output does not mean that output is
architecturally zero. A simulator might show unknown data or a particular
default depending on its model. The skeleton intentionally supplies no behavior.

## A5. Pipeline depth and superscalar width are different

Pipeline **depth** is how many stages an instruction traverses. Our requested
depth is eight. Pipeline **width** is how many independent instructions a stage
can process together. Our final target width is four.

A useful picture is four parallel lanes through each of eight processing steps.
The lanes are positions within an age-ordered packet, not four separate CPUs.
They share one architectural register file, one program's order and one commit
policy. They also share some limited resources, including the single data port.

Four independent ADDs can occupy four EX lanes at once. Four dependent ADDs
cannot necessarily do so: each may need the preceding result. Four loads do
not run together in this initial design, because data operations serialize.

Latency asks how long one instruction takes. Throughput asks how many finish
per cycle after the pipeline fills. A deep pipeline can have good throughput
without low latency. Four-wide is a peak opportunity, not a promise of IPC=4
on arbitrary programs. IPC means retired instructions divided by clock cycles
over a stated interval.

## A6. The whole machine in one annotated picture

```text
Instruction memory
      |
      v
 IF -> D -> R -> DP -> EX -> MEM -> WB -> C
           ^     ^      |      |      |    |
           |     +------+- result forwarding --+
           |                                  |
           +-- committed register file <-------+ commit writes
                 |
                 +---- current values read in R

DP allocation --> scoreboard <-- C release
MEM load request --> memory adapter <-- C authorized store
C branch/trap --> recovery --> IF redirect and younger-work cancellation
```

The forward arrows show instruction progression. The backward arrows carry
data or control information; they do not mean instructions execute backward.
A producer in EX can send a value to a waiting consumer in DP. Commit can
release a busy register name. Recovery can tell fetch which PC to use next.

The units outside the straight pipeline are just as important as the stages.
The scoreboard remembers who is still writing. The forwarding unit resolves
operand values. The memory adapter owns external requests. Recovery owns trap
reporting and restart. `core.sv` eventually connects all of them; its current
ports do not instantiate or implement any of them yet.

## A7. The eight stages, explained without shortcuts

### IF: get instruction bits, not data operands

IF chooses an address, sends an instruction request and waits for a response.
It attaches a PC to each instruction word and buffers a packet when decode is
not ready. It cannot assume memory answers immediately. It cannot discard
ownership of a request just because a branch later changes the desired PC.

The proposed instruction response carries four words from an aligned 16-byte
block. If the desired PC is 0x10c, only that block's last word is relevant.
IF emits one instruction, then obtains the next block. Correctness matters
more than filling every packet with four words.

### D: translate bits into named actions

D determines the operation, source names, destination, immediate and whether
the instruction needs serialized treatment. It does not read the register
values or calculate the arithmetic result. A decoder is combinational; the
decode stage also needs packet storage and handshake control.

`rv32_decode.sv` is the per-instruction decoder; `decode_stage.sv` uses four
instances and preserves packet order. Do not confuse these two files and
accidentally add an extra pipeline stage between them.

### R: obtain the current committed register values

R holds stable register indices and reads the register file. Four instructions
with two sources each need up to eight reads. A port means an independently
addressable access, not merely another variable name in RTL.

The register file may change while R waits because older instructions commit.
Therefore R supplies live operand values on a separate sideband sampled by DP
at transfer. The held instruction/control packet remains stable. DP subsequently
maintains its own snapshots and resolves them against forwarding.

### DP: decide what may safely start execution

DP checks sources, destination ownership and resource availability in program
order. It selects an oldest consecutive prefix, never arbitrary ready lanes.
If lane 1 cannot run, lanes 2 and 3 wait behind it. It retains and compacts the
unselected suffix without changing the instructions' original PCs.

DP allocates busy destination names only when an instruction actually transfers
to EX. A tentative choice or an offer held under backpressure is not allocation.
For serialized instructions, DP also waits for older backend work to drain.

### EX: compute, but do not commit

EX performs arithmetic or computes an address/branch result. It can supply a
ready arithmetic value to forwarding. A load's computed address is not ready
load data. Branch comparisons and jump targets are calculations here; the
current conservative design applies control-flow changes at commit.

Use the currently resident EX operation for forwarding, not the candidate
arriving from DP. Feeding the new DP instruction's own prospective result back
into its input selection would create the wrong dependency path or a loop.

### MEM: obtain load data or prepare a store descriptor

MEM sends a load once, waits for its response and formats the returned bytes.
It passes ALU instructions through in order without issuing memory traffic.
For stores it packages the address, data and mask but does not send the write.
Commit must authorize that externally visible operation later.

A load-waiting stage may be occupied even when it has no output packet ready.
Consequently backend_empty cannot be calculated from output-valid bits alone.

### WB: preserve the completed result while commit waits

WB is a holding stage for results, destination metadata and faults. In this
project it is not the place that writes x1–x31. It can provide a forwarded
value, but it cannot clear destination ownership or retire an instruction.

When C stalls, WB holds its packet and earlier stages experience backpressure.
This is normal behavior, not a reason to overwrite the oldest unfinished work.

### C: make accepted effects architectural

C applies register writes, emits retirement records and handles ordered traps.
It retires only the oldest permitted prefix. It sends an authorized store once
and waits for the result before declaring that store complete. It coordinates
branch retirement/link updates with acceptance of the redirect event.

This separation lets us distinguish “the ALU knows the answer” from “the program
has permanently completed this instruction.” Precise errors depend on it.

## A8. Follow one real instruction through every stage

Take `addi x5,x0,7`, whose instruction word is 0x00700293. Its fields are opcode
0x13, destination 5, source 1 index 0, funct3 zero and signed immediate 7. The
instruction's register indices are not its operand values.

| Stage | Example state or action |
| --- | --- |
| IF | Receives 0x00700293 and attaches its illustrative PC 0x100 |
| D | Produces OP_ADDI, rs1=x0, rd=x5, uses_rs1=1, uses_rs2=0, immediate=7 |
| R | Supplies zero for source x0; no real rs2 value is needed |
| DP | Checks x5 ownership, resolves x0 ready, dispatches and allocates busy[5] |
| EX | Selects zero and immediate seven; computes result seven |
| MEM | Makes no data-memory request and preserves the result |
| WB | Holds result=7 and destination x5 for commit |
| C | Writes x5=7 once, clears busy[5], emits a retirement event for PC 0x100 |

If rd were x0, the instruction could still retire, but it would not allocate
or write a nonzero register. For memory instructions, rd=x0 must not remove
memory accesses or faults. Destination suppression is not instruction deletion.

The reference chapters give the complete instruction-group checklist. This
example demonstrates the metadata journey, not an implementation of the decoder.

### How decode finds the fields

Number instruction bits from 31 down to 0. A slice such as instruction[19:15]
means the five bits at positions 19 through 15, inclusive. The opcode is [6:0],
rd is [11:7], funct3 is [14:12], rs1 is [19:15], rs2 is [24:20], and funct7 is
[31:25] when the particular format uses those fields. A field's physical bits
can instead belong to an immediate in another format.

| Format | Typical use | Where the immediate comes from |
| --- | --- | --- |
| R | ADD and other register operations | No immediate; two source registers |
| I | ADDI, loads, JALR | instruction[31:20], sign-extended from 12 bits |
| S | Stores | instruction[31:25] followed by instruction[11:7], sign-extended |
| B | Conditional branches | [31], [7], [30:25], [11:8], then a zero bit; sign-extended |
| U | LUI and AUIPC | instruction[31:12] followed by twelve zero bits |
| J | JAL | [31], [19:12], [20], [30:21], then a zero bit; sign-extended |

“Followed by” means concatenation from high to low bits, not arithmetic addition.
Sign extension repeats the original sign bit into the newly added upper positions.
Shift-immediate operations use a shift amount and additional function checks;
do not treat every I-format instruction as ADDI.

Use the [official RV32I formats and semantics](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
when completing the decoder. The table is a reading aid, not the full legality
table. For this project, write a decode row containing the required opcode and
function fields, source-use flags, destination behavior, immediate format and
serial classification. Then test the resulting record, not just its operation
name. A correctly named ADD with a wrong source flag can still break dispatch.

## A9. Valid and ready: an agreement at a clock edge

`valid` says the producer is offering meaningful work. `ready` says the receiver
can accept it. The transfer is `valid && ready` at the rising edge. Neither
signal alone means ownership moved.

| valid | ready | Meaning at the edge |
| --- | --- | --- |
| 0 | 0 | No transfer; neither side is offering an accepted item |
| 0 | 1 | Receiver has space, but producer has no item |
| 1 | 0 | Producer must retain its offered packet |
| 1 | 1 | One transfer; receiver now owns that item |

Suppose EX offers packet A while MEM is waiting on an older load. EX keeps A
valid with the same payload through every stalled edge. When MEM finally raises
ready, exactly one edge transfers A. EX must not treat each stalled cycle as a
new issue. Likewise, a memory request may be accepted before its response exists.

For a one-entry buffer, `ready = !occupied || downstream_ready` permits consuming
the old packet and replacing it with a new packet on one edge. Without this
consume-and-replace case, every packet may be followed by an avoidable bubble.
This equation alone does not implement flush priority or external request ownership.

A **bubble** is an empty slot, not an instruction encoding of zero. A **stall**
retains work. A **flush** cancels specific work. Reset initializes the design
under a coordinated system contract. Using these words interchangeably causes
real bugs: a stall must not clear a valid instruction, and a flush must not
erase an already-authorized external store.

### Decide simultaneous events before writing next-state logic

Multiple events can be true during one cycle. For a simple pipeline buffer,
reset/authorized kill must take precedence over ordinary movement. When there
is no cancellation, downstream acceptance and upstream acceptance may replace
the old item together. With neither event, retain the old ownership.

This is a reasoning method, not a universal priority list for every module.
Commit cannot erase an authorized store because a younger instruction wants
a flush. The adapter cannot forget a request that the memory endpoint accepted.
Write a separate event table for each state owner before implementing its
always_comb block. Use the actual pipe_reg example for the small buffer case.

## A10. Packets, lanes and splitting an instruction group

Assume lane 0 is oldest and the valid mask is written with lane 0 at the right.
1111 means four instructions, 0011 means lanes 0 and 1, and 0000 means empty.
0101 has a hole and is not a legal compact input packet for this design.

```text
Before dispatch:
lane 0 = A, PC 0x100
lane 1 = B, PC 0x104
lane 2 = C, PC 0x108
lane 3 = D, PC 0x10c

Accept A and B only.

Retained suffix after compaction:
lane 0 = C, PC 0x108
lane 1 = D, PC 0x10c
lane 2 and lane 3 invalid
```

Compaction changes storage positions, not instruction identities or PCs. C does
not acquire A's address when moved into lane 0. Use the retained instruction's
own metadata for branch targets, faults and retirement checks.

While a selected prefix is offered to EX and EX is stalled, freeze that selection.
Do not expand it from two instructions to three midway through the offer just
because another operand becomes ready. After acceptance, update ownership and
compact the remaining suffix exactly once.

## A11. Dependencies and the scoreboard, with concrete values

The scoreboard is a 32-bit ownership table. busy[5]=1 means a dispatched
instruction still owns a future write to x5. It does not mean the numeric value
of x5 is one, and it does not mean the result is definitely unavailable.
Forwarding may already have that result even while the name remains busy.

Consider A=`addi x5,x0,7` and B=`add x7,x5,x6`, with x6 already equal to 9.
B has a true read-after-write dependency: it needs A's seven, not the old x5.
Dispatching B with stale x5 would calculate the wrong result. B may proceed
when A's result is ready for forwarding, subject to the in-order/resource rules.

Now let C=`addi x5,x0,20`. C is another writer to x5. Our simple policy prevents
C from dispatching while A owns busy[5], even if A's result is already forwarded.
Otherwise one bit could not distinguish which writer later cleared ownership.
This is a conservative WAW rule, not a universal requirement for every CPU.

For WAR, imagine A reads x5 and a younger B writes x5. Once A's operands are
captured safely, B's later architectural write cannot change that captured input.
In-order dispatch prevents B passing a blocked older reader. No renaming table
is needed for this initial policy.

Set a busy bit only at actual dispatch; clear it only at accepted commit or
valid recovery that removes all its remaining owners. Never clear it just
because a result was forwarded. x0's busy bit must stay clear.

## A12. Forwarding is choosing a value, not changing the register file

Forwarding is a multiplexer decision. It substitutes an available older result
for the stale committed-register snapshot a consumer would otherwise read.
It does not retire the producer, update the architectural register file or
let the consumer ignore program order.

Each of eight source ports compares its register index with up to sixteen
producer descriptions. The comparison must use valid, writes_rd and killed
flags as well as the name. A store has no integer destination result to forward.

| Situation for source x5 | Correct choice |
| --- | --- |
| No live writer and busy[5]=0 | Use the refreshed register-file value |
| Matching writer has a ready nonfaulting value 7 | Forward seven |
| Youngest matching writer is still waiting for data | Stall, even if an older value exists |
| Matching writer faulted | Stall until recovery; do not use an older value |
| Candidate writer was killed | Exclude it from live producer matching |
| Source is x0 or unused | Resolve ready zero |

The youngest matching writer is the most recent one before the consumer in
program order. Numeric data value and register number say nothing about age.
In this strictly ordered pipeline, stage/lane placement defines age: current EX
is younger than MEM, then WB, then C. Within each packet a higher valid lane
is younger. If you later permit overtaking, that age shortcut must change.

An EX-to-DP path can let B follow A in the next cycle. It cannot make two newly
selected dependent instructions complete a chain inside one ordinary cycle
unless you intentionally build that combinational chain. We do not do that.

## A13. A four-instruction worked scheduling example

Assume all starting source values are committed and these instructions arrive
as one packet:

```text
A: addi x5, x0, 7
B: addi x6, x0, 9
C: add  x7, x5, x6
D: xor  x8, x9, x10
```

A and B may dispatch together. C needs both of their results, so the oldest-
prefix rule stops there; D cannot pass C even though D is independent. DP keeps
C and D as its suffix. Once A/B are resident in EX with ready values, forwarding
can supply C's seven and nine. If EX can consume and replace its current packet,
C and D may enter EX on the next edge.

This illustrative overlap assumes a direct EX forwarding path meets timing and
no downstream stage stalls. If that path is disabled, C waits until those results
become visible at a later supported forwarding point. The arithmetic remains
the same; only the schedule changes.

At retirement, the accepted effects remain A then B then C then D. Some may
retire on the same edge, but the trace preserves lane order. Four-lane hardware
does not allow D to commit before unfinished C. Under a fault, only permitted
older effects may become visible.

## A14. Loads: follow the address, response and result separately

Suppose x1 contains 0x200 and we execute `lbu x5,1(x1)`. The bytes are those from
A3. The expected result is 0x000000c3.

| Step | What happens |
| --- | --- |
| R/DP | Read x1, drain older backend work, and admit the load alone |
| EX | Calculate original byte address 0x201; no load data exists yet |
| MEM request | Offer aligned address 0x200 with read semantics under the adapter contract |
| Request acceptance | Record that it was sent; do not resend during the wait |
| Response | Receive word 0xa1b2c3d4 or an access-error indication |
| MEM formatting | Shift/extract byte offset 1 and zero-extend 0xc3 |
| WB/C | Hold, then commit x5=0x000000c3 and retire the load |

Request acceptance and response completion can be separated by many cycles.
The adapter remembers which instruction-side owner receives the response.
Its idle signal stays false while it holds a response the core has not consumed.

For `lh x5,1(x1)`, address 0x201 is misaligned for our selected halfword policy.
The design reports a fault before issuing that request. This project's trap
policy is a platform choice; do not mistake it for a hidden automatic split
across two memory words.

Loads remain serialized here even though the forwarding module can represent
load results. A capable submodule does not automatically relax the overall
dispatch policy. Enabling overlapping loads would require more ownership,
ordering and recovery work than changing one stall bit.

## A15. Stores: why computing the address is not permission to write

For `sb x5,1(x1)` with x5=0x000000aa and x1=0x200, EX computes address 0x201.
The aligned bus write address is 0x200, write data is 0x0000aa00 and the four
byte strobes are 0010. A strobe bit says which byte is actually modified; the
other data bytes are irrelevant to this write.

MEM creates that descriptor. WB holds it. C checks that the store is the next
allowed architectural effect, then sends it through the adapter. On acceptance
it remembers store_sent=1. Waiting three more cycles for acknowledgement must
not create three additional writes, especially when the target is a device.

An older exception must prevent a younger store from being authorized. After a
store is authorized, external effects cannot be undone by flushing pipeline
registers. Our adapter contract requires failed stores to have no partial
visible effect. A real bus that cannot guarantee that needs a different error
contract; the skeleton does not solve this by pretending errors never occur.

FENCE orders relevant accesses. In this simple design it waits for earlier
data operations to complete and blocks later ones. This is sufficient only
when the memory endpoint's acknowledgement really satisfies the required ordering;
an acknowledgement into a posted queue may require an additional drain mechanism.

## A16. Branches and the difference between a fault PC and a restart PC

A branch asks a condition and chooses a target or fall-through. For an illustrative
branch at 0x100 with offset 12, a taken target is 0x10c and fall-through is
0x104. Use that branch's own PC, not the packet's first PC or the current fetch PC.

The initial policy drains older work, dispatches the branch alone, and blocks
younger dispatch. EX calculates its outcome; C accepts the control-flow event.
Recovery tells IF to restart and discards younger prefetched words, even for
fall-through in this conservative version. There is no branch predictor to train.

JAL/JALR also produce a link value, so the link write and accepted branch event
must agree. A losing or faulting jump must not leave a committed link write.
JALR clears bit zero of its computed target, but base-only instruction alignment
still requires checking the remaining alignment condition.

An exception has a faulting PC that identifies the failed instruction. Its
restart/handler PC is where the environment later tells execution to continue.
Those are different fields. For example, a fault at 0x120 does not imply the
handler is located at 0x120. The unfinished recovery module must retain the
trap report and wait for the environment's explicit response.

The control unit stops new sequential fetch, but must still allow a redirect
to be accepted and stale responses to drain. If IF says “I cannot accept a
redirect because fetch is stopped,” and control says “fetch stays stopped until
you accept the redirect,” neither side can progress. That is a deadlock, not
an ordinary stall.

## A17. Precise commit and a fault in the middle of a group

Precise architectural state means the machine can explain the program as an
ordered sequence up to the fault: permitted older instructions completed, the
faulting instruction did not complete normally, and younger effects are absent.

Imagine a future commit packet containing A, B, faulting C, and D. Commit may
retire A/B if their effects are complete. It must not report C as a normal
retirement or commit D. The current serial-special policy often makes a fault
a singleton, but the general prefix rule is still the right specification.

`commit_writes_t` describes accepted register writes. `retire_bundle_t` is a
passive trace of accepted instructions; it has no ready signal in our skeleton.
`trap_t` describes the fault event separately. The trace consumer must observe
every cycle. It cannot silently backpressure an interface that has no ready port.

Because architectural registers change only at C, their state can survive a
flush of unfinished work. Resetting the entire register file on every branch
would erase legitimate program results. Reset, branch recovery and trap handling
must therefore have different destinations and ownership rules.

## A18. Read the SystemVerilog types as a vocabulary

| Name | Beginner interpretation |
| --- | --- |
| word_t | One 32-bit data/address/instruction-sized vector; meaning depends on its field |
| reg_idx_t | Five bits selecting x0 through x31, not the selected value |
| op_t | Internal name for a decoded instruction; not its binary instruction opcode |
| decoded_t | Instruction meaning: names, source-use flags, immediate, class/fault information |
| lane_t | Everything we currently carry about one in-flight instruction |
| packet_t | Four ordered lane records |
| fault_t | Valid flag, symbolic internal cause and relevant address/bits |
| source_t | One architectural operand query for forwarding |
| producer_t | One older instruction's destination and result availability |
| mem_request_t | Aligned data transaction descriptor; no request ownership without handshake |
| mem_response_t | Returned word/error; interpreted by the retained transaction owner |

Packed means the fields form a contiguous bit vector that can be stored or
assigned as a group. It does not mean every field is meaningful at every stage.
IF does not know the final arithmetic result. EX does not know pending load
data. Consult the ownership table before reading a field.

Fault enums are symbolic internal names, not architectural privileged numeric
cause codes. This base-only teaching interface does not secretly implement
machine-mode CSRs. Port declarations are contracts you must implement, not proof
that the contracts already hold.

## A19. How to implement one module without getting lost

Start with the module's question: for example, “which operation do these bits
describe?” for decode, or “who still owns a pending destination?” for the scoreboard.
Write the inputs it may trust, the outputs it owns, and the state it needs.
Do not begin by copying every signal from a larger processor design.

Then write down the edge events: input transfer, output transfer, response
acceptance, commit, reset and permitted flush. Ask which can happen together.
A buffer that can consume and replace needs a different next-state case from
a buffer that can only do one action. A request that was accepted must remain
owned even when its request-valid signal falls.

Choose one directed test whose wrong behavior would be unmistakable. For a
scoreboard, dispatch a writer, forward its value and confirm its busy bit stays
set until commit. For DP, accept two lanes and confirm the retained suffix keeps
its own PCs. For a store, delay response and confirm only one request is accepted.

Only then implement next-state logic and the assignment-only always_ff block.
Run strict lint and behavioral tests for that module. Structural skeleton checks
suppress expected undriven warnings; do not use those relaxed checks as proof
that completed RTL is good.

## A20. What is intentionally not part of this first processor

No caches, translation, interrupts, privileged CSR system, operating-system
platform, branch prediction, multiple outstanding data accesses or out-of-order
scheduler is supplied by the skeleton. The memory and trap ports are boundaries
where a selected environment will eventually connect those services if needed.

These omissions do not make four-wide integer execution impossible. They make
the implementation easier to reason about while you learn. They also limit
performance and system software support. The eventual full RV32I claim still
requires instruction semantics, the execution environment, and verification;
writing every module name is not that evidence.

The rest of this HTML contains the detailed architecture reference, the full
implementation workbook, and the current module interfaces/source listings.
Use the chapter search to find a concept, then jump to its module. Keep the
worked examples separate from measured results: this processor is still yours
to complete.
