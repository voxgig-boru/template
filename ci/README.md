# ci/ — continuous-integration code

The CI *logic* lives here as runnable shell scripts, so the same steps run
locally and in GitHub Actions. The workflow YAML just invokes them.

GitHub blocks pushes that **create or update files under
`.github/workflows/`** unless the pushing token carries the `workflow` OAuth
scope. The automation that maintains this repo doesn't have that scope, so
the workflow is maintained here as `ci/test.yml` and a maintainer promotes
it; the scripts it calls (and which you can run directly) are the real CI
code.

## What's here

| File | Purpose |
|------|---------|
| `boru-ref` | what to track: `main` (resolved to its HEAD at run time) or a full commit SHA |
| `build-boru.sh` | ensure a `boru` built at that ref is available; echoes its path (idempotent, cached) |
| `run-tests.sh` | build boru, run every `test/*.aql` suite (exit 0 + `all green`), then `boru check template.aql` (0 errors) |
| `check-consistency.sh` | skill-copy drift, JSON manifest validity, and no retired boru flags in the scripts |
| `test.yml` | the GitHub Actions workflow — three jobs that call the scripts above and `test/divergence/run.sh` |

Run any of them from the repo root:

```bash
ci/run-tests.sh                                       # build boru and run the suites
ci/check-consistency.sh                               # packaging guard (no boru needed)
test/divergence/run.sh                                # gating run + check, per suite
BORU=$HOME/.local/bin/boru test/divergence/run.sh     # same, reusing a binary
```

## The tracked ref

The library tracks boru-lang/boru **main** — there is no pinned commit.
`ci/boru-ref` says `main`; `build-boru.sh` resolves it to main's current HEAD
(or uses a `BORU_REF` the workflow resolved once and passed in), and the
workflow's cache key is that SHA, so a new main HEAD forces a rebuild. Last
verified against boru main @ `64c5ab2` (2026-10-01).

boru main has **one execution path**: `boru X` compiles the program to
bytecode and runs it on the VM (after a static pre-flight check whose errors
block the run), or fails with `[boru/compile_failed] … compiler defect`. The
flags `--compile`, `--force-compile` and `--no-compile` are retired (usage
errors); `check-consistency.sh` fails if a script still passes one.

The build is from a codeload source tarball, `cmd/go` → `./boru`, with
`GOWORK=off` (the tarball carries boru's `go.work`, and `GOFLAGS=-mod=mod` is
refused in workspace mode).

## The workflow's three jobs

1. **test** — `ci/run-tests.sh`: build boru at main HEAD (cached), run all
   eight suites, then check the module standalone (0 errors; infos expected
   — see [`../test/divergence/README.md`](../test/divergence/README.md)).
2. **divergence** — `test/divergence/run.sh`: every suite must run green
   under `boru X` and report 0 errors under `boru check X`, and the module
   must check clean. Self-contained (builds its own boru via a `codeload`
   tarball). The name is historical: it used to compare the interpreter
   with the byte compiler, which no longer exist as separate paths.
3. **consistency** — `ci/check-consistency.sh`: skill-copy drift, JSON
   manifests, retired flags.

## Promoting the workflow (maintainer)

`.github/workflows/test.yml` is a promoted copy of `ci/test.yml`. They run
the same jobs and steps; after the boru-main migration the promoted copy
still carries the old comments and step names (it calls the same scripts,
so it works unchanged). From a clone with `workflow` scope (or the GitHub
web editor):

```bash
cp ci/test.yml .github/workflows/test.yml
git commit -am "ci: re-promote the workflow (comments and step names)"
git push
```
