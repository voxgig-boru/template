# AGENTS.md — using the `Template` library

Guidance for an AI coding agent calling this templating library from an
boru project. Every code block below is verified to run against
`boru-lang/boru` @ `6185620`. If you read nothing else, read
[The one calling rule](#the-one-calling-rule) and
[Common mistakes](#common-mistakes).

> **Calling convention.** Forward args, receiver (the `Compiled`) last:
> `Template.render context compiled`. Piping
> `compiled Template.render context` also works; only
> `Template.render compiled context` misbinds.

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

## Import

```boru
import "./template.aql"
```

- The path is resolved **relative to the working directory the script is
  run from**, not the importing file. Run scripts from where that path
  is valid (adjust otherwise).
- Do **not** import `boru:parse`, `boru:parselang`, `boru:string-util`, or
  `boru:vm` yourself — `template.aql` imports its own dependencies.

## The one calling rule

boru is not C/Python/JS. There is no `f(a, b)` and no `obj.method(a)`.
A call is a **verb with its arguments forward** — `Verb arg1 arg2` — and a
value sitting to the **left** of the verb pipes into the verb's **last**
parameter.

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

Only putting the receiver **first in forward position** misbinds — the data
lands in the receiver slot and render fails to match a signature:

```boru
print (Template.render tpl {name:'Ada'})   # ✗ WRONG: tpl→cdata, map→c
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

Errors carry a code and message: catch with `do […] error […]` and read
`e get "code"` / `e get "message"` in the handler. Codes: `bad_input`,
`unknown_engine`, `template_syntax` (malformed template — unbalanced or
mismatched section; a truly unterminated tag surfaces as
`parse_syntax_error` from the parser).

> **Reading an error code:** use `(e get "code")` with a **quoted String
> key**. On this build `get` evaluates its key argument, so a bare
> `e get code` is an "undefined word: code" error.

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

Not yet implemented (any engine): partials/includes, template
inheritance, custom helpers/filters, set-delimiter tags, lambdas, and
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
print (tpl Template.render {label:'a'})
print (tpl Template.render {label:'b'})
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
  get "message"                            # or: get "code", case […]
])
print (result)
```

In a test, assert the failure code:

```boru
import "boru:test"
def e (do [{engine:'mustache' source:'{{#a}}x{{/b}}' context:{}} Template.render])
template_syntax/q (e get "code") Assert.equal end
```

## Common mistakes

| ✗ Don't write | ✓ Write | Why |
|---------------|---------|-----|
| `Template.render(tpl, ctx)` / `tpl.render(ctx)` | `(Template.render ctx tpl)` | boru has no call/method syntax. |
| `Template.render tpl ctx` (receiver first in forward position) | `Template.render ctx tpl` or `tpl Template.render ctx` | The `Compiled` receiver binds LAST — put it last, or pipe it in from the left. |
| `e get code` | `e get "code"` | `get` evaluates its key; use a quoted String. |
| treat `{{x}}` as raw | it is **HTML-escaped** | use `{{{x}}}` / `{{& x}}` for raw output. |
| rely on parent context in a section | pass needed fields into the item | no parent-context fallback yet. |
| `make Compiled {…}` | `{engine, source} Template.compile` | Construct only via `Template.compile`. |
| `import "boru:parse"` in your script | nothing | `template.aql` imports its own deps. |

## Where to look next

- `template.aql` — the module; its header documents the parse → compile →
  sandbox pipeline and the runtime word set.
- `api.json` — the same API as a machine-readable manifest.
- `test/template_smoke_test.aql` — a complete, runnable worked example.
- `dx-report.md` — boru-runtime gotchas observed building this module.
