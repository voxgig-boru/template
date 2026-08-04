# Developer-experience report: template on boru

**Date:** 2026-06-26
**boru build under test:** `boru-lang/boru` @ `b849948` (latest `main`).
**Context:** building the `Template` module (four sandboxed templating
languages — mustache, handlebars, liquid, jinja) on the bloom-filter
template repo. The pipeline relies on three facilities — `boru:parse`
(grammar), `boru:vm` (sandbox), and `canon` (round-trippable source) — plus
ordinary string/list words. Every gotcha below was reproduced first-hand;
all eight test suites pass on the interpreter, and this report also audits
the module across all three execution surfaces (interpret / check /
compile) in [§ Execution-surface audit](#execution-surface-audit).

Severity: **🔴 high** (silent wrong results / blocks a use case) ·
**🟡 medium** (friction, clear workaround) · **🟢 low** (papercut).

---

## Findings

### 1. 🔴 ABNF cannot lex delimiter-against-free-text (silent misparse)

The structure-first engine uses FIRST-set dispatch, not PEG backtracking.
An ABNF grammar like `tmpl = *( tag / ch )` with `ch = %x00-10FFFF` (any
char) **silently mis-parses**: every character — including `{{` — is taken
as a `ch`, and the `tag` alternative is never tried. The parse *succeeds*
with the wrong tree, which is worse than failing. A broad character class
shadows the fixed delimiter token in the lexer; whether it does so is
sensitive to the exact range (`%x61-7A` and `%x61-7E` recognize `{{`,
but `%x21-7A` and `%x20-7A` do not).

**Workaround:** drive lexing with a custom `Parse.matcher` (full control
of tokenization) and keep only the token-level grammar declarative
(`Parse.rule`). The template lexer is a matcher; the recognizer is a
push-recursion `val` rule (`{open:[{s:'#TX' p:'val'} {}] close:[{s:'#ZZ'} {}]}`).
"`*token`" is otherwise expressible only through the multi-rule lookahead
machinery the ABNF compiler generates — impractical to hand-write.

### 2. 🔴 A `fn` body is evaluated once at definition time

Defining `def w fn [ [s:String] [] [ buf push "ZZZ" end ] ]` runs the body
**once at def time** (with params bound to sample values, e.g. a String
param becomes `"a"`). For a void-return (`[]`) fn with captured mutable
state this performs a real, unwanted side effect; for a body that does a
strict lookup it can *raise* during definition (`getr` on a sample key →
`not_found`).

**Workaround:** make runtime words **pure** (value-returning, no captured
mutation) and trace-safe (use `get` which returns `None`, not `getr`). The
template runtime builds output by returning Strings and concatenating,
never by mutating a captured buffer.

### 3. 🟡 Argument-order conventions differ word to word

There is no single rule. Observed on this build:

- `slice 0 2 s`, `StringUtil.indexof needle haystack`,
  `StringUtil.replace find repl s` — **forward** (params left-to-right).
- `sub`/arithmetic forward is reversed: `sub a b` = `b - a`; use the
  pipeline form `(n sub 1)` for `n - 1`.
- `get` is **receiver-first**: `m get key`.
- A user `fn` called **receiver-first** binds the receiver to the *last*
  param: `compiled Template.render ctx` needs the signature
  `[cdata:Any c:Compiled]` (receiver last), matching the bloom convention
  `bf Bloom.add item` ⇒ `[item, bf]`.

**Workaround:** verify each word's order with a one-line probe; don't
assume. A mis-ordered call usually mis-binds silently rather than erroring.

### 4. 🟡 Map-literal values don't see local `def`s

Inside a `fn`, `{ a: x }` where `x` is a local `def` raises
"undefined word: x" — a bare map-literal value is not resolved against the
surrounding bindings.

**Workaround:** use the bracketed `do { a: [x] b: [y] }` form (as bloom's
`bloom-params` does); the `[…]` value expressions evaluate and see locals.

### 5. 🟡 `boru:vm` resource limits are declared but not enforced

`Vm.run-with code policy` honours the policy's **capability** scopes —
`import "boru:io"` / network / fileops / process / env are all denied, and
the words don't exist in the sub-engine (verified). But the policy's
`limits` (`timeoutMs`, `maxStepBudget`) are **not** enforced via this
path: an infinite tail-recursive program runs until externally killed,
not until the step budget.

**Impact here is low:** a mustache template cannot express unbounded
computation (no recursion primitive; sections iterate finite context
lists), so capability isolation is the operative guarantee and it holds.
A template that is merely *huge* is the only way to spend many steps. If a
later engine admits user-driven loops, the budget gap would matter.

### 6. 🟢 `get` now evaluates a dynamic key (fixed since `407feda`)

On the older `407feda` pin, `m get k` (variable key) looked up the literal
key `"k"`; you needed `m get (k)`. On `b849948` `m get k` resolves the
variable. The flip side: reading an error code as `e get code` is now an
"undefined word: code" error — use the quoted `e get "code"`. (The
bloom-template tests, written for `407feda`, use the bare form and would
need updating for main.)

### 7. 🟢 Multiple `Assert.equal` per block need terminators

Two `Assert.equal` statements on consecutive lines: the first forward-
collects the second (`expected fn assert-equal(...)`). End each with
`end` (`expected actual Assert.equal end`), as the suites do.

### 8. 🟡 `or` / `and` forward form mis-collects bare-variable operands

`(or is-sec is-inv)` (forward, two bare variables) raised
`no matching signature for or` with the operands arriving as unresolved
words. The **pipeline form** `(is-sec or is-inv)` works. (Forward `or`
with *parenthesised* operands — `(or (a eq b) (c eq d))` — is fine; the
breakage is specifically bare variables in forward position.) The
multi-engine compiler uses the pipeline form throughout.

### 9. 🟢 Naive comma split breaks quoted filter args

Splitting `{{ x | join: ", " }}`'s argument list on `,` shreds the quoted
`", "`. The compiler uses a small quote-aware splitter (`split-args`)
instead, so `join: ", "` and `replace: "a", "b"` parse correctly. Pipes
(`|`) inside a quoted argument are still not supported.

### 10. 🟢 Building the multi-engine layer hit the §2/§3/§4 traps repeatedly

The void-fn def-time trace (§2), per-word argument order (§3), and
map-literal scoping (§4) each recurred while adding handlebars/liquid/jinja
— result maps must use the `do { k:[expr] }` form; recursion is fine but
only *self*-reference is unbound, so mutual recursion (compile-tagged-seq ↔
liquid-if/liquid-for) works as long as each fn guards its list indexing so
the def-time trace short-circuits on empty input.

A surprisingly broad set of short, ordinary-looking names are **reserved
built-ins** that `def` rejects with `'X' is a built-in word and cannot be
redefined`. Encountered (and renamed) here: `emit`, `inner`, `base`,
`word`, `context`, `args`. Others that *look* reserved but are fine:
`rest`, `then`. There is no obvious pattern — probe with
`echo 'def NAME 1' | boru /dev/stdin` before settling on a local name.

---

## Execution-surface audit

boru exposes three execution surfaces: the interpreter (`boru X`), the static
checker (`boru check X`), and the bytecode compiler (`boru -compile X`, with
`-force-compile` to require it). Status of this module + its eight suites
on `b849948`:

| Surface | `template.aql` | test suites |
|---|---|---|
| **interpret** (`boru`) | ✅ clean | ✅ all 8 green |
| **`-compile`** (bytecode, silent fallback) | ✅ runs | ✅ all 8 green, output **byte-identical** to interpret |
| **`boru check`** | ❌ 24 errors, 10 warnings | ⚠️ 0 errors, only `unused_def` warnings |
| **`-force-compile`** (strict bytecode) | ❌ refuses (`check diagnostics`) | ⚠️ 1 of 8 fully compiles; the rest refuse on code-body words (`each`/`test-test`, "Stage 2") or, for the smoke suite, `check diagnostics` |

**The module is fully interpretable and runs identically under the byte
compiler, but is not `boru check`-clean and therefore not
`-force-compile`-able.** The check findings are *not* real defects, and the
soundness contract holds — see the three findings below.

> **Update (boru `claude/dx-driven-language-improvements`, 2026-06-27):** the
> §11 `parse: no parser … is registered` category — described above as *"the
> single biggest blocker to a check-clean result"* — is **FIXED upstream**.
> `boru:parse`'s `Parse.register` gained a check-mode hook that marks its
> runtime-registered kind as deferred, so `parse <kind>` in a fn body now
> resolves during analysis instead of raising. **`boru check template.aql` drops
> from 24 → 18 errors** (`parse_unknown_lang`: 0). The remaining 18 are the two
> *acknowledged-checker-limitation* categories: 12 `no_signature` (dynamic
> dispatch over `Any`-typed values — the gradual-dispatch false positive) and 6
> `fn_body_error: unmatched parenthesis` (emergent whole-module analysis-state
> bleed — each body is balanced and checks clean alone). Both are upstream
> checker work, not module defects; the soundness contract (§13) is unchanged.

### 11. 🟡 `boru check` reports emergent errors the runtime does not (not gating-ready)

`boru check template.aql` reports 24 errors + 10 warnings, yet the
interpreter runs the module and all suites cleanly and `-compile` is
byte-identical (§13). The errors are checker limitations, not bugs —
proven two ways: (a) the interpreter/compiler disagree with check; (b) a
function that errors *in the module* checks **clean in isolation**
(`first-word` alone → `0 error(s)`), so the failures are emergent from
whole-module analysis, not from the code (the same "emergent, not
per-construct" behaviour the bloom template's force-compile notes
describe). The categories:

- **`parse: no parser "mustache"/"liquid"/"jinja" is registered`** (in the
  `lex-*` fn bodies). The grammars are installed by `Parse.register` — a
  **runtime** side effect; `boru check` never executes it, so the static
  pass cannot see the `parse <kind>` the lexer calls. This is intrinsic to
  the architecture (runtime-registered grammars) and the single biggest
  blocker to a check-clean result.
- **`no_signature … assuming best-fit candidate`** — user-fn dispatch
  (`gen-program`, `compile-tagged-seq`, `lex-*`) and dynamic `get` on
  `Any`-typed values. Same family as the bloom module's false
  `no_signature for mul` (dx of `407feda`).
- **`fn_body_error: unmatched opening/closing parenthesis`** for
  `first-word` / `after-word` / `compile-operand` / `compile-output` /
  `parts`. Emergent only: each body is balanced and checks clean alone.
- **`unused_def`** for body-only defs and the mutually-recursive
  `liquid-if` / `liquid-for` (the checker's flow analysis doesn't see uses
  reached only through mutual recursion or inside higher-order code
  bodies).

**Workaround:** none that makes `template.aql` check-clean without upstream
changes — the runtime-registered-parser pattern is invisible to a static
pass by construction. The benign test-suite `unused_def` warnings *can* be
silenced with the bloom `_`-prefix trick on body-only defs. Treat `boru
check` as advisory for this module, not gating.

### 12. 🟡 `-force-compile` refuses — for two distinct reasons

Strict bytecode (`-force-compile`) declines this module, but the per-target
reasons differ:

- **`template.aql` and the smoke suite → `force-compile: check
  diagnostics`.** `-force-compile` refuses whenever the static checker
  emits error diagnostics, regardless of whether the program would lower.
  Because §11's diagnostics are false positives, this is a *consequence* of
  §11, not an independent limitation; closing §11 upstream unblocks it.
- **The assertion suites → `force-compile: code-body word each / test-test
  (Stage 2)`.** This is a separate, genuine emitter coverage gap: the
  bytecode backend can't yet fully lower a higher-order code body (the
  `each`/`fold` block and the `boru:test` harness's `test-test` /
  `test-check-prop` words), so it refuses rather than guess. `template_prop_test.aql`
  (whose property bodies avoid the triggering shapes) *does* fully compile —
  1 of 8. The same class of refusal is catalogued for the bloom module.

Neither blocks anything in practice: non-strict `-compile` lowers what it
can and falls back for the rest, byte-identically (§13).

### 13. ✅ Soundness holds: `-compile` is byte-identical to the interpreter

The positive result worth recording: with `-compile` (bytecode where
possible, silent interpreter fallback otherwise), every suite still prints
`all green`, and a direct interpret-vs-`-compile` diff of multi-engine
renders (liquid `for`+filter+`forloop.last`, jinja `if`, handlebars
`each`) is **byte-identical**. The "opt-in performance, never semantics"
contract is upheld for this module — the compile path is safe to use even
though strict `-force-compile` is blocked by §11/§12.

### 14. 🟡 `convert String` requires a Scalar — it raises on a Map/List

`convert String {a:1}` raises `signature_error` (the signatures are
`(Scalar, Scalar)` etc.; there is no Map→String conversion). This surfaced
as a render-time error when a value resolved to a Map and was handed to
`tpl_str` — e.g. a `{{.}}`/`{{this}}` that pointed at the whole context
frame instead of the intended item.

**Workaround:** stringify only scalars; the runtime's `tpl_str` guards
`None` and relies on every interpolated value being a scalar by the time it
reaches `convert`. The fix for the `{{this}}` case was a lookup-model
correction (resolve `this` to the item, not the frame), not a `convert`
change.

### 15. 🟡 `boru:parse` builder words are void and silently no-op without a terminator

`Parse.matcher` / `Parse.rule` / `Parse.register` (and the rest of the
builder) **return nothing**, so they cannot be `def`-bound
(`def x (Parse.register …)` → "expression produced no value"). Worse, a
bare builder call followed by more tokens **silently fails to take effect**
with no error: `Parse.register op g` immediately before another statement
left `op` *unregistered* — `ParseLang.kinds` simply omitted it, and the
later `parse op …` failed with "no parser op is registered". Adding the
`end` terminator (`Parse.register op g end`) fixed it.

**Workaround:** call every `boru:parse` builder word as a bare statement
terminated with `end` (or as the last statement in its block). This is the
general forward-collection rule (a verb swallows following tokens), but it
is especially sharp here because the failure is silent — registration just
doesn't happen.

| # | Severity | Issue |
|---|----------|-------|
| 1 | 🔴 | ABNF char-class lexing silently mis-parses delimiter/free-text; use a Parse.matcher |
| 2 | 🔴 | fn body runs once at def time (sample args); keep runtime words pure & trace-safe |
| 3 | 🟡 | per-word argument-order conventions differ (forward / reversed / receiver-first / receiver-last) |
| 4 | 🟡 | map-literal values don't see local defs; use `do { k:[expr] }` |
| 5 | 🟡 | boru:vm enforces capability scopes but not the step/time limits |
| 6 | 🟢 | `get` evaluates a dynamic key on main (so error reads need `get "code"`) |
| 7 | 🟢 | chained `Assert.equal` needs `end` terminators |
| 8 | 🟡 | forward `or`/`and` mis-collects bare-variable operands; use the pipeline form |
| 9 | 🟢 | naive comma split breaks quoted filter args; a quote-aware splitter is needed |
| 10 | 🟢 | the §2/§3/§4 traps recur across the multi-engine layer (reserved words, map-literal scoping, guarded mutual recursion) |
| 11 | 🟡 | `boru check` reports 24 emergent errors on the module (runtime-registered parsers, dynamic dispatch, emergent paren/unused_def false positives); not gating-ready |
| 12 | 🟡 | `-force-compile` refuses two ways: `check diagnostics` (module/smoke, from §11) and `code-body word each/test-test` (suites, a real emitter coverage gap); 1/8 fully compiles |
| 13 | ✅ | soundness holds: `-compile` runs every suite green and is byte-identical to the interpreter |
| 14 | 🟡 | `convert String` requires a Scalar; it raises `signature_error` on a Map/List |
| 15 | 🟡 | `boru:parse` builder words are void and silently no-op without an `end` terminator (registration just doesn't happen) |

## Surface status at a glance

- **Interpret:** ✅ clean — module + all 8 suites, no errors.
- **Compile (`-compile`):** ✅ runs; suites green; byte-identical to interpret.
- **Check (`boru check`):** ❌ module 24 errors / 10 warnings (all checker
  limitations, §11); tests only `unused_def` warnings.
- **Force-compile (`-force-compile`):** ❌ module/smoke refuse on `check
  diagnostics`; the suites refuse on code-body words (`each`/`test-test`);
  1 of 8 fully compiles (§12).
