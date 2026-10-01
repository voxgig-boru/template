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

## Current numbers — boru main @ `64c5ab2` (2026-10-01)

Linux x86-64, 4 cores **shared with other jobs** (load average 3–6 during the
runs), so treat these as upper bounds; one run each, `real` wall-clock.

| Measurement                          | Wall-clock | Fixed startup | Marginal per op |
|--------------------------------------|-----------:|--------------:|----------------:|
| Fixed startup (`import template.aql`)|     ~3.5 s |             — |               — |
| `Template.compile` × 800             |    ~15.4 s |        ~3.5 s |     **~15 ms**  |
| `Template.render` × 800              |     ~239 s |        ~3.5 s |    **~295 ms**  |

Derived throughput: **~67 compiles/sec**, **~3.4 renders/sec** (single core).

### Why render got ~20× slower

Each render runs the generated program (the ~6 KB `tpl_*` runtime prelude
plus `__render` and the injected context) through `Vm.run-with` in a fresh
sub-engine. On boru main that sub-engine, like every other boru program,
**compiles the program to bytecode before running it**; on the earlier
builds it interpreted it. Measured directly: 20 × `Vm.compile` of a
generated program costs ~4.5 s (~225 ms each), against ~280 ms per full
render — so compiling the sandbox program is nearly all of the per-render
cost. `boru:vm` exposes no way to reuse a compiled program across runs, so
"compile once, render many" amortizes `Template.compile` (the parse and code
generation) but not the sub-engine's own bytecode compile. Startup rose from
~0.7 s to ~3.5 s for the same reason: `template.aql` itself is compiled
before it runs.

Possible mitigations (not applied — they change the runtime, not the API):
emit only the `tpl_*` words a template actually uses, shrinking what the
sub-engine compiles per render; or, upstream, a `boru:vm` word that runs a
pre-compiled program against fresh data.

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
