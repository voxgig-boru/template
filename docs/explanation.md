# Explanation

Understanding-oriented discussion of how this templating library works and
why it is built the way it is. Read this when you want the *why*; for the
*what*, see the [Reference](reference.md), and for *how to get a job done*,
the [How-to guides](how-to.md).

---

## What the library is for

`Template` renders text templates against a data context, with **one
interface across four templating languages** — mustache, handlebars,
liquid, and jinja. You pick the language with the `engine` field; the
config and context data structures are identical across all of them, so a
codebase can mix engines (or migrate between them) without changing how it
calls the library.

The design goal is a *common spine*: every engine is parsed, compiled, and
run the same way, and only the surface syntax and tag semantics differ.
Adding a fifth engine means adding a lexer and a compiler, not a new
runtime or a new sandbox.

---

## The three-stage pipeline

Every render — for every engine — goes through the same three stages. The
header of [`template.aql`](../template.aql) documents them inline.

### 1. Parse

`boru:parse` is the grammar facility. For each engine the library registers
a `parse <engine>` kind built from:

- a **custom lex matcher** (an boru function) that segments the source into
  a typed token stream — text runs and the engine's tag kinds; and
- a **declarative `Parse.rule`** that recognizes the token stream
  (a push-recursion `val` rule = "zero or more tokens").

The matcher is the lexer: it knows each engine's delimiters
(`{{ }}`/`{{{ }}}` for mustache and handlebars; `{% %}` added for liquid;
`{# #}` added for jinja) and pushes `{t, v}` tokens onto an accumulator
that the compiler reads back.

> **Why a matcher and not pure ABNF.** The task this library was built for
> asked for an ABNF grammar. ABNF was evaluated and rejected for the
> lexer: the structure-first engine under `boru:parse` dispatches on FIRST
> sets rather than backtracking, so an ABNF character class for "free
> text" *silently shadows* the fixed `{{` delimiter token and the tags are
> never recognized — a wrong parse, not an error (see
> [dx-report.md](../dx-report.md) §1). A custom matcher gives the lexer the
> control ABNF cannot here, while the token grammar stays declarative.

### 2. Compile

The token stream is lowered to a small **boru program**: a fixed runtime
prelude of custom `tpl_*` words (string-building, escaping, lookups,
sections, loops, filters) plus a generated `__render` function that builds
the output by calling *only* those words. mustache and handlebars each
have their own compiler; liquid and jinja share one `compile-tagged-seq`
over the union of their tag vocabularies (so `elsif`/`elif` and
`assign`/`set` both parse), differing only in their lexers.

The compiler is a self-recursive descent over the token list. Text becomes
a string literal (embedded via `canon`, so any quotes/braces/newlines
round-trip); interpolations become `tpl_esc`/`tpl_str` calls; blocks
become `tpl_section`/`tpl_if`/`tpl_each`/`tpl_for` calls wrapping a body
function. The context is injected at render time (also via `canon`), so a
`Compiled` value can render many contexts without recompiling.

### 3. Run — the sandbox

The program is executed through `boru:vm` in a fresh sub-engine under a
**totally restricted policy**: the network, fileops, process, env, and
sqlite capability scopes are *uninstalled* (the words don't even exist in
the sub-engine), and only the import of `boru:string-util` — pure string
computation the runtime needs — is allowed. A template therefore can never
perform I/O or escape the sandbox. This is the "totally restricted
registry": the rendered template can reach nothing but its own runtime
vocabulary.

This is why templating is safe here even for untrusted template *source*:
a mustache/handlebars/liquid/jinja template has no way to express I/O,
process control, or (lacking a recursion primitive) unbounded computation.

---

## Escaping, by engine

Mustache and handlebars **HTML-escape** `{{x}}` (`& < > "`) — the
historically safe default for HTML output — and provide `{{{x}}}` / `{{&
x}}` for raw. Liquid and jinja emit **raw** output by default, matching
their upstream defaults; an `escape` filter is available when you need
HTML escaping. The escaping itself is four `StringUtil.replace` passes in
the `tpl_esc` runtime word.

---

## Context and scoping

The context is a Map (or any value) addressed by dotted paths (`a.b.c`),
with `{{.}}` meaning the current value. How blocks change the context
differs by construct:

- **mustache sections** over a list iterate with each item as the context;
  over a map, the map becomes the context. There is **no parent-context
  fallback** — inside a section, lookups see the section's own frame only.
- **handlebars `each`** wraps each item with the magic names `this`,
  `@index`, `@first`, `@last`; `with` merges an object onto the context.
- **liquid/jinja `for`** binds the loop variable by name and merges
  `forloop`/`loop` metadata *onto* the surrounding context, so outer
  variables stay visible. `assign`/`set` likewise thread a new binding
  through the rest of the enclosing block by wrapping the remainder in a
  body function called with the augmented context.

The asymmetry (mustache has no parent fallback; liquid/jinja/each do) is a
deliberate v1 scope choice, documented in the [Reference](reference.md).

---

## Why these four engines share so much

The expensive parts — a safe sandbox, a context-lookup model, escaping, a
filter library, loop/section runtimes — are engine-independent and live in
one runtime prelude. What actually differs between mustache and jinja is
small: the delimiters (a lexer) and the tag keywords (a compiler). Keeping
the spine common means a bug fixed in `tpl_for` is fixed for both liquid
and jinja, and the security properties are identical for all four. It also
means the gaps are shared and few: partials, template inheritance, custom
helpers/filters, and set-delimiter tags are unimplemented across the board
rather than half-done per engine.

---

## Building on boru: the sharp edges

boru is a structure-first, stack-oriented language, and several of its
characteristics shaped this library. They are catalogued with repros in
[dx-report.md](../dx-report.md); the ones that most affected the design:

- **`fn` bodies are traced once at definition** with sample arguments, so
  the runtime words are *pure* (value-returning, no captured mutation) —
  output is built by returning and concatenating Strings, never by
  mutating a buffer.
- **Argument order is per-word** (forward, reversed for arithmetic,
  receiver-first for `get`, receiver-last for user fns), so calls are
  written to each word's convention rather than one global rule.
- **Map-literal values don't see local `def`s**, so result maps use the
  bracketed `do { k: [expr] }` form.
- **Self-recursion works but mutual recursion needs guards** so the
  definition-time trace short-circuits on empty input — which is how
  `compile-tagged-seq` and `liquid-if`/`liquid-for` recurse into each
  other safely.

---

## Execution surfaces

The module is fully **interpretable**, and `boru -compile` (the bytecode
path) produces **byte-identical** output — the "opt-in performance, never
semantics" contract holds. It is *not* `boru check`-clean, and therefore
not `-force-compile`-able: the static checker can't see the `parse
<engine>` kinds because they are registered as a runtime side effect, and
reports `no_signature`/`unused_def` false positives on dynamic dispatch
and mutually-recursive helpers. These are checker limitations, not defects
(a function that errors in-module checks clean in isolation). The full
audit is [dx-report.md](../dx-report.md) §11–13.

---

## Further reading

- [Tutorial](tutorial.md) — render your first template step by step.
- [How-to guides](how-to.md) — task-focused recipes.
- [Reference](reference.md) — the exact API and per-engine feature tables.
- [dx-report.md](../dx-report.md) — boru runtime gotchas and the surface audit.
