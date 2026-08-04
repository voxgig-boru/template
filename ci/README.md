# ci/ — continuous-integration code

The CI *logic* lives here as runnable shell scripts, so the same steps run
locally and in GitHub Actions. The workflow YAML just invokes them.

GitHub blocks pushes that **create or update files under
`.github/workflows/`** unless the pushing token carries the `workflow` OAuth
scope. The automation that maintains this repo doesn't have that scope, so
the workflow is staged here as `ci/test.yml` and a maintainer promotes it;
the scripts it calls (and which you can run directly) are the real CI code.

## What's here

| File | Purpose |
|------|---------|
| `aql-ref` | the pinned `boru` commit — **single source of truth** for the ref |
| `build-aql.sh` | ensure an `boru` built at `aql-ref` is available; echoes its path (idempotent, cached) |
| `run-tests.sh` | build boru + run every `test/*.aql` suite + an advisory `boru check` |
| `check-consistency.sh` | skill-copy drift, JSON manifest validity, and pinned-ref consistency across files |
| `test.yml` | the GitHub Actions workflow — three jobs that call the scripts above and `test/divergence/run.sh` |

Run any of them from the repo root:

```bash
ci/run-tests.sh          # build boru and run the suites
ci/check-consistency.sh  # packaging + pinned-ref guard (no boru needed)
test/divergence/run.sh   # gating interpret / check / compile agreement
```

## The pinned ref

`ci/aql-ref` holds the 40-char `boru` commit this library is verified
against. `build-aql.sh`, `run-tests.sh`, the workflow's cache key, and
`check-consistency.sh` all read it; `check-consistency.sh` additionally
asserts the copies hardcoded in `.claude/hooks/session-start.sh`,
`test/divergence/run.sh`, and `api.json` (by prefix) match it. To adopt a
newer boru, edit `ci/aql-ref`, update those three files, and re-run the
suites.

## The workflow's three jobs

1. **test** — `ci/run-tests.sh`: build boru at `aql-ref` (cached), run all
   eight suites, advisory `boru check` (non-gating — see
   [`../dx-report.md`](../dx-report.md) §11).
2. **divergence** — `test/divergence/run.sh`: asserts every suite
   interprets, checks (0 errors), and is byte-identical under
   `boru --compile`. Self-contained (builds its own boru via a `codeload`
   tarball).
3. **consistency** — `ci/check-consistency.sh`: skill-copy drift, JSON
   manifests, pinned-ref single-source-of-truth.

## Promoting the workflow (maintainer, one-time)

The live `.github/workflows/test.yml` is the **stale** bloom-era copy; this
`ci/test.yml` supersedes it. From a clone with `workflow` scope (or the
GitHub web editor):

```bash
cp ci/test.yml .github/workflows/test.yml
git commit -am "ci: adopt the template workflow (scripts in ci/)"
git push
```

The workflow calls `ci/*.sh` and reads `ci/aql-ref`, so it works unchanged
the moment it lands under `.github/workflows/`.
