# Developer-experience report: template on boru

**Latest:** [Migration to boru main @ 64c5ab2 (2026-10-01)](#migration-to-boru-main--64c5ab2-2026-10-01)
— read it first. The findings after it are the original report
(2026-06-26, boru `b849948`); each one's status on boru main is in the
migration section's [status table](#status-of-the-original-findings-on-boru-main).

**Original date:** 2026-06-26
**Original boru build under test:** `boru-lang/boru` @ `b849948` (then-latest `main`).
**Context:** building the `Template` module (four sandboxed templating
languages — mustache, handlebars, liquid, jinja) on the bloom-filter
template repo. The pipeline relies on three facilities — `boru:parse`
(grammar), `boru:vm` (sandbox), and `canon` (round-trippable source) — plus
ordinary string/list words. Every gotcha below was reproduced first-hand;
all eight test suites passed on the interpreter, and the original report
audited the module across the three execution surfaces of that time
(interpret / check / compile) in [§ Execution-surface audit](#execution-surface-audit).

Severity: **🔴 high** (silent wrong results / blocks a use case) ·
**🟡 medium** (friction, clear workaround) · **🟢 low** (papercut).

---

## Migration to boru main @ 64c5ab2 (2026-10-01)

The library was last verified against boru `6185620` (2026-07-21), 1,587
upstream commits earlier. On boru main @ `64c5ab2` **every program compiles
to bytecode and runs on the VM, or fails** with `[boru/compile_failed] …
this is a compiler defect`: the interpreter fallback and the `--compile` /
`--force-compile` / `--no-compile` flags are retired, and `boru X` runs a
static pre-flight check first whose errors block the run. So "a suite
runs" now means "a suite fully compiles".

**Starting state.** Every suite was blocked: `template.aql` failed to
compile (`fn compile-hb-seq: a gradual read in a nested body has no seated
guard … (NUR361)`), the suites' `import "./template.aql"` no longer
resolved from `test/`, and the spec suites reported fail counts of 9 and 5
because every sandboxed render died on a syntax error in the runtime
prelude (breaking change 3 below).

**End state.** All 8 suites fully compile, run and print `all green`;
`boru check` reports **0 errors** on every suite and on `template.aql`
(which used to report 18–24 false-positive errors). Remaining diagnostics:

| File | Errors | Warnings | Infos |
|------|-------:|---------:|------:|
| `template.aql` | 0 | 0 | 6 — three `macro_not_expandable` (the runtime-registered `parse <engine>` calls are dynamic to the static pass) and three `late_binding` (the forward-declared `liquid-if` / `liquid-for`, and see checker note F) |
| `test/template_smoke_test.aql` | 0 | 1 — `unused_def: def ctx` (checker false positive D) | 1 |
| the other 7 suites | 0 | 0 | 1 — `module_body_executed_in_check` |

The gate is `test/divergence/run.sh` (run + check per suite, plus the
module check); see its README for why the interpreter/compile columns are
gone.

### Breaking changes hit

1. **`/r` → `/v`** (ADR-011). The export map used `tpl-compile/r`; now
   `compile: tpl-compile/v  render: tpl-render/v`.
2. **Relative imports resolve against the importing file's directory**
   (run and check alike). All eight suites now `import "../template.aql"`,
   as do `bench/*.aql`.
3. **Backtick templates decode the quoted-string escapes** (boru
   `8d7d7b965`, "one escape vocabulary", NUR026). The sandbox runtime is a
   backtick string holding boru source, and its `tpl_esc` replaced
   `"\""` — which used to stay literal inside the backtick and is now
   decoded, so the generated program contained `"""`: a syntax error in
   **every** render. Written `'"'` now (needs no escape). Repro:
   ``def s `a"\"b` `` then `print (s size)` → `4` (was 5).
4. **One execution path.** The harness (`test/divergence/run.sh`), CI
   (`ci/run-tests.sh`) and `bench/BASELINE.md` used `--no-compile` /
   `--compile` / `--force-compile`; all rewritten. `ci/build-aql.sh`
   (renamed `ci/build-boru.sh`) also looked for an `aql` binary on `PATH`.
5. **`Test.check-prop` returns its PropertyResult Map** — five bare calls in
   `template_prop_test.aql` left five Maps on the stack, printed after
   `all green`. Bound (`def _pN (…)`).
6. **`get` evaluates its key** (re-verified): a bare `get code` /
   `e get code` is an `undefined_word: code` check error. `get "code"`,
   `dot code` (in a handler) and `e.code` work. The suites and docs already
   used the quoted form; the docs now also show `dot` / field access.
7. **Receiver-first calls are rejected statically.**
   `Template.render tpl {name:'Ada'}` → `uncalled_function: call to
   'tpl-render' matched no signature` (it used to fail at run time). The
   docs' "Common mistakes" say so.
8. **Map printing / `none` rendering.** `print (Template.engines)` renders
   JSON-style (`["mustache", "handlebars", "liquid", "jinja"]`); `${x}` of
   `none` renders `none`. Doc comments updated.
9. **The SessionStart hook's build was broken**: `GOFLAGS=-mod=mod go
   build` inside the source tree (which carries boru's `go.work`) fails
   with "-mod may only be set to readonly or vendor when in workspace
   mode". Now `GOWORK=off GOFLAGS=-mod=mod`, verified by building
   `64c5ab2` from a source copy (`boru -version` → `boru 64c5ab2…`).
10. **Performance.** A render costs ~210 ms vs ~15 ms in the interpreter
    era (~14×; the first migration run measured ~295 ms with the earlier
    fn-value code shape). The `boru:vm` sub-engine now runs each generated
    program the way `boru X` does — check, bytecode compile, VM — falling
    back to the interpreter only if the compile fails (`CompiledSubRun` in
    boru's `lang/go/boru.go`); the generated programs compile, so every
    render pays the compile, and nothing reuses a compiled program across
    runs (20 × `Vm.compile` ≈ 20 × render). Startup (`import
    template.aql`) went from ~0.7 s to ~3.5–5.4 s (load-dependent).
    Numbers, the old-vs-new code-shape comparison and the measurement are
    in `bench/BASELINE.md`.

### Compiler / runtime defects worked around

Each workaround is a natural, semantics-preserving rewrite carrying a
comment that names the defect; remove them when upstream fixes land. Repro
files: `/tmp/…/scratchpad/template/repro-*.boru` at migration time; the
text is reproduced here.

**A. NUR361 — compile_failed when two fns bind the same local name from a
gradual read in an arm.** (NUR361, pending; this same-name trigger is a
facet the record does not mention.)

```boru
# compile_failed: fn fb: a gradual read in a nested body has no seated guard:
# the interpreter dispatches it as a word when it holds a fn (NUR361)
def fa fn [ [i:Integer] [Map] [ if (i gt 0) [ def k ((fa (i sub 1)) get "n")  do {n:[(k add 1)]} ] [ do {n:[0]} ] ] ]
def fb fn [ [i:Integer] [Map] [ if (i gt 0) [ def k ((fb (i sub 1)) get "n")  do {n:[(k add 1)]} ] [ do {n:[0]} ] ] ]
print (fa 2)
print (fb 2)
```

Renaming `k` in either fn compiles and prints `{"n": 2}` twice. In
`template.aql` four fns bound `cidx` this way; they are now `hb-cidx`
(`compile-hb-seq`), `cmt-cidx` (`compile-tagged-seq`), `if-cidx`
(`liquid-if`) and `for-cidx` (`liquid-for`). Reverting the rename brings
back the compile failure that blocked every suite.

**B. DISPATCH_GENERIC internal_error (`vm:generic-claim-drift`) — a fn
parameter called on a def made in the same `each`/`var` body.**
(Recorded upstream as **NUR370**, [boru-lang/boru#528](https://github.com/boru-lang/boru/pull/528); a runtime `internal_error`,
"this is a compiler defect".)

```boru
# internal_error: DISPATCH_GENERIC at f: the live plan claims 1 forward of 1
# where the record claimed 0 of 1. Expected [1, 2].
def apply-each fn [ [xs:List f:Function] [List] [
  (xs each [ var [[e] def x (e get "k") (f x) ] ])
] ]
print (apply-each [{k:1} {k:2}] (fn [ [c:Any] [Any] [ c ] ]))
```

`(f x/v)`, `(f (x))` and `(f (e get "k"))` all answer `[1, 2]`. The sandbox
runtime's `tpl_each` and `tpl_for` had this shape (`(body m4)`,
`(body c4)`); the migration first passed `m4/v` / `c4/v` (both are Maps, so
`/v` is the identity). The block-fn lowering (defect G below) has since
removed those words — the runtime no longer calls any fn parameter — so
this shape no longer occurs in the library. The repro still fails on
`64c5ab2` (re-run 2026-10-02).

**C. A `def` inside an arm of a module fn's fold body leaks its name to
callers.** (Recorded upstream as **NUR371**, [boru-lang/boru#528](https://github.com/boru-lang/boru/pull/528); a wrong
`undefined_word` at run time, check clean.)

```boru
# mod.boru
def collect fn [ [n:Integer] [List] [
  def out (flex [])
  def res (do {k:[""]} (iota n) [ var [[i acc]
    if (i eq 1) [ def _ (out push i)  do {k:[""]} ] [ acc ]
  ] ] fold)
  slice 0 (out size) out
] ]
# `work` merely REACHES collect (statically, in an arm never taken).
def work fn [ [s:String] [String] [ if (s eq "zz") [ convert String ((collect 3) size) ] [ add "?" s ] ] ]
export "M" { work: work/v }

# main.boru — prints `undefined word: out`; expected `out=ab?`
import "./mod.boru"
def f fn [ [s:String] [String] [
  def out (M.work s)
  `out=${out}`
] ]
print (f "ab")
```

Renaming the caller's local (or the module's `out`) passes, and so does a
plain `print (out)` instead of the template-string read. `split-args` (the
liquid/jinja filter-argument splitter) had exactly this shape, so any
caller that bound `out` to a render and interpolated it failed — two of
the property tests (`def out (… Template.render)`) did. `split-args` now
carries its finished arguments in the fold accumulator (`parts`, a plain
List grown with copy-returning `push`): no captured `flex`, no `def`
inside an arm, and simply the cleaner idiom. (It was rewritten once more
for defect H.)

**G. A fn value passed as a parameter and called from an `each` callback
is miscompiled when the callee re-enters: the outer loop calls the INNER
fn.** (Recorded upstream as **NUR369**, [boru-lang/boru#528](https://github.com/boru-lang/boru/pull/528); a **silent wrong answer**,
check clean. Found by the verifier, 2026-10-02.)

```boru
def tj fn [ [xs:List body:Function] [List] [ (xs each [ var [[x] (body x) ] ]) ] ]
def b2 fn [ [c:Integer] [Integer] [ c mul 10 ] ]
def b1 fn [ [c:Integer] [Integer] [ (tj [7 8] b2/v) size ] ]
print (tj [1 2] b1/v)
# boru main @ 64c5ab2 prints [10, 20]; expected [2, 2] — the outer tj
# applied b2 (the inner call's body) instead of b1.
```

The shape varies (fn literals created inside a fn body, a gradual `v:Any`
receiver, a `get`-read argument), and so does what goes wrong, but the
template runtime was built on it: every block handed its body to a runtime
word as an anonymous fn value (`(tpl_for items 'x' ctx (fn [ [ctx:Any]
[String] [ … ] ]) …)`), and the word called it from an `each`. Nested
blocks therefore rendered wrong — `{% for x in xs %}{% for y in ys %}{{ y
}}{% endfor %}{{ x }};{% endfor %}` gave `ab1;` (expected `ab1;ab2;ab3;`),
a jinja three-level for dropped the second outer row,
`{{#xs}}{{^ok}}-{{/ok}}{{#ok}}+{{/ok}}{{/xs}}` gave `+++` (expected `+-+`),
and `{{#xs}}{{#ys}}{{.}}{{/ys}};{{/xs}}` raised `cannot call convert`. No
suite nested a loop, so the migration missed it; the unit suites now do
(`nested-loops` / `nested-each` / `sections-in-list-section`).

Workaround (natural, and arguably the better design): the compiler lowers
every block body to a **named** generated fn `__bN [ctx]`, and every block
to a named block fn that asks a pure context builder (`tpl_section_ctxs`,
`tpl_each_ctxs`, `tpl_for_ctxs`, `tpl_with_ctxs`) for the List of contexts
and calls the body fn **statically** (`cs each [ var [[c] (__b3 c) ] ]`),
or its else fn when the List is empty; conditionals become `if` block fns.
The generated program holds no fn values at all, still compiles to
bytecode (`Vm.compile` reports `ok`), and renders the nested cases
correctly; 30 non-nested edge cases render identically before and after.

**H. A fold body that reads an enclosing name raises `undefined word` on
the 5th–8th call in a process.** (Recorded upstream as **NUR372**, [boru-lang/boru#528](https://github.com/boru-lang/boru/pull/528),
with this library-scale repro; check clean. Found by the verifier,
2026-10-02.) The migrated `split-args` folded over
`iota (s size)` and read the fn parameter `s` in its body (`slice i (i add
1) s`). Compiling a liquid/jinja template with a filter argument worked
four times, then raised `undefined word: s` for compiles 5–8, then worked
again for 9–12:

```boru
import "./template.aql"   # template.aql as of commit bea732e
# repeat 8×: the 5th to 8th print `undefined word: s`
print (do [(({engine:'liquid' source:'{{ v | append: "a" }}'} Template.compile).program size)] error [ get "message" ])
```

Renaming the parameter only renames the error (`undefined word: sarg`);
replacing the `s` read with a module word moved it (`undefined word:
StringUtil`, reached on the 3rd compile once a template has two filter
segments). The cut-down standalone module does not reproduce it, so the
trigger needs more of `template.aql`'s context than has been isolated;
reproduce it from the commit above. Workaround: the fold walks the
characters themselves (`StringUtil.split "" s` — the same code points
`slice` yields) and joins with core `add`, so its body reads no name from
outside; 12 consecutive compiles of a two-filter jinja template now
succeed.

### Checker false positives (not gating; recorded precisely)

**D. `unused_def` for a def used only as a Map-literal value.**
`def ctx {a:1}` then `print (({k:ctx} get "k"))` → `[warning] unused_def:
def ctx is never used` (the program prints `{"a": 1}`). `{k:(ctx)}` warns
the same. This is the smoke suite's one warning.

**E. A handler-less `do [body]` is typed as the body's result, not the
Error it yields.**

```boru
# boru check: [error] no_signature: cannot call `dot` … got (String, Word)
def f fn [ [s:String] [String] [ if (s eq "x") [ raise bad_thing `no` ] [ s ] ] ]
def e (do [f "x"])
print (e.code)
```

With `-no-check` it prints `bad_thing`, the defined behaviour. Inside a
`Test.test` body (how the suites read error codes) the check does not
reach it, so no suite is affected; the AGENTS.md/SKILL.md top-level
examples use the handler form `do […] error [ get "code" ]` instead.

**F. A `def` in a `Parse.matcher` lambda arm is reported as a module
binding.** `boru check template.aql` reports `late_binding: parse-filter
reads ci, re-def'ed at line 624` (line 566 before the block-fn lowering) — that line is a `def ci` inside an arm of
the liquid matcher lambda, and `parse-filter` has its own local `ci`. Info
only; the code is correct.

### Other upstream observations

- **`boru:test` type-ID collision** (the ecosystem-wide defect: its record
  types are minted from a fresh type-ID counter). Not hit here: the suites
  import `boru:test` first and `Template.compile`'s `Compiled` return
  contract still checks (verified with both import orders). Note for the
  ecosystem: the one-class minimal repro (`def Box class { v: 0 }` /
  `def mk fn [ [n:Integer] [Box] [ make Box {v: n} ] ]` / `export "L"
  { mk: mk/v }`, then `print (L.mk 1)`) fails with `expected Box, got Box`
  in **both** import orders on `64c5ab2`, so importing the library first
  is not a general workaround.
- **`boru:vm` limits are still unenforced** (original §5): a 200,000-step
  fold completes under `maxStepBudget: 1000`. Capability scopes are
  enforced (`import "boru:fileops"` → `permission_denied`).
- **Forward `or` / `and` with bare variables** (original §8) is now a
  check error by design: both words take one argument forward and the rest
  from the stack, so `(or a b)` reports `no_signature`; the infix
  `(a or b)` the library uses is the canonical style.

### Status of the original findings on boru main

| # | Original finding | On boru main @ 64c5ab2 |
|---|------------------|------------------------|
| 1 | ABNF char-class lexing mis-parses delimiters | not re-tested; the library keeps its `Parse.matcher` lexer |
| 2 | fn body runs once at def time | **fixed** — a void fn that pushes to a captured buffer leaves it empty |
| 3 | per-word argument order | superseded by the one binding rule (signature order: forward first, then the stack) |
| 4 | map-literal values don't see local defs | **fixed** — `{a: y}` with a body-local `y` works; the `do {k:[…]}` form still works |
| 5 | `boru:vm` doesn't enforce step/time limits | **still open** |
| 6 | `get` evaluates its key | still true (now a check error for a bare word) |
| 7 | chained `Assert.equal` needs `end` | resolved by writing it forward, `Assert.equal expected actual` (saturated, no terminator) |
| 8 | forward `or`/`and` with bare variables | by design now (one forward argument); use infix |
| 9 | naive comma split | still handled by `split-args` (rewritten, defects C and H) |
| 10 | reserved names | `emit`, `inner`, `base`, `word`, `context`, `args` still reserved; `rest`, `then` still free |
| 11 | `boru check template.aql` 24 errors | **fixed** — 0 errors, 6 infos |
| 12 | `-force-compile` refuses | superseded — the flag is retired and every suite fully compiles |
| 13 | `-compile` byte-identical to the interpreter | superseded — one execution path |
| 14 | `convert String` needs a Scalar | still true (`signature_error` on a Map) |
| 15 | `boru:parse` builder words need `end` | the library still terminates them; not re-tested |

---

## Findings (original report, boru `b849948`, 2026-06-26)

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

## Execution-surface audit (historical — superseded by the single execution path)

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

## Surface status at a glance (historical, `b849948`)

- **Interpret:** ✅ clean — module + all 8 suites, no errors.
- **Compile (`-compile`):** ✅ runs; suites green; byte-identical to interpret.
- **Check (`boru check`):** ❌ module 24 errors / 10 warnings (all checker
  limitations, §11); tests only `unused_def` warnings.
- **Force-compile (`-force-compile`):** ❌ module/smoke refuse on `check
  diagnostics`; the suites refuse on code-body words (`each`/`test-test`);
  1 of 8 fully compiles (§12).
