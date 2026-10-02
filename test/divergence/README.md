# Single-path gate: run · check

This library's `.aql` suites must run green on boru **main**. `run.sh` is the
gate CI calls: for every suite it runs

```bash
boru X         # compile X to bytecode and run it on the VM — the only path
boru check X   # static check — must report 0 errors
```

and then checks the library module on its own:

```bash
boru check template.aql   # must report 0 errors
```

A suite passes when `boru X` exits 0 — and, for a suite that asserts (it
reads `Test.fail-count`), also prints `all green` — and `boru check X`
reports 0 errors.

## Why the interpreter / `--compile` columns are gone

The harness used to assert that three surfaces agreed: the interpreter
(`boru --no-compile X`), `boru check X`, and the byte compiler
(`boru --compile X`, with a `--force-compile` coverage line). Since boru
2026-09-19 there is **one execution path**: `boru X` compiles the program to
bytecode and runs it on the VM, or fails with
`[boru/compile_failed] … this is a compiler defect`. There is no interpreter
fallback, and `--compile`, `--force-compile`, `--no-compile` (and the
`BORU_COMPILE` / `BORU_FORCE_COMPILE` / `BORU_NO_COMPILE` env vars) are
retired — passing them is a usage error. With nothing left to diverge from,
"the suite runs" now *means* "the suite fully compiles", so the gate is run +
check. `boru X` also runs the static pre-flight check first and refuses on a
check error; the harness never passes `-no-check`.

The directory keeps its old name so CI and the docs that call
`test/divergence/run.sh` keep working.

## Running it

```bash
test/divergence/run.sh                              # build boru @ main HEAD (cached)
BORU=$HOME/.local/bin/boru test/divergence/run.sh   # reuse a binary, no network
BORU_REF=<sha> test/divergence/run.sh               # build a specific ref
```

Without `BORU`, `run.sh` builds its own boru so it never depends on whatever
is on `PATH`: a codeload source tarball of `boru-lang/boru` (works where a
raw `git clone` is blocked), built from `cmd/go` as `./boru` with
`GOWORK=off` (the tarball carries boru's `go.work`, and `-mod=mod` is refused
in workspace mode), cached in `~/.cache/boru-divergence` by the resolved SHA.
`BORU_TIMEOUT` (default 600 s) caps each invocation. Output:

```
  SUITE                         RUN                   CHECK         SECONDS
  template_unit_test.aql        ok                    ok            7
  ...
  jinja_unit_test.aql           ok                    ok            7

[divergence] modules — boru check must report 0 errors:
  template.aql                  ok
```

It exits non-zero on any compile failure, run failure, missing `all green`,
timeout, or check **error**. Warnings and infos are not gating; the current
ones are listed in [`../../dx-report.md`](../../dx-report.md) ("Migration to
boru main @ 64c5ab2").

## What `boru check template.aql` reports now

Checked standalone the module reports **0 errors** on boru main @ `64c5ab2`
(earlier builds reported false-positive errors there, because the engines'
parsers are registered at run time). What remains are six infos: three
`macro_not_expandable` (the runtime-registered `parse <engine>` calls are
dynamic and unchecked) and three `late_binding` notes about names the
mutually recursive compiler helpers read before their definition.
