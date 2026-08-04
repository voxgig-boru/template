# Performance baseline — `Template` library

A reproducible performance baseline for the `Template` library, measured
against the pinned `boru` build. Re-run the harnesses below and compare.

## How to reproduce

```bash
# wall-clock, default (compiled) mode:
time boru bench/compile_bench.aql      # parse + compile throughput
time boru bench/render_bench.aql       # render throughput

# interpreter-only, for the compiled-vs-interpreted comparison:
time boru -no-compile bench/render_bench.aql
```

Each harness compiles one template per engine, then repeats the measured
operation `reps` times across all four engines (`reps` is a `def` at the top
of each file). The reported figures use `reps = 200` (800 operations total).

## Environment

- `boru` built from `boru-lang/boru` **latest `main`** (`203ea2f`, this baseline).
- Linux x86-64, single-threaded (`boru` runs the workload on one core).
- Warm binary/module cache; times are `real` wall-clock, best of three.

## Numbers (reps = 200, 4 engines = 800 ops)

| Measurement                          | Wall-clock | Fixed startup | Marginal per op |
|--------------------------------------|-----------:|--------------:|----------------:|
| Fixed startup (`import template.aql`)|     ~0.70 s |             — |               — |
| `Template.compile` × 800             |    ~10.3 s |        ~0.70 s |     **~12 ms**  |
| `Template.render` × 800              |    ~12.5 s |        ~0.70 s |    **~14.7 ms** |
| Test suite (`template_unit_test`)    |     ~1.3 s |        ~0.70 s |               — |

Derived throughput: **~83 compiles/sec**, **~68 renders/sec** (single core).

## Compiled vs interpreted

| Mode                     | render × 800 |
|--------------------------|-------------:|
| default (`--compile`)    |     ~12.5 s  |
| `--no-compile`           |     ~11.8 s  |

The two modes are within noise of each other. The reason is structural, not a
measurement artifact: the render pipeline runs each template inside a fresh
`boru:vm` sub-engine (the sandbox), and the library's own hot paths — the lexer
matcher and the compile/lower helpers — currently **fall back to the
interpreter** rather than executing as bytecode, because they read a
module-level `flex` accumulator through boru's dynamic scope, a shape the
bytecode compiler does not yet lower soundly (see the diagnosis note below).
The dominant cost per render is therefore the per-render sub-engine setup, which
is identical in both modes.

## What moves these numbers

- **Per-render sandbox setup dominates** render cost. Compiling once and
  rendering many contexts (the intended usage — `AGENTS.md` "compile once,
  render many") amortizes `compile` but not the per-render sub-engine spin-up.
- **Bytecode compilation of the library internals** would help once the
  upstream `flex`-accumulator / dynamic-scope-module-read refusal is resolved
  in `boru`. Until then compiled and interpreted modes are equivalent for this
  library. The one `boru` compiler fix landed alongside this baseline — treating
  a `do {…}` value-eval map as a single (non-variadic) result so a recursive
  or branch-arm `do`-map return compiles instead of refusing "consumes loop
  results" — removes one refusal on that path but does not by itself flip the
  library to fully-compiled (the `flex` read gates it first).

See `dx-report.md` and the aql-side diagnosis for the full refusal frontier.
