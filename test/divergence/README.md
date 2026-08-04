# Three-way test check: interpreter · check · byte compiler

This library's `.aql` suites are written once and must mean the same thing
no matter how `boru` runs them. `run.sh` runs every suite through all three
execution surfaces and asserts none errors or disagrees:

```bash
boru X            # interpreter — the default; what CI and users run
boru check X      # static type-check — must report 0 errors
boru --compile X  # byte compiler — bytecode when compilable, else a SILENT
                 #   fallback to the interpreter; documented to be IDENTICAL
                 #   to it ("opt-in performance, never semantics")
```

It also prints an `boru --force-compile X` coverage line per suite — how much
of each program the bytecode emitter can fully lower today. Refusals there
are expected gaps (under `--compile` they fall back to the interpreter), not
failures.

## Running it

```bash
test/divergence/run.sh
```

`run.sh` builds its own boru at a ref pinned in the script (the same
`6185620` the library pins; pinning it here keeps the harness
self-contained, so it never depends on whatever boru is on `PATH`), then
prints a per-suite matrix:

```
  SUITE                         INTERPRETER   CHECK           BYTECODE
  template_unit_test.aql           ok            ok              ok
  template_unit_spec.aql           ok            ok              ok
  ...
  jinja_unit_test.aql              ok            ok              ok
```

It exits non-zero on any interpreter failure, any check **error**, or any
difference between `boru --compile X` and `boru X`. Needs `go` + network for
the one-time build (cached in `~/.cache/aql-divergence`).

## What this guards — and an important scoping note

The contract under test is the byte compiler's promise: `boru --compile X`
returns results **identical** to `boru X` (it falls back to the interpreter
for anything it can't lower). For this module that holds — every suite is
byte-identical between the two surfaces.

The harness checks the **test suites**, not `template.aql` directly, and
that distinction matters:

- Checked **through a suite** — where the engines' words run with concrete
  values — `boru check` reports **0 errors** (only advisory `unused_def`
  warnings), so the gate passes.
- Checked **alone**, `boru check template.aql` reports errors. They are
  *not* real defects: the engines register their grammars as a **runtime**
  side effect (`Parse.register`), which a static pass cannot see, so the
  `lex-*` words' `parse <engine>` calls look unresolved; dynamic dispatch
  and the mutually-recursive compiler helpers defeat the checker's flow
  analysis too. A function that errors in-module checks clean in isolation
  — the failures are emergent from whole-module analysis. See
  [`../../dx-report.md`](../../dx-report.md) §11–13 for the full audit.

Consequently `boru --force-compile` (strict bytecode) refuses on those
check diagnostics and falls back; non-strict `--compile` compiles-or-falls-
back and stays byte-identical, which is what this harness gates on.

This guard has value beyond the static facts: the "compile == interpret"
promise has been broken by upstream regressions before, and this is the
cheap, self-contained check that catches a recurrence.
