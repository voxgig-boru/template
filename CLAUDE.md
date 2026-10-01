# CLAUDE.md

This repository is the `Template` library: sandboxed templating languages
written in boru. Four engines — `mustache`, `handlebars`, `liquid`, and
`jinja` — are implemented on one shared pipeline, selected by the `engine`
field with identical config and context data.

## Using the library

See @AGENTS.md for how to call the `Template` API correctly from boru — the
calling convention, the full API, copy-paste idioms, and the common
mistakes to avoid. Every example there was executed against boru main @
`64c5ab2` (2026-10-01).

## How it works

Each engine follows one pipeline (see the header of `template.aql`):

1. **Parse** — `boru:parse` defines the template grammar. A custom lex
   matcher segments the source into a typed token stream and a declarative
   `Parse.rule` recognizes it, registered as a `parse <engine>` kind.
   mustache/handlebars share the `{{ }}` lexer; liquid adds `{% %}`; jinja
   adds `{# #}`.
2. **Compile** — the token stream is lowered to a boru program: a fixed
   runtime prelude of custom `tpl_*` words plus a `__render` function that
   builds the output by calling only those words. mustache and handlebars
   have their own compilers; liquid and jinja share one `compile-tagged-seq`
   over the union of their tag vocabularies.
3. **Run** — the program executes through `boru:vm` in a fresh sub-engine
   under a totally restricted policy (every capability scope uninstalled),
   so a template can never do I/O or escape the sandbox.

## Working on this repository

- A SessionStart hook (`.claude/settings.json` →
  `.claude/hooks/session-start.sh`) builds `boru` from boru-lang/boru
  **main** HEAD in remote sessions, so a fresh session can run the suites.
  It fetches via the codeload tarball (the `boru-lang/boru` git remote is
  egress-blocked behind the agent proxy), falls back to `git clone`, and
  builds `cmd/go` → `./boru` with `GOWORK=off`. Locally, build once from
  source — see [docs/how-to.md](docs/how-to.md#install-and-run-boru).
- The library tracks boru **main** — no pinned commit: the hook, CI
  (`ci/boru-ref` = `main`) and the gate all resolve main HEAD at run time.
  Last verified against boru main @ `64c5ab2` (2026-10-01).
- **One execution path.** `boru X` runs a static pre-flight check, then
  compiles to bytecode and runs on the VM, or fails with
  `[boru/compile_failed] … compiler defect`. There is no interpreter
  fallback; `--compile` / `--force-compile` / `--no-compile` are retired
  (usage errors). "A suite runs" means "a suite fully compiles". Never use
  `-no-check` to get green.
- Relative imports resolve against the **importing file's directory**: the
  suites in `test/` and the harnesses in `bench/` import
  `"../template.aql"`.
- Tests live in `test/`, named `<subject>_<unit|prop>_<test|spec>.aql` plus
  a `template_smoke_test.aql`: `_test` = imperative (`Test.test` /
  `Test.check-prop`), `_spec` = declarative spec; `unit` = example-based,
  `prop` = property-based. Each assertion-bearing suite ends with
  `Assert.equal 0 (Test.fail-count)` and prints `all green`. Run them all
  with `for f in test/*.aql; do boru "$f"; done`.
- `test/divergence/run.sh` is the gate (CI calls it): every suite exits 0
  under `boru <suite>` and prints `all green` where it asserts, and
  `boru check` reports 0 errors on every suite and on `template.aql`.
  `BORU=/path/to/boru test/divergence/run.sh` reuses a binary; without it
  the script builds boru @ main HEAD. All 8 suites and the module pass it
  on `64c5ab2`.
- Three spots in `template.aql` carry commented workarounds for open boru
  compiler/runtime defects (`split-args`, the `*-cidx` names in
  `compile-hb-seq` and friends, and `(body m4/v)` / `(body c4/v)` in the
  sandbox runtime); minimal repros are in `dx-report.md`'s migration
  section. Remove them when upstream fixes land.
- Known boru-runtime gotchas observed building this module are in
  `dx-report.md` (the migration to boru main @ `64c5ab2` first, then the
  original findings: the `fn`-body def-time trace, argument binding,
  map-literal scoping, and the unenforced `boru:vm` step budget).
  Performance numbers are in `bench/BASELINE.md` — renders got ~20× slower
  on boru main because the sandbox sub-engine now compiles every program.
- All four engines are implemented and green (mustache unit/prop/spec +
  an all-engines smoke, plus a unit suite each for handlebars/liquid/jinja).
  The Diátaxis docs (`docs/`), the agent guides (`AGENTS.md`, this file, the
  `template-aql` skill + bundled plugin — the two SKILL.md copies must stay
  byte-identical — and `api.json`), and CI (`ci/test.yml`, the canonical
  workflow, promoted to `.github/workflows/test.yml` — see `ci/README.md`)
  are all current for `Template`.
