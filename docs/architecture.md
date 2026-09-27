# Milestone 0 interface and decisions

Historical OoO architecture. The active project is the
[four-wide in-order superscalar design](superscalar/tutorial.md).

## Contract

`ooo_core` consumes a caller-supplied stream of aligned 32-bit instruction words
and their PCs. The caller is responsible for instruction order and PC selection;
the core neither fetches nor checks PC alignment. A transfer occurs at a rising
edge where `instruction_valid_i && instruction_ready_o`. While stalled, the
caller must retain valid, instruction and PC. It may insert idle cycles.

Retirement is likewise a valid/ready channel. PC, instruction, destination,
value and fault are meaningful when `retire_valid_o`; they remain stable during
backpressure. A normal transfer writes the committed register file, except x0.
The result reported for an x0-destination instruction is its computed result,
although x0 itself remains zero. This trace is not RVFI.

An unsupported instruction enters the ROB already complete, without renaming
its destination. At the head it emits `retire_fault_o`; the value is undefined
architecturally (currently zero). Accepting that event sets `halted_o` until
reset. No younger instruction can retire. Younger speculative state is retained
but frozen; there is no architectural trap entry or resumable flush interface.

Reset is synchronous and active high. All registers initialize to zero for this
laboratory; only x0 has a hardwired-zero architectural meaning. Hold reset for
one or more rising edges; inputs are not accepted during reset.

`issue_valid_o` and `issue_tag_o` are observation signals, not a ready/valid
interface. They indicate selection for the always-accepting execution pipeline.
The three-bit tag wraps and is only unique among currently live instructions.

## Fixed configuration

- RV32 data and instruction width; x0..x31 architectural names.
- Eight ROB slots, one allocation, one issue, one completion and one retirement
  per cycle. No same-cycle full-buffer retirement-to-allocation bypass.
- Unified reservation station and data-in-ROB renaming. No physical free list.
- Three execution registers; dependent issue waits for registered wakeup.
- LUI, AUIPC; ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND;
  ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI.
- All remaining opcodes and reserved function encodings are unsupported faults.

## Update ordering

The ROB starts from current state, applies completion/wakeup, marks issue,
removes a retiring head, then adds a dispatch at the old tail. Count changes
accumulate in next state. Full occupancy refuses allocation for that cycle,
which avoids replacing the retiring slot in the same cycle.

Source lookup uses the old rename map (required for `addi x1,x1,1`). Sources
already completed resolve from the ROB; same-cycle completion is bypassed into
incoming operands. A concurrent commit still has a live old ROB value during
lookup. Rename applies retirement before allocation, so the youngest writer
owns the next map. Commit clears a mapping only if its tag still matches.

## Why this baseline

Implicit renaming avoids a physical free list while exposing true dependencies,
speculative values and ordered architectural effects. A deliberately long,
fully pipelined integer path makes out-of-order scheduling observable with only
integer instructions. Neither choice is claimed to maximize performance.
Depth is fixed at a power of two: changing it to a non-power-of-two requires
explicit wrap logic in head, tail and age scanning, plus new tests.
