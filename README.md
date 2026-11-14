# Four-wide RV32I superscalar processor laboratory

## Current project: eight-stage in-order superscalar

**The complete baseline pipeline is implemented.** Start with
[the file-by-file implementation walkthrough](docs/superscalar/implementation.md)
and [core.sv](rtl/superscalar/core.sv). It includes four-wide ordered arithmetic,
forwarding, scoreboarding, singleton memory/control execution, commit-only
architectural updates, memory ownership and EEI trap/resume recovery.

Run `wsl -d Ubuntu -- bash scripts/check_core.sh` for strict lint and full-core
simulation against an independent Python architectural oracle. See
[validation scope](docs/superscalar/validation.md). This is an educational abstract-port
processor; FPGA/SoC integration and timing/area validation remain future work.

`rv32_decode.sv` now decodes all 40 RV32I operations combinationally. Run
`wsl -d Ubuntu -- bash scripts/check_decode.sh` for strict lint and 99,496
generated encode-to-decode vectors checking complete output records. See
[decoder validation and conventions](docs/superscalar/validation.md).

The superscalar `alu.sv` is also implemented. Run
`wsl -d Ubuntu -- bash scripts/check_alu.sh` for strict lint and 16,936 arithmetic,
comparison, shift and default-result checks against a Python integer oracle.

Use `wsl -d Ubuntu -- bash scripts/check_skeleton.sh` for strict full-core lint.
The skeleton and historical OoO manifests must not be combined in one build.

**Instruction fetch → Decode → Register → Dispatch → Execute → Memory → Writeback → Commit**

Start with the [beginner's guide](docs/superscalar/beginner.md), then read the
[architecture reference](docs/superscalar/tutorial.md) and
[module walkthroughs](docs/superscalar/modules.md). These render on GitHub.
The [standalone HTML course](docs/superscalar/tutorial.html) combines all three
with the implementation workbook, a [30-lesson architecture course](docs/superscalar/course.md),
[17 practical labs](docs/superscalar/labs.md), and expandable actual RTL listings.
The course connects each module to design alternatives: prediction, multiport
register files, scheduling, caches, memory ordering, renaming, ROBs, recovery,
verification and implementation. Advanced mechanisms are study/extension paths;
they are not features implemented by the current baseline.
Download/open it locally for chapter filtering and internal navigation. It covers
clock edges, all eight stages, worked instructions, forwarding, packet splitting,
memory ownership, precise commit, recovery, and implementation/verification steps.

The [pipeline register example](examples/superscalar/pipe_reg.sv) demonstrates the
assignment-only `always_ff` convention used throughout the implementation.
Earlier labs remain useful as guided reimplementation exercises.

```powershell
python scripts/build_superscalar_docs.py
python scripts/build_superscalar_docs.py --check
wsl -d Ubuntu -- verilator --lint-only -Wall --top-module pipe_reg examples/superscalar/pipe_reg.sv
wsl -d Ubuntu -- bash scripts/check_hazards.sh
```

New modules live in `rtl/superscalar/`, with tests in `tests/superscalar/`.
Design documents live in `docs/superscalar/`; small RTL examples live in
`examples/superscalar/`. The HTML builder uses Python's standard library. Edit
`implementation.md`, `beginner.md`, `course.md`, `labs.md`, `tutorial.md`, `skeleton.md`, `modules.md` or `build-guide.md`, then regenerate the
HTML. The builder embeds every source in `skeleton.f` plus the pipeline-register
example and checks local links and internal anchors. Regenerate after RTL edits
too; CI's `--check` rejects stale source listings. No network is needed to read
the handbook; external specification links require a connection.

Ready to code? The [step-by-step build guide](docs/superscalar/build-guide.md)
is the final section of the HTML, after the RTL listings. Start with ADDI decode
and ALU checks, then follow its checkpoints through single-lane integration,
control/memory, four-lane operation and full-core validation.

## Historical experiment: out-of-order backend

The files directly under root `rtl/` and `tests/` below are the earlier OoO experiment. They
are retained for reference and are not the implementation of the current design.

Start with [the complete HTML tutorial](docs/tutorial.html) (download/open locally;
GitHub's file viewer does not render HTML). Open [rtl/ooo_core.sv](rtl/ooo_core.sv)
to follow the module connections.

This first milestone is a working **instruction-stream out-of-order backend**,
not a complete RV32I CPU. It implements 21 integer computation instructions,
eight unified reorder/reservation slots, implicit register renaming, oldest-ready
issue, a three-stage result pipeline, broadcast wakeup and in-order retirement.
Unsupported encodings produce a terminal retirement fault; reset restarts it.
There is no fetch unit, branch execution, memory interface, architectural trap
handler, CSR file, cache, MMU, privileged mode, or extension implementation yet.

## Run

On this Windows workspace, Ubuntu WSL already has Verilator and the build tools:

```powershell
wsl -d Ubuntu -- make check
python scripts/build_docs.py
python scripts/check_repo.py
code --reuse-window . --goto rtl/ooo_core.sv:1
```

On Linux, run `make check` from the repository root. Requirements are Verilator
with SystemVerilog support, GNU Make, a C++17 compiler, and Python 3 for docs.
For Ubuntu missing these tools: `sudo apt-get install verilator make g++ python3`.
The VS Code default build task uses this machine's Ubuntu WSL distribution;
select the Linux task when using VS Code inside WSL or on Linux.

## Layout

| Path | Purpose |
| --- | --- |
| `rtl/` | Synthesizable teaching RTL and ordered compilation manifest |
| `tests/` | Deterministic architectural differential simulation |
| `docs/tutorial.html` | Standalone, searchable tutorial with embedded RTL |
| `docs/chapters.html` | Editable tutorial prose |
| `docs/architecture.md` | Interface contract and baseline design decisions |
| `docs/roadmap.md` | Milestones and acceptance gates |
| `docs/validation.md` | Actual test results and remaining verification work |
| `scripts/` | Dependency-free documentation generation and structural checks |
| `.github/` | CI and pull-request guidance |
| `.vscode/` | Editor recommendations and build tasks |
| `build/` | Ignored generated simulator files |

RTL convention: all next-state and reset logic is in `always_comb`; each
`always_ff` body contains only nonblocking state assignments. Synchronous reset
must span a rising clock edge. No initial blocks or delays appear in RTL.

See [CONTRIBUTING.md](CONTRIBUTING.md) before extending the core. Sources and
algorithm explanations are included in the tutorial. No license has been chosen
on the repository owner's behalf. No silicon, frequency, power, compliance, or
GitHub CI result is claimed by the local simulation.
