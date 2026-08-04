# CLAUDE.md

This repository is the `Template` library: sandboxed templating languages
written in boru. Four engines — `mustache`, `handlebars`, `liquid`, and
`jinja` — are implemented on one shared pipeline, selected by the `engine`
field with identical config and context data.

## Using the library

See @AGENTS.md for how to call the `Template` API correctly from boru — the
calling convention, the full API, copy-paste idioms, and the common
mistakes to avoid. Every example there is verified against the pinned
`boru` build.

## How it works

Each engine follows one pipeline (see the header of `template.aql`):

1. **Parse** — `boru:parse` defines the template grammar. A custom lex
   matcher segments the source into a typed token stream and a declarative
   `Parse.rule` recognizes it, registered as a `parse <engine>` kind.
   mustache/handlebars share the `{{ }}` lexer; liquid adds `{% %}`; jinja
   adds `{# #}`.
2. **Compile** — the token stream is lowered to an boru program: a fixed
   runtime prelude of custom `tpl_*` words plus a `__render` function that
   builds the output by calling only those words. mustache and handlebars
   have their own compilers; liquid and jinja share one `compile-tagged-seq`
   over the union of their tag vocabularies.
3. **Run** — the program executes through `boru:vm` in a fresh sub-engine
   under a totally restricted policy (every capability scope uninstalled),
   so a template can never do I/O or escape the sandbox.

## Working on this repository

- A SessionStart hook (`.claude/settings.json` →
  `.claude/hooks/session-start.sh`) builds `boru` from the pinned commit in
  remote sessions, so a fresh session can run the suites. It fetches via
  the codeload tarball (the `boru-lang/boru` git remote is egress-blocked
  behind the agent proxy) and falls back to `git clone`. Locally, build
  once from source — see [docs/how-to.md](docs/how-to.md#install-and-run-aql).
- The pinned boru commit is **latest main** (`6185620…`), single-sourced in
  the SessionStart hook's `BORU_REF`. Several fixes this module relies on
  (notably `get` evaluating a dynamic key argument) landed after the older
  `407feda` pin the template was forked from.
- Tests live in `test/`, named `<subject>_<unit|prop>_<test|spec>.aql` plus
  a `template_smoke_test.aql`: `_test` = imperative (`Test.test` /
  `Test.check-prop`), `_spec` = declarative spec; `unit` = example-based,
  `prop` = property-based. Each assertion-bearing suite ends by asserting
  `Test.fail-count` is `0` and prints `all green`. Run them all with
  `for f in test/template_*.aql; do boru "$f"; done`.
- Known boru-runtime gotchas observed building this module are in
  `dx-report.md` (the `fn`-body def-time trace, mixed argument-order
  conventions, map-literal scoping, and the unenforced `boru:vm` step
  budget).
- All four engines are implemented and green (mustache unit/prop/spec +
  an all-engines smoke, plus a unit suite each for handlebars/liquid/jinja).
  The Diátaxis docs (`docs/`), the agent guides (`AGENTS.md`, this file, the
  `template-aql` skill + bundled plugin, `api.json`), and CI (`ci/test.yml`,
  the canonical workflow — see `ci/README.md`) are all current for
  `Template`. The `.github/workflows/test.yml` on `main` is the older
  bloom-era copy, superseded by `ci/test.yml` (promoting it needs `workflow`
  token scope).
