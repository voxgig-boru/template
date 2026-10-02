# Performance baseline — `Template` library

A reproducible performance baseline for the `Template` library. Re-run the
harnesses below and compare.

## How to reproduce

```bash
time boru bench/compile_bench.aql      # parse + compile throughput
time boru bench/render_bench.aql       # render throughput
```

Each harness compiles one template per engine, then repeats the measured
operation `reps` times across all four engines (`reps` is a `def` at the top
of each file). The reported figures use `reps = 200` (800 operations total).
The harnesses import `../template.aql` (a relative import resolves against
the importing file's own directory), so they run from any directory.

boru main has **one execution path** — `boru X` compiles the program to
bytecode and runs it on the VM — so there is no compiled-vs-interpreted
comparison to make any more (`-no-compile` is a retired flag).

## Current numbers — boru main @ `64c5ab2` (re-measured 2026-10-02)

Linux x86-64, 4 cores **shared with other jobs** (load average 5–8 during
the runs), so treat these as upper bounds; one run each, `real` wall-clock.
These are for the current code generator (named block fns — see below).

| Measurement                          | Wall-clock | Fixed startup | Marginal per op |
|--------------------------------------|-----------:|--------------:|----------------:|
| Fixed startup (`import template.aql`)|     ~5.4 s |             — |               — |
| `Template.compile` × 800             |    ~21.6 s |        ~5.4 s |     **~20 ms**  |
| `Template.render` × 800              |   ~171.9 s |        ~5.4 s |    **~208 ms**  |

Derived throughput: **~50 compiles/sec**, **~4.8 renders/sec** (single
core). The first migration run (2026-10-01, load 3–6, the earlier
fn-value code shape) measured ~3.5 s startup, ~15 ms per compile and
~295 ms per render.

### Why a render is ~14× slower than in the interpreter era

Each render runs the generated program (the ~5–6 KB `tpl_*` runtime
prelude, the template's generated fns, `__render` and the injected context)
through `Vm.run-with` in a fresh sub-engine. On boru main that sub-engine
runs the source the way `boru X` does — static check, bytecode compile,
then the VM — and only when the compile **fails** does it fall back to the
interpreter (the one place boru keeps an interpreter arm, because the
source is built at run time; `lang/go/boru.go`, `CompiledSubRun`). The
generated programs compile (`Vm.compile` reports `ok`), so every render
pays a full check + compile. On the earlier builds the sub-engine simply
interpreted the program.

Measured directly on the same liquid template (20 iterations each, same
session): **20 × `Vm.compile` ≈ 4.2 s, 20 × render ≈ 4.1 s** — the
sub-engine's compile is essentially the whole per-render cost. `boru:vm`
exposes no way to reuse a compiled program across runs, so "compile once,
render many" amortizes `Template.compile` (the parse and code generation)
but not the sub-engine's own compile. Startup rose from ~0.7 s for the same
reason: `template.aql` itself is checked and compiled before it runs.

### The code shape matters too

The migration's first shape handed each block body to a runtime word as an
anonymous fn value (`tpl_for items 'x' ctx (fn …) (fn …)`). Besides being
miscompiled once blocks nest (dx-report defect G), it was slower to run:
measured back to back in the same session, 200 renders took **79.2 s
(~371 ms each) with the fn-value shape vs 46.0 s (~203 ms each) with the
named block fns**, and on the liquid template above 20 renders took 10.2 s
vs 4.1 s while 20 × `Vm.compile` stayed similar (3.5 s vs 4.2 s) — the
fn-value program spent more time *running* than compiling. The
`Template.compile` cost barely moved (~17.5 ms vs ~20 ms).

Possible further mitigations (not applied): emit only the `tpl_*` words a
template actually uses, shrinking what the sub-engine checks and compiles
per render; or, upstream, a `boru:vm` word that runs a pre-compiled program
against fresh data.

### Reproduce the breakdown

```bash
time boru bench/render_bench.aql       # 800 renders (reps = 200)
```

For the compile-vs-render split, time 20 × `Vm.compile` of a compiled
template's `program` (plus the `def __ctx …` / `(__render __ctx)` tail
`Template.render` appends) against 20 × `Template.render` of the same
template, with `boru:time-util`.

## Earlier baseline — boru `203ea2f` (interpreter era)

| Measurement                          | Wall-clock | Fixed startup | Marginal per op |
|--------------------------------------|-----------:|--------------:|----------------:|
| Fixed startup (`import template.aql`)|     ~0.70 s |             — |               — |
| `Template.compile` × 800             |    ~10.3 s |        ~0.70 s |     **~12 ms**  |
| `Template.render` × 800              |    ~12.5 s |        ~0.70 s |    **~14.7 ms** |
| Test suite (`template_unit_test`)    |     ~1.3 s |        ~0.70 s |               — |

Then, the default (`--compile`) and `--no-compile` modes were within noise of
each other (render × 800: ~12.5 s vs ~11.8 s): the library's hot paths fell
back to the interpreter, and the per-render sub-engine setup dominated.
