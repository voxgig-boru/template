# AGENTS.md — using the `Template` library

Guidance for an AI coding agent calling this templating library from a
boru project. Every code block below was executed against `boru-lang/boru`
**main @ `64c5ab2`** (2026-10-01). If you read nothing else, read
[The one calling rule](#the-one-calling-rule) and
[Common mistakes](#common-mistakes).

> **Calling convention.** Forward args, receiver (the `Compiled`) last:
> `Template.render context compiled`. Piping
> `compiled Template.render context` also works. Receiver-first
> `Template.render compiled context` matches no signature: `boru check`
> (which `boru X` runs first) rejects it, so the program does not run.

## What it is

A templating engine that renders text templates against a data context,
with a **common interface across templating languages**. Four engines are
implemented on one shared pipeline — **`mustache`**, **`handlebars`**,
**`liquid`**, and **`jinja`** — selected by the `engine` field; the config
and context data structures are identical across all of them. The public
surface is the `Template` namespace plus the `Compiled` type.

Every render runs inside a **sandbox**: the template is parsed (via
`boru:parse`), compiled to a small boru program built from a fixed set of
custom `tpl_*` words, and executed through `boru:vm` under a policy that
uninstalls every capability (network, fileops, process, env, sqlite). A
template can therefore never perform I/O or escape the sandbox.

boru main has **one execution path**: `boru file` runs a static pre-flight
check, then compiles the program to bytecode and runs it on the VM. There is
no interpreter fallback, and `--compile` / `--force-compile` /
`--no-compile` are retired (passing them is a usage error). A check error,
or a `[boru/compile_failed] … this is a compiler defect`, blocks the run.

## Import

```boru
import "./template.aql"
```

- A relative path resolves against the **importing file's own directory**
  (for both `boru file` and `boru check file`), not the working directory.
  A script next to `template.aql` writes `import "./template.aql"`; one in
  `test/` writes `import "../template.aql"`.
- Do **not** import `boru:parse`, `boru:parselang`, `boru:string-util`, or
  `boru:vm` yourself — `template.aql` imports its own dependencies.

## The one calling rule

boru is not C/Python/JS. There is no `f(a, b)` and no `obj.method(a)`.
A call binds its arguments **in signature order**: the tokens written after
the word fill the leading parameters, and whatever is left comes off the
stack (top of stack first). So a value sitting to the **left** of the verb
lands in the verb's **last** parameter.

The public `Template` words put the **receiver (the `Compiled` template)
LAST**: `render`'s signature is `[cdata:Any c:Compiled]` — **data first,
compiled last**. Because the receiver is the last parameter, two spellings
both bind:

```boru
def tpl (Template.compile {engine:'mustache' source:'Hi {{name}}!'})

# forward form (canonical): data forward, compiled LAST
print (Template.render {name:'Ada'} tpl)   # => Hi Ada!

# piping: the compiled template flows in from the LEFT
print (tpl Template.render {name:'Ada'})   # => Hi Ada!
```

Putting the receiver **first in forward position** is rejected before the
program runs — the `Compiled` would land in the data slot and the Map in the
receiver slot, and no signature matches:

```boru
print (Template.render tpl {name:'Ada'})   # ✗ WRONG
# boru check: [error] uncalled_function: call to 'tpl-render' matched no signature
```

`compile` takes a single `Options` map (it is a constructor), so
`Template.compile {…}` and `{…} Template.compile` are equivalent. Group a
call in parens to use its result.

## API reference (exact call shapes)

| Call | Returns | Notes |
|------|---------|-------|
| `Template.compile {engine:String, source:String}` | `Compiled` | Parse + compile a template once (single `Options` arg; `{…} Template.compile` is equivalent). Bad args raise `bad_input`; an unimplemented engine raises `unknown_engine`. |
| `Template.render context compiled` | `String` | Render a compiled template against a context (any Map/value). Receiver LAST; piping `compiled Template.render context` is equivalent. |
| `Template.render {engine, source, context}` | `String` | One-shot convenience: compile then render in one call (single `Options` arg). |
| `Template.engines` | `List` | The engines this build implements (`['mustache' 'handlebars' 'liquid' 'jinja']`). |

`Compiled` has read-only fields `engine` (String) and `program` (the
generated boru source). Build it only through `Template.compile`.

Errors carry a code and message: catch with `do […] error […]`. Inside the
handler the error is on the stack — read it with a **quoted** key,
`get "code"` / `get "message"`, or with `dot code` (`dot` quotes the bare
field name). An error bound to a name reads as `e.code` / `e get "code"`.
Codes: `bad_input`, `unknown_engine`, `template_syntax` (malformed template —
unbalanced or mismatched section; a truly unterminated tag surfaces as
`parse_syntax_error` from the parser).

> **`get` evaluates its key.** A bare `get code` / `e get code` is an
> `undefined_word: code` error from `boru check` (re-verified on boru main @
> `64c5ab2`), so the program does not run. Quote the key, or use `dot` /
> field access.

## Engines and their features

All four share dotted lookups (`a.b.c`), the `{{ }}` output delimiter, and
the same context data. Where escaping differs: **mustache and handlebars
HTML-escape** `{{x}}` (use `{{{x}}}` / `{{& x}}` for raw); **liquid and
jinja do not escape** by default (use the `escape` filter for HTML).

**mustache**
- `{{name}}` escaped, `{{{name}}}` / `{{& name}}` raw, `{{! comment }}`
- `{{#section}}…{{/section}}` — list iteration (`{{.}}` = current item),
  map context, or truthy-scalar; `{{^section}}…{{/section}}` inverted

**handlebars** (mustache lexer + block helpers)
- `{{#if x}}…{{else}}…{{/if}}`, `{{#unless x}}…{{/unless}}`
- `{{#each xs}}…{{/each}}` with `{{this}}`, `{{@index}}`, `{{@first}}`,
  `{{@last}}`, and item fields; `{{#with obj}}…{{/with}}`
- a `{{#name}}` whose first word is not a helper falls back to a section

**liquid** (`{{ output }}` + `{% tags %}`)
- filters: `{{ x | upcase | join: ", " }}`
- `{% if a > b %}…{% elsif c %}…{% else %}…{% endif %}`, `{% unless %}…{% endunless %}`
- `{% for x in xs %}…{% else %}…{% endfor %}` with `forloop.index/first/last/length`
- `{% assign v = expr %}`, `{% comment %}…{% endcomment %}`
- conditions support `== != < > <= >=` and `and` / `or`

**jinja** (`{{ }}` + `{% %}` + `{# comments #}`)
- filters: `{{ x | lower | capitalize }}`
- `{% if %}…{% elif %}…{% else %}…{% endif %}`
- `{% for x in xs %}…{% else %}…{% endfor %}` with `loop.index/first/last/length`
- `{% set v = expr %}`

Built-in filters (liquid/jinja): `upcase`/`upper`, `downcase`/`lower`,
`capitalize`, `size`/`length`, `first`, `last`, `join`, `default`,
`append`, `prepend`, `replace`, `escape`, `strip`/`trim`.

Not yet implemented (any engine): partials/includes, template inheritance,
custom helpers/filters, set-delimiter tags, lambdas, and
**parent-context fallback in mustache/handlebars sections** (liquid/jinja
`for` and handlebars `each`/`with` *do* see the surrounding context, since
they merge it). Filter arguments are simple literals/paths (commas inside
quotes are handled; nested pipes inside a quoted arg are not).

## Copy-paste idioms (all verified)

One-shot render:

```boru
import "./template.aql"
print ({engine:'mustache' source:'Hi {{name}}!' context:{name:'Ada'}} Template.render)
# => Hi Ada!
```

Compile once, render many contexts:

```boru
def tpl ({engine:'mustache' source:'<li>{{label}}</li>'} Template.compile)
print (Template.render {label:'a'} tpl)   # => <li>a</li>
print (tpl Template.render {label:'b'})   # => <li>b</li>
```

List section with the implicit iterator:

```boru
print ({engine:'mustache' source:'{{#xs}}[{{.}}]{{/xs}}' context:{xs:['a' 'b' 'c']}} Template.render)
# => [a][b][c]
```

Sections, dotted lookups, inverted sections together:

```boru
def src '{{#user}}{{name}} likes {{#likes}}{{.}} {{/likes}}{{/user}}{{^user}}no user{{/user}}'
print ({engine:'mustache' source:src context:{user:{name:'Ada' likes:['x' 'y']}}} Template.render)
# => Ada likes x y
```

Each of the other three engines:

```boru
print ({engine:'handlebars' source:'{{#each xs}}{{@index}}:{{this}} {{/each}}' context:{xs:['a' 'b']}} Template.render)
# => 0:a 1:b
print ({engine:'liquid' source:'{% for x in xs %}{{ x | upcase }} {% endfor %}' context:{xs:['a' 'b']}} Template.render)
# => A B
print ({engine:'jinja' source:'{% if n > 1 %}{{ n }} big{% endif %}' context:{n:3}} Template.render)
# => 3 big
```

Handle a bad engine or template (`erb` is not implemented):

```boru
def result (do [{engine:'erb' source:'x' context:{}} Template.render] error [
  get "message"                            # or: get "code", dot code, case […]
])
print (result)
# => Template.compile: no engine 'erb'; available: ['mustache' 'handlebars' 'liquid' 'jinja']
```

In a test, assert the failure code inside a `Test.test` body:

```boru
import "./template.aql"
import "boru:test"
Test.test "syntax-error" [
  def e (do [{engine:'mustache' source:'{{#a}}x{{/b}}' context:{}} Template.render])
  Assert.equal template_syntax/q (e get "code")
]
Assert.equal 0 (Test.fail-count)
```

`Assert.equal expected actual` reads forward, expected first. At the top
level of a script prefer the handler form above (`do […] error [get
"code"]`): a top-level `def e (do […])` followed by `e.code` is rejected by
`boru check` on boru main @ `64c5ab2` — it types the handler-less `do` as
the body's String result, not the Error it yields when the body raises (a
checker false positive, recorded in `dx-report.md`).

## Common mistakes

| ✗ Don't write | ✓ Write | Why |
|---------------|---------|-----|
| `Template.render(tpl, ctx)` / `tpl.render(ctx)` | `(Template.render ctx tpl)` | boru has no call/method syntax. |
| `Template.render tpl ctx` (receiver first in forward position) | `Template.render ctx tpl` or `tpl Template.render ctx` | The `Compiled` receiver binds LAST. Receiver-first matches no signature: `boru check` reports `uncalled_function` and the run is blocked. |
| `e get code` / handler `[ get code ]` | `e get "code"`, `e.code`, or `get "code"` / `dot code` in a handler | `get` evaluates its key; a bare word is looked up as a variable (`undefined_word: code`). |
| treat `{{x}}` as raw | it is **HTML-escaped** | use `{{{x}}}` / `{{& x}}` for raw output. |
| rely on parent context in a section | pass needed fields into the item | no parent-context fallback yet. |
| `make Compiled {…}` | `{engine, source} Template.compile` | Construct only via `Template.compile`. |
| `import "boru:parse"` in your script | nothing | `template.aql` imports its own deps. |
| `import "./template.aql"` from a file in a subdirectory | `import "../template.aql"` | Relative imports resolve against the importing file's directory. |
| `boru --compile file` / `--no-compile` | `boru file` | One execution path; the mode flags are retired (usage errors). |

A note on `print` while debugging: `print` collects a forward argument, so
write `print (value)` — verb first, one value per statement — and output
appears in source order. Postfix chains reorder: `"a" print` on one line
followed by `"b" print` on the next prints `b` first.

## Where to look next

- `template.aql` — the module; its header documents the parse → compile →
  sandbox pipeline and the runtime word set.
- `api.json` — the same API as a machine-readable manifest.
- `docs/reference.md` — full signatures, per-engine feature tables, errors.
- `test/template_smoke_test.aql` — a complete, runnable worked example.
- `dx-report.md` — boru-runtime gotchas observed building this module,
  including the migration to boru main @ `64c5ab2` and its open upstream
  defects.
