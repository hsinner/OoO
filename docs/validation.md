# Validation record

Executed locally on 2026-09-07 using the Windows workspace and Ubuntu WSL.

## RTL

Tool output: `Verilator 5.020 2024-01-01 rev (Debian 5.020-1)`.
Command: `wsl -d Ubuntu -- make check`.

```text
verilator --lint-only -Wall --top-module ooo_core -f rtl/files.f
PASS: 20430 retirements, 28979 cycles; OoO issue, backpressure, wraparound, faults and resets observed.
```

Lint completed with no warnings. The regression uses seed `0x52495343` and an
independent C++ architectural interpreter. Reported retirements include terminal
fault events. The cycle counter covers the main stimulus loops, not reset and
post-halt checking edges, and must not be used as a processor IPC benchmark.

Verified checks include:

- Retirement PC, instruction, destination, value and fault comparisons in the
  main directed/random streams.
- RAW dependencies, repeated destinations, zero-register behavior and upper
  immediate operations among the generated programs.
- Observed out-of-order issue; no duplicate or unallocated issue in main runs.
- Input gaps, retirement backpressure and stable stalled retirement payloads.
- Circular tag reuse over long streams and repeated reset/restart.
- Unsupported opcodes and invalid function fields producing ordered faults.
- A dedicated fault with four younger allocated instructions: only the three
  older instructions and the fault event retire.
- Reset with a result in flight: no stale issue or retirement after reset.

The test observes issue passing and admission stalls. It is not an exhaustive
cross-product coverage model, nor a formal proof of every state invariant.

## Repository and document checks

Commands: `python scripts/build_docs.py` and `python scripts/check_repo.py`.
The generated document has 28 tutorial chapters and an RTL appendix containing
eight source listings. The structural check verifies compilation-manifest
coverage, three assignment-only sequential blocks, unique document IDs and
internal anchor targets. This lightweight source-style check is intentionally
specific to the current convention; Verilator handles syntax and elaboration.

Browser QA uses the locally generated HTML, checks rendering, chapter filtering
and opening an embedded source listing. The document is self-contained and can
be opened directly from disk without the temporary preview server.

## Not executed / not established

No GitHub-hosted CI run, synthesis, FPGA run, ASIC implementation, timing closure,
power/area measurement, four-state simulation, formal proof, RISC-V architectural
compliance suite, independent full ISA simulator integration or OS boot has been
performed. Those need additional tooling or future milestone functionality.
The instruction-stream interface does not validate supplied PC alignment.

CI checks out a verified full commit for actions/checkout v7 with read-only
permissions and credential persistence disabled. Its Ubuntu package versions
may differ from this local environment; the workflow prints Verilator's version.
