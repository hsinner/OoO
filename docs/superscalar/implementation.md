# The implemented processor: read the RTL from end to end

This chapter explains the working baseline in `rtl/superscalar/`. The earlier lessons remain useful as exercises: you can hide an implementation, write it yourself, then compare behavior. The source appendix contains the actual current RTL. Start here when you want to understand how the pieces now connect.

The design is a **four-wide, in-order RV32I pipeline** with eight stages. Four-wide means that a packet can contain up to four instructions, and four independent arithmetic instructions can execute and retire together. It does not mean four instructions finish on every clock. Fetch waits for memory, dependencies split packets, dispatch and commit deliberately insert bubbles between packets, and memory/control/system instructions execute alone after older work drains.

This is an educational processor with abstract instruction/data ports and an external execution environment interface (EEI). It has no cache, predictor, privileged CSRs, interrupts, MMU, multiply/divide, compressed instructions, physical register renaming or out-of-order scheduler. Those remain extension lessons. FPGA integration still requires a memory/bus implementation, an EEI policy, clock/reset constraints and device-specific synthesis and timing checks.

## 1. First understand the machine's two kinds of state

**Architectural state** is what a program can observe: committed register values, committed memory effects and the program's instruction sequence. **Pipeline state** is temporary bookkeeping: a fetched packet, operands waiting in dispatch, a load waiting for its response. A computed result is not automatically an architectural update.

`regfile.sv` holds committed integer registers. Only `commit.sv` supplies its write events. EX computes values; MEM completes loads; WB holds completed packets; C decides which effects become visible. Stores are sent externally from C, after older instructions have completed. This separation is why an instruction that eventually faults cannot accidentally write a register just because its ALU calculated something.

Every sequential module follows your requested style:

```systemverilog
always_comb begin
  d = q;                 // Keep existing state unless an event changes it.
  if (event) d = update; // Decide the next state using current inputs/state.
  if (rst_i) d = '0;     // Reset has final priority.
end
always_ff @(posedge clk_i) begin
  q <= d;               // Only assignments belong in this block.
end
```

`q` means the state currently stored in flip-flops. `d` means the state that those flip-flops will receive at the next rising edge. A structure can hold many fields and still use one `q <= d` assignment. These are synchronous resets: the reset decision changes D immediately, but stored Q changes on the clock edge. Ports are also gated during reset to prevent transactions.

Several files use separate `always_comb` blocks for readiness, output data and next-state updates. This makes dependencies explicit. For example, a stage's output-valid depends on its resident valid bit; it should not accidentally appear to depend on the next packet's input-valid merely because both calculations were put in one large block. Strict lint checks the resulting combinational dependency graph.

## 2. The connecting wires and the meaning of a packet

```text
instruction memory
       |
       v
 IF --> D --> R --> DP --> EX --> MEM --> WB --> C
             |      ^      |       |       |      |
           regfile  |      +-------+-------+------+
             ^      |             forwarding producers
             |      +---- scoreboard / commit bypass
             +------------------------------ C writes
                                  MEM loads ---+
                                    C stores --+--> memory_adapter --> data memory
                                    C traps/branches --> recovery --> IF redirect
```

A stage-to-stage channel carries `packet_valid`, `packet_ready` and a `packet_t` payload. Transfer occurs only on a rising edge with both valid and ready high. Ready means the receiver can take ownership; valid means the sender is offering something real. Neither signal alone is a transfer.

A packet contains four lanes. Lane 0 is oldest. Valid lanes always form a prefix: `0,1,2` may be valid with lane 3 unused; a hole at lane 1 with lane 2 valid is not a legal packet. Outer packet-valid says the whole storage slot is occupied; each lane-valid says which of its entries are real instructions.

Most stages can consume A and accept B on the same edge. DP accepts a new packet only when its retained packet is empty. C similarly accepts only when empty. These two deliberate bubbles simplify ownership and are a future performance optimization, not an ISA limitation.

A held packet's payload stays unchanged until transfer or an authorized flush. R has a separate live operand sideband that may change while its control packet remains held. DP samples those values on acceptance, then refreshes snapshots when matching registers commit. Do not treat that live sideband as a stable packet field.

## 3. rv32_pkg.sv: the shared vocabulary

[Open rv32_pkg.sv](../../rtl/superscalar/rv32_pkg.sv). A package defines types and pure helper functions; it does not allocate flip-flops by itself.

`word_t` is 32 bits. `reg_idx_t` is five bits, enough to select registers x0 through x31. `op_t` is our internal operation enumeration: it is easier for EX to receive `OP_SRAI` than to decode the instruction encoding again. Its numeric values are implementation details, not instruction opcodes.

`decoded_t` carries the operation, source/destination indices, source-use flags, destination-write flag, immediate, serialization flag and decode fault. A source index is meaningful only when its use flag says the instruction reads that source. `writes_rd` is false for x0 and for instructions without a register result.

`lane_t` accumulates information as an instruction travels. IF provides PC and instruction. D provides decoded control. DP resolves `src1/src2`. EX computes result, effective address, positioned store data, byte mask, next PC and alignment faults. MEM replaces a load's result with returned data. WB preserves it. C consumes it. Fields that have not reached their owning stage are not yet meaningful.

`fault_t` holds valid, symbolic kind and an associated address or instruction value. These kinds are **not privileged mcause numbers**. `trap_t` adds the instruction and its PC so an external environment can decide what to do. `retire_t` describes a successful retirement event; `commit_writes_t` describes accepted register updates. Retirement has no ready input: a monitor must sample every cycle.

`if_response_t` contains four words and four per-word access-error bits. `mem_request_t` carries a read/write bit, aligned word address, positioned write data and byte enables. `mem_response_t` carries read data and an error bit. `is_load`, `is_store`, `is_control` and `memory_mask` classify operations without storing state. `make_producer` converts a resident lane into the smaller forwarding record and qualifies it with occupied/ready status.

## 4. hazard_pkg.sv: describe a consumer and a producer

[Open hazard_pkg.sv](../../rtl/superscalar/hazard_pkg.sv). Eight source records correspond to two sources for each of four lanes. A source says whether it is used, which register it wants, whether the scoreboard marks that register busy, and what value to use if the committed snapshot is sufficient.

Sixteen producer records describe four lanes in each of EX, MEM, WB and C. Each says whether it is valid, writes a destination, is killed or faulting, has its value ready, and what destination/value it carries. Keeping these records smaller than a full pipeline lane makes the forwarding interface easier to understand.

## 5. fetch.sv: acquire instructions and remember memory ownership

[Open fetch.sv](../../rtl/superscalar/fetch.sv). State `q.pc` is the next desired instruction PC. `q.request_pc` remembers the PC associated with an offered memory transaction. These must be separate: a redirect can change the next PC while an old request is still outstanding.

`phase` has three meanings: 0 idle, 1 holding a request until accepted, and 2 waiting for its response. `valid/packet` hold one completed fetch packet. `stale` says that the current transaction belongs to a discarded path. `outstanding_o` is true in both request and response phases, because even an unaccepted offered request must remain stable.

An instruction request addresses a 16-byte aligned block. If the desired PC is 0x104, fetch requests 0x100 but uses response words 1, 2 and 3 as packet lanes 0, 1 and 2. The next sequential block begins at 0x110. This explains why fetch packets are sometimes narrower than four instructions.

Fetch advances to the wait-response phase only on request valid-and-ready. It creates a packet only when response valid-and-ready occurs. Access errors attach to their individual instruction lanes. A misaligned requested PC generates a fault packet without issuing a memory request.

A redirect accepts ownership of a replacement PC immediately outside reset. It discards any buffered old packet and marks outstanding old work stale. It **does not withdraw a stalled memory request**. Fetch drains the old transaction, ignores its response, then requests the new path. `stop_fetch_i` prevents starting new sequential work but does not prevent completing an already owned transaction. This is the difference between stopping instruction production and abandoning a bus transaction.

## 6. rv32_decode.sv: identify what each word means

[Open rv32_decode.sv](../../rtl/superscalar/rv32_decode.sv). This existing combinational module examines opcode, funct3 and funct7, reconstructs immediates, and produces a decoded record. It has no clock or retained state. Its default is illegal; a recognized encoding replaces that default.

The intermediate opcode/function fields select the instruction family and operation. I/S/B/U/J immediates rearrange different bit positions; negative immediates are sign-extended. Shift-immediate operations carry the five-bit shift amount rather than treating their function bits as part of an arithmetic immediate.

The use/write flags prevent false dependencies. ADD reads two registers and writes one. ADDI reads only rs1. A store reads its base and data but writes no register. JAL writes a link and uses a PC-relative immediate. Memory/control/FENCE/system/illegal operations set `serial` for the conservative scheduler. ECALL and EBREAK become fault records for the EEI. Existing decoder tests check complete records, including unused-field conventions and illegal encodings.

## 7. decode_stage.sv: turn four decoders into a pipeline stage

[Open decode_stage.sv](../../rtl/superscalar/decode_stage.sv). The decoder is a calculator; the stage is a storage boundary around four calculators. `g_decode` creates one decoder per incoming lane. `decoded_packet` copies the incoming packet and attaches each decoder's result.

An earlier fetch fault takes priority over a decode fault. An unreadable instruction must be reported as an instruction access error, even if its supplied bits happen to look illegal. Such a lane is also marked serialized.

`packet_q/valid_q` hold the accepted decoded packet. `packet_d/valid_d` hold its next state. `packet_ready_o` is high when the slot is empty or the old packet will leave. If input-valid is low on such an edge, valid clears; if input-valid is high, the new decoded packet replaces the old one. Flush clears occupancy and suppresses transfer.

## 8. regfile.sv: store only committed register values

[Open regfile.sv](../../rtl/superscalar/regfile.sv). `regs_q` is 32 words of storage; `regs_d` is the proposed next array. Eight combinational read ports allow four instructions to ask for two source registers each.

The next-state block starts with retention, applies up to four commit writes in lane order, then forces x0 to zero. Reset clears the array. If multiple writes targeted one register, the later lane's assignment would win; dispatch's WAW rule normally prevents that situation. Read outputs reflect current committed state. Same-edge commit visibility is supplied explicitly by R's bypass, rather than relying on a vendor RAM's read-during-write behavior.

This multiport array is readable RTL, but it is not automatically an FPGA block RAM. Eight reads and four writes may map to a significant amount of registers and multiplexers. Determine the actual mapping through synthesis when you choose a device.

## 9. scoreboard.sv: remember unfinished writers

[Open scoreboard.sv](../../rtl/superscalar/scoreboard.sv). A 32-bit bitmap has one bit per architectural register. `busy_q[5]=1` means an already dispatched instruction still owns a future write to x5. It does not say the value is ready; forwarding provides that separate fact.

Commit clears completed destinations. Dispatch's accepted allocation mask sets new destinations. Allocation wins if both happen on the same edge, then bit zero is forced clear. Reset or backend flush clears all ownership. Because WAW dispatch is blocked, at most one unfinished writer owns each register: one bit is enough. Supporting multiple writers would require tags or counts and a different recovery design.

## 10. register_stage.sv: hold control and read current operands

[Open register_stage.sv](../../rtl/superscalar/register_stage.sv). `packet_q/valid_q` hold the control packet. `read_indices_o` uses each lane's source-use flags to ask the register file for meaningful sources, choosing x0 for unused sources.

`live_operands_o` starts from `read_values_i`. For each read port it checks accepted commit writes and substitutes a matching newly committed value, then forces x0 reads to zero. Example: C writes x5=9 on the same edge that R transfers an ADD using x5 to DP. The register file still exposes old Q before the edge; this explicit bypass supplies 9 to DP at that edge.

The packet itself does not continually change to include those values. This avoids breaking the stable-payload rule while R is stalled. DP captures the live operand sideband when R-to-DP transfers.

## 11. forwarding_unit.sv: find the correct newest older value

[Open forwarding_unit.sv](../../rtl/superscalar/forwarding_unit.sv). This is combinational. For every used source it searches producers in youngest-to-oldest order. In this in-order pipeline, EX is younger than MEM, which is younger than WB, which is younger than C. Within a packet, higher lane numbers are younger. `core.sv` constructs precisely this ordering.

The first eligible matching writer owns the answer. If it is ready and nonfaulting, forward its result. If it is unready or faulting, block the consumer; do not fall through to an older value. If there is no matching producer, the fallback is usable only when the scoreboard says the register is not busy. x0 always resolves to zero, and unused sources never stall an instruction.

## 12. dispatch.sv: choose an ordered prefix and keep the rest

[Open dispatch.sv](../../rtl/superscalar/dispatch.sv). This is the central scheduling module. Its state includes an occupied `packet`, a `frozen` bit, a saved `offer`, and the number of lanes in that offer. It never skips a blocked older instruction to run a younger one.

`refreshed` starts with saved operands and incorporates accepted commit writes. This matters when a suffix waits long enough for a producer to leave the pipeline: its newest value must not disappear with the producer. `sources` describes the eight operand queries; the forwarding unit returns readiness and resolved `values`.

The selection loop walks lanes 0 through 3. `selected_writers` records destinations already selected in this group. `stopped` remembers the first obstacle. A lane stops selection when a source is unavailable, its source depends on an earlier selected writer, its destination is already busy, or its destination duplicates an earlier selected destination. Selection also stops before a later serialized instruction. `count` is the number of lanes accepted into the proposed prefix.

For example, lane 0 `ADDI x5,x0,7` can dispatch, but lane 1 `ADD x6,x5,x5` cannot execute beside it: this design has no same-cycle cross-ALU result path. Lane 1 remains as the new lane 0 in the retained suffix. When x5 appears as a ready older producer, that ADD can dispatch using forwarding.

`singleton` means the oldest lane is serialized or faulting. It can transfer only when the controller grants serialization after the backend empties. The serial handshake is constructed independently of `block_younger_i`: starting a singleton itself raises that block signal, and using it to suppress the same handshake would create a combinational loop.

When EX stalls a normal offered packet, DP saves the complete selected payload and count into `offer/count`, setting `frozen`. It must not expand that offer when additional sources become ready. On acceptance, the allocation mask marks only real nonfaulting writers, and exactly the accepted prefix is removed. The suffix shifts down without changing program order.

## 13. alu.sv: calculate one integer result

[Open alu.sv](../../rtl/superscalar/alu.sv). Four instances serve EX. Inputs are operation, A and B; output is a 32-bit result. There is no clock, register file, branch redirect or memory operation inside the ALU.

ADD/SUB wrap to 32 bits. Logical operations work bitwise. SLT treats operands as signed two's-complement values; SLTU compares their unsigned magnitudes. Shifts use B's low five bits. SRA/SRAI explicitly interpret A as signed so right shifting propagates its sign bit. With A=0x80000000 and a shift of one, SRL produces 0x40000000 while SRA produces 0xc0000000. The independent test oracle uses integer arithmetic/division for shifts to avoid repeating the RTL expression.

## 14. execute.sv: choose operands, calculate addresses and resolve control

[Open execute.sv](../../rtl/superscalar/execute.sv). `q/valid_q` store the resident dispatched packet. Arrays `a`, `b` and `result` connect four ALUs. Register arithmetic uses saved src1/src2. Immediate arithmetic replaces B with the decoded immediate. AUIPC uses the lane PC as A. LUI passes its upper immediate through the ALU operation.

EX starts `packet_o` as a copy of Q, then adds calculated fields. Effective address is rs1 plus immediate. Store data shifts into the correct little-endian byte position. The mask is 1, 3 or 15 for byte, halfword or word, shifted by address low bits.

`taken` records the branch comparison result, using signed comparisons for BLT/BGE and unsigned ones for BLTU/BGEU. Default next PC is PC+4. A taken branch or JAL chooses PC+immediate. JALR chooses `(rs1+immediate)` with bit 0 cleared. Jumps also produce PC+4 as their link-register result.

A taken misaligned target adds an instruction-alignment fault. Misaligned halfword/word memory addresses add load/store-alignment faults. Existing faults win. A not-taken branch does not fault merely because its encoded target would have been misaligned. Control transfers are resolved here, but C owns the later redirect event.

Producer records expose arithmetic results immediately from the resident EX packet. Loads advertise a writer whose value is not yet ready. A faulted result cannot be forwarded as successful data.

## 15. memory_stage.sv: complete a load exactly once

[Open memory_stage.sv](../../rtl/superscalar/memory_stage.sv). State holds packet, occupied-valid, `sent` and `done`. `load_pending` means lane 0 is a nonfaulting load that has not completed. The singleton contract guarantees that a load is never hidden in a later lane beside another instruction.

While pending and not sent, MEM offers a read request to the adapter. Acceptance sets sent, preventing duplicates. While sent, it waits for a response. Acceptance sets done and records either the returned result or a load-access fault. A load to x0 still performs the access and can fault; suppressing its register write must not suppress the instruction's memory behavior.

`shifted` moves the addressed byte/halfword to the bottom of the response word. LB/LH sign-extend it; LBU/LHU zero-extend it; LW retains all 32 bits. Packet-valid stays low until the load completes. Once completed, the result and any fault remain in Q until WB accepts them.

Stores pass through MEM as descriptors. They have not yet modified external memory. Nonmemory packets also pass through. Flush is safe here because integration only allows the singleton's backend cancellation after owned data work has settled; this module is not a generic speculative load-cancellation engine.

## 16. writeback.sv: hold completion, not architectural state

[Open writeback.sv](../../rtl/superscalar/writeback.sv). `packet_q/valid_q` hold a completed packet. It uses the ordinary fill, hold, replace and drain rule. It preserves every fault and provides ready producer records for forwarding.

Despite its name, WB does not write the architectural register file. In this design WB is completion buffering; C performs the visible write. That distinction keeps retirement ordered and prevents faults from leaking results into architectural state.

## 17. commit.sv: make effects visible in order

[Open commit.sv](../../rtl/superscalar/commit.sv). State contains the oldest completion packet, its occupancy, and store `sent/done` bits. A combinational loop visits lanes in program order. `stop` prevents retiring anything after the first blocking event; `count` records the retired prefix length; `retire_lane` is the decision for the currently examined lane.

Ordinary successful arithmetic can retire in all four lanes. Each retirement emits a passive trace and, when applicable, an accepted register-write event. A retired prefix is removed and the remaining suffix compacted.

A fault first waits until it is at lane 0. C offers `trap_valid_o` with a stable PC/instruction/fault record until recovery accepts it. It does not emit a normal retirement or register write for that instruction. Although dispatch normally isolates faults already known there, C still handles an older successful prefix correctly.

A control instruction offers its resolved next PC to recovery and retires only when that request is accepted. This applies to both taken and not-taken branches. A successful store offers one request, remembers acceptance, waits for its response, then retires. An error response instead attaches a store-access fault; no successful store retirement occurs. The external memory contract must ensure an error response means the store did not perform an irreversible write.

FENCE waits for the data adapter to be idle. Since earlier memory operations already execute alone and complete before younger memory begins, this is a conservative ordering point. Successful non-control singletons pulse `serial_done_o` to release dispatch. Branches release through redirect acceptance; faults release through the EEI resume path.

## 18. memory_adapter.sv: remember which client owns the response

[Open memory_adapter.sv](../../rtl/superscalar/memory_adapter.sv). MEM loads and C stores share one external data port. State holds phase, a store-owner bit, a buffered request and a buffered response.

Phase 0 accepts a client request; stores have defensive priority. Phase 1 holds the external request stable until ready. Phase 2 waits for one response. Phase 3 holds that response for the original client until it consumes it. The adapter then returns to idle. The owner bit prevents a load response from being interpreted as a store acknowledgement.

Only one transaction can be outstanding. There is no ID allocation, burst protocol or AXI logic here. A request remains valid while stalled, and a returned response remains buffered while its client stalls. Reset must be coordinated with the external memory endpoint so a pre-reset response is not mistaken for a new transaction.

## 19. control_hazard_unit.sv: enforce the singleton interval

[Open control_hazard_unit.sv](../../rtl/superscalar/control_hazard_unit.sv). Its state stores `serial_busy`, `redirect_valid` and `redirect_pc`. `start_fire` means DP's singleton request was accepted. Acceptance requires the backend and data adapter to be empty and no pending serial or redirect work.

Starting a singleton blocks younger dispatch immediately and stops new sequential fetch work. `serial_done_i` clears that block after a successful non-control singleton. Accepted branch/trap redirect requests latch the new PC and flush the required pipeline region. A pending redirect remains unchanged until fetch accepts it; that acceptance clears redirect ownership and serial-busy.

`branch_fire` and `trap_fire` are accepted events, not merely high input-valid signals. Trap wins arbitration. A branch flushes the frontend; an EEI restart also clears backend ownership. This conservative controller has no branch predictor or age-selective speculative recovery.

## 20. recovery.sv: report the fault before choosing a new PC

[Open recovery.sv](../../rtl/superscalar/recovery.sv). Recovery wraps the control unit with four phases: IDLE, REPORT, RESUME and REDIRECT. It stores the accepted trap separately from C so C can release the faulting instruction without losing its report.

IDLE accepts a commit trap and cancels younger frontend/backend work. REPORT holds the external EEI trap message until the environment accepts it. RESUME waits for the environment's chosen replacement PC. REDIRECT waits until fetch accepts that replacement, then returns to IDLE.

The CPU does **not** assume every fault should skip four bytes. The simulation environment uses that policy to continue its directed tests; a real environment might terminate the program, emulate an instruction, retry an access or enter a handler. The EEI chooses the resume address. No privileged trap CSRs are silently invented by this interface.

## 21. core.sv: the wiring diagram made executable

[Open core.sv](../../rtl/superscalar/core.sv). Core adds no architectural storage of its own. Seven packet channels connect IF→D through WB→C. Their valid signals flow forward; readiness flows backward. The external instruction interface connects directly to fetch. The data interface connects through the adapter.

`read_indices/read_values/live_operands` connect R and the register file. `writes` fans out from C to the register file, scoreboard, R bypass and DP snapshot refresh. `allocate` goes from accepted DP issue to the scoreboard. The producer array is ordered EX, MEM, WB, C, with lanes reversed within each stage so forwarding searches youngest first.

`occupied` includes EX, MEM, WB and C. `backend_empty` additionally requires `memory_idle`. A singleton cannot begin merely because EX is empty while an older store is waiting in C. `front_flush` goes to IF/D/R/DP. `back_flush` goes to EX/MEM/WB and clears scoreboard ownership. The register file preserves committed values across a trap; C hands its fault to recovery rather than being blindly erased by its own flush.

## 22. examples/superscalar/pipe_reg.sv: the storage lesson

[Open pipe_reg.sv](../../examples/superscalar/pipe_reg.sv). This standalone teaching example is not instantiated by core. It demonstrates the elastic one-slot rule in isolation: accept when empty or when the current occupant is leaving; hold occupied data under backpressure; replace on simultaneous consume/accept; clear occupancy after consume without replacement. Reset and kill clear validity. It does not manage outstanding memory transactions, so fetch and the adapter need richer state machines.

## 23. Walk one dependency through the connected design

Consider `ADDI x5,x0,7` followed by `ADD x6,x5,x5`. Fetch supplies their words/PCs. D identifies operations and source/destination fields. R reads committed state; x5 might still be zero. DP sees the within-packet dependency and sends only ADDI. The scoreboard marks x5 busy, and ADD remains in the retained suffix.

EX computes seven and advertises a ready x5 producer. DP resolves both ADD operands to seven through forwarding, even before ADDI commits. ADD later computes fourteen. C retires ADDI before ADD, so architectural state changes in program order. If ADD waits longer, C's write refreshes DP's snapshot before the producer disappears. Both paths preserve the same architectural result.

Now consider a load. DP waits for all older backend work to finish, starts its singleton interval, and blocks younger issue. EX calculates/checks the address. MEM sends one request and waits. The adapter buffers ownership and response. MEM records the value. WB holds it. C writes its destination and signals serial-done. Only then can younger work issue. This is intentionally conservative and easy to audit.

## 24. Test files, build files and what the evidence means

`rtl/superscalar/skeleton.f` retains its historical filename but is now the complete active CPU manifest. Its order places packages before consumers. `rtl/superscalar/files.f` remains the smaller hazard-only manifest. `rtl/files.f` describes the separate historical OoO experiment; never combine the two designs' ALU/core sources in one build.

`tests/superscalar/core_vectors.py` constructs a deterministic binary program and executes it with an independent sequential Python interpreter. It decodes instruction bits independently of the RTL enums/helpers. It writes instruction memory, expected retirement/trap events, expected final data memory and a small test configuration under ignored `build/core-vectors/`.

`tests/superscalar/core_tb.sv` instantiates the real core plus minimal simulation memory and EEI endpoints. It varies request acceptance and response latency, observes every retired lane, compares register and memory trace results with the oracle, checks faults and final memory, and checks held requests/traps for stability. No processor stage is replaced with a fake. The EEI resumes after directed faults and stops on the final breakpoint.

`check_core.sh` regenerates vectors, runs strict full-core lint, builds the simulator and runs multiple deterministic timing schedules. `check_skeleton.sh` now runs strict integration lint without empty-shell warning suppressions. `check_decode.sh`, `check_alu.sh` and `check_hazards.sh` keep the focused tests. Their `.sv` testbenches drive inputs and compare outputs; the decoder/ALU Python vector files provide reference records. `validation.md` records scope and reproducible commands. CI runs these checks on changes.

```powershell
wsl -d Ubuntu -- bash scripts/check_core.sh
wsl -d Ubuntu -- bash scripts/check_decode.sh
wsl -d Ubuntu -- bash scripts/check_alu.sh
wsl -d Ubuntu -- bash scripts/check_hazards.sh
python scripts/build_superscalar_docs.py --check
```

Run commands from the repository root. On Linux, omit the `wsl -d Ubuntu --` prefix. Test generation uses Python's standard library; simulation uses Verilator, a C++ compiler and make. Quartus is for the later FPGA synthesis/integration step; simulation should be your first correctness check.

`docs/superscalar/implementation.md` is this explanation. Other Markdown chapters provide foundations, architecture alternatives, exercises, contracts and the build order. `scripts/build_superscalar_docs.py` embeds those chapters plus current RTL into the offline HTML and validates its links/anchors. Edit Markdown or RTL, regenerate HTML, then run `--check`; do not manually patch the generated HTML.

Simulation is evidence for the exercised programs and handshakes, not an exhaustive ISA certification or a timing/area result. Formal proof, additional independent architectural suites, synthesis, FPGA memory integration and hardware testing remain separate validation tasks. For normative instruction semantics, consult the [official RV32I specification](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html); pipeline timing and EEI choices in this chapter are repository design decisions.
