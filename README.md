# Four-wide RV32I superscalar processor laboratory

## Current project: eight-stage in-order superscalar

**Instruction fetch → Decode → Register → Dispatch → Execute → Memory → Writeback → Commit**

Start with the [current design tutorial](docs/superscalar/tutorial.md), which
renders on GitHub, or download the [standalone HTML edition](docs/superscalar/tutorial.html).
It specifies the stage contracts, hazards, packet splitting, precise commit,
memory protocol and implementation sequence for a four-wide RV32I target.

This is a design specification with standalone hazard RTL, not a complete CPU yet.
[Forwarding](rtl/superscalar/forwarding_unit.sv) and
[control hazards](rtl/superscalar/control_hazard_unit.sv) now have implemented
modules and directed simulation. Their integration contracts and the pipeline
assessment are in tutorial sections 21–23. The
[pipeline register example](examples/superscalar/pipe_reg.sv) demonstrates the
assignment-only `always_ff` convention. Start with one lane through all eight
stages, then widen the verified protocol to four lanes. See the
[current roadmap](docs/superscalar/roadmap.md).

```powershell
python scripts/build_superscalar_docs.py
python scripts/build_superscalar_docs.py --check
wsl -d Ubuntu -- verilator --lint-only -Wall --top-module pipe_reg examples/superscalar/pipe_reg.sv
wsl -d Ubuntu -- bash scripts/check_hazards.sh
```

New modules live in `rtl/superscalar/`, with tests in `tests/superscalar/`.
Design documents live in `docs/superscalar/`; small RTL examples live in
`examples/superscalar/`. The HTML builder uses Python's standard library.

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
