# Contributing

The active architecture is `docs/superscalar/tutorial.md`; its roadmap is
`docs/superscalar/roadmap.md`. Existing root `rtl/` and tests are historical OoO
work. Do not relabel them as a superscalar implementation. Build the new HTML
with `python scripts/build_superscalar_docs.py`; verify it using `--check`.

Keep each change focused on a roadmap milestone. Explain the architectural
contract before changing interfaces. Put reusable types in the package and
module-specific state next to its next-state logic. Use `_q` for current state,
`_d` for next state, `_i` for inputs and `_o` for outputs.

All RTL logic belongs in `always_comb` with defaults on every path. Use only
nonblocking assignments in `always_ff`; even reset selection belongs in the
combinational block. Do not introduce asynchronous reset without revisiting
this documented convention with the owner. Avoid implicit nets, magic opcode
changes, unexplained lint suppression, incomplete assignments and inferred
latches. A packed state struct is useful here but is not a recommendation to
reset large future SRAM data arrays.

Run `make check`, `python scripts/build_docs.py`, and `python scripts/check_repo.py`.
Keep generated documentation synchronized. Explain new invariants and add tests
that would fail for the bug or missing behavior, including overlapping pipeline
events. Report the exact tool version and command for any performance claim.

Never describe a subset as ISA compliant. Never mark a roadmap feature complete
because its interface exists. Link architectural claims to primary sources;
record specification versions. Do not invent board constraints, memory maps,
software ABI support, frequency, power, or area. Choose a target before writing
platform constraints. CI is proposed infrastructure until it runs on GitHub.
