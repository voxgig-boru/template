---
name: template-aql
description: Use when writing or editing boru code that calls the Template library — Template.compile / Template.render / Template.engines, the Compiled type, or any file that does `import "./template.aql"`. Renders mustache / handlebars / liquid / jinja templates against a data context through one common, sandboxed interface. Provides the exact boru calling convention (which is not C/Python/JS — the `Compiled` receiver goes LAST: `Template.render data tpl`, not `Template.render tpl data`), the per-engine feature set, verified copy-paste idioms, and fixes for the mistakes agents most often make (foreign call syntax like `tpl.render(ctx)`, putting the receiver first in forward position, bare `e get code` instead of `e get "code"`, assuming `{{x}}` is raw, expecting parent-context fallback in mustache sections).
---

# Calling the Template library (boru)

Render text templates against a data context, with one interface across
**four engines** — `mustache`, `handlebars`, `liquid`, `jinja` — selected
by the `engine` field. Every render is **sandboxed** (parsed via
`boru:parse`, compiled to custom `tpl_*` words, run through `boru:vm` with
all capabilities — network/fileops/process/env/sqlite — uninstalled), so a
template can never do I/O or escape. Public surface = the `Template`
namespace + the `Compiled` type. Verified against `boru @ 6185620`.

## Import

```boru
import "./template.aql"
```

- Path resolves relative to the **working directory the script runs from**,
  not the importing file.
- Do **not** import `boru:parse` / `boru:parselang` / `boru:string-util` /
  `boru:vm` — the library imports its own dependencies.

## The one calling rule

boru has no `f(a, b)` and no `obj.method(a)`. A call is a **verb with its
arguments forward** — `Verb arg1 arg2` — and a value sitting to the **left**
of the verb is piped into the verb's **last** parameter.

The public `Template` words put the **receiver (the `Compiled` template)
LAST**: `render`'s signature is `[cdata:Any c:Compiled]` — **data first,
compiled last**. Because the receiver is the last parameter, two spellings
both bind correctly:

```boru
def tpl (Template.compile {engine:'mustache' source:'Hi {{name}}!'})

# forward form (canonical): data forward, compiled LAST
print (Template.render {name:'Ada'} tpl)   # => Hi Ada!

# piping: the compiled template flows in from the LEFT
print (tpl Template.render {name:'Ada'})   # => Hi Ada!
```

Only putting the receiver **first in forward position** misbinds — the data
lands in the receiver slot and render fails a type match:

```boru
print (Template.render tpl {name:'Ada'})   # ✗ WRONG: tpl→cdata, map→c
```

`compile` takes a single `Options` map (it is a constructor), so
`Template.compile {…}` and `{…} Template.compile` are equivalent. Group any
call in parens to use its result as a value.

## API

| Call | Returns | Notes |
|------|---------|-------|
| `Template.compile {engine:String, source:String}` | `Compiled` | Parse + compile once (single `Options` arg; `{…} Template.compile` is equivalent). Bad args raise `bad_input`; an unimplemented engine raises `unknown_engine`. |
| `Template.render context compiled` | `String` | Render a compiled template against a context (any Map/value). Receiver LAST; piping `compiled Template.render context` is equivalent. |
| `Template.render {engine, source, context}` | `String` | One-shot: compile + render (single `Options` arg). |
| `Template.engines` | `List` | `['mustache' 'handlebars' 'liquid' 'jinja']`. |

`Compiled` has read-only fields `engine` / `program`; build only via
`Template.compile`. Catch errors with `do […] error […]` and read
`e get "code"` / `e get "message"` (a **quoted** key — `get` evaluates its
argument, so bare `e get code` is "undefined word: code"). Codes:
`bad_input`, `unknown_engine`, `template_syntax` (a truly unterminated tag
surfaces as `parse_syntax_error`).

## Engines

Escaping differs: **mustache & handlebars HTML-escape** `{{x}}` (use
`{{{x}}}` / `{{& x}}` for raw); **liquid & jinja are raw** by default (use
the `escape` filter). All share dotted lookups (`a.b.c`) and the same
context data.

- **mustache** — `{{v}}` / `{{{v}}}` / `{{& v}}`, `{{#s}}…{{/s}}` (list /
  map / boolean), `{{^s}}…{{/s}}`, `{{! comment }}`, `{{.}}`.
- **handlebars** — mustache plus `{{#if}}{{else}}{{/if}}`, `{{#unless}}`,
  `{{#each}}` (`{{this}}`, `{{@index}}`, `{{@first}}`, `{{@last}}`, item
  fields), `{{#with}}`.
- **liquid** — `{{ x | filter: arg }}`, `{% if/elsif/else/endif %}`,
  `{% unless %}`, `{% for x in xs %}…{% else %}…{% endfor %}` (`forloop.*`),
  `{% assign v = expr %}`, `{% comment %}`; conditions `== != < > <= >=`
  and `and` / `or`.
- **jinja** — `{{ x | filter }}`, `{% if/elif/else/endif %}`,
  `{% for %}…{% else %}…{% endfor %}` (`loop.*`), `{% set v = expr %}`,
  `{# comments #}`.

Built-in filters (liquid/jinja): `upcase`/`upper`, `downcase`/`lower`,
`capitalize`, `size`/`length`, `first`, `last`, `join`, `default`,
`append`, `prepend`, `replace`, `escape`, `strip`/`trim`.

Not implemented (any engine): partials/includes, template inheritance,
custom helpers/filters, set-delimiter tags, lambdas, and **parent-context
fallback in mustache/handlebars sections** (liquid/jinja `for` and
handlebars `each`/`with` *do* see the surrounding context).

## Idioms (verified)

```boru
import "./template.aql"

# one-shot
print ({engine:'mustache' source:'Hi {{name}}!' context:{name:'Ada'}} Template.render)
# => Hi Ada!

# compile once, render many — data first, compiled LAST
def li (Template.compile {engine:'mustache' source:'<li>{{label}}</li>'})
print (Template.render {label:'a'} li)     # forward form (canonical)
print (li Template.render {label:'b'})     # piping — also correct

# handlebars block helpers
print ({engine:'handlebars' source:'{{#each xs}}{{@index}}:{{this}} {{/each}}' context:{xs:['a' 'b']}} Template.render)
# => 0:a 1:b

# liquid filters + control
print ({engine:'liquid' source:'{% for x in xs %}{{ x | upcase }} {% endfor %}' context:{xs:['a' 'b']}} Template.render)
# => A B

# jinja loop metadata + comment
print ({engine:'jinja' source:'{% for x in xs %}{{ loop.index }}{% endfor %}{# c #}' context:{xs:['a' 'b' 'c']}} Template.render)
# => 123

# handle a bad engine ('erb' is not implemented) or template
def out (do [{engine:'erb' source:'x' context:{}} Template.render] error [ get "message" ])
```

## Common mistakes

| ✗ Don't | ✓ Do | Why |
|---------|------|-----|
| `Template.render(tpl, ctx)` / `tpl.render(ctx)` | `(Template.render ctx tpl)` | boru has no call/method syntax. |
| `Template.render tpl ctx` (receiver first in forward position) | `Template.render ctx tpl` or `tpl Template.render ctx` | The `Compiled` receiver binds LAST — put it last, or pipe it in from the left. |
| `e get code` | `e get "code"` | `get` evaluates its key; use a quoted String. |
| treat `{{x}}` as raw (mustache/handlebars) | `{{{x}}}` / `{{& x}}` for raw | `{{x}}` is HTML-escaped there. |
| rely on parent context in a mustache section | pass needed fields into the item | no parent-context fallback. |
| `make Compiled {…}` | `{engine, source} Template.compile` | Construct only via `Template.compile`. |
| `import "boru:parse"` in your script | nothing | the library imports its own deps. |

## boru semantics worth knowing (by design)

These are intentional boru behaviours that bite when driving this library:

- **`None` interpolation renders `None`.** In a host string, `${x}` where
  `x` is `None` prints the literal `None` (human-readable), not empty and
  not JSON `null`. (Inside a template, a *missing* lookup still renders
  empty — `tpl_str` maps `None → ""`.) For JSON semantics use `jsonify`
  (the `boru:struct` module), not string interpolation.
- **`eq` is identity, `deq` is structural.** `[1 2] eq [1 2]` is `false`;
  `[1 2] deq [1 2]` is `true`. Rendered output is a String, so compare it
  with `eq`; compare Lists/Maps (e.g. `Template.engines`) with `deq`.
- **Maps/Lists are immutable.** `set` / `push` return a **new** value and
  leave the original unchanged (they do not mutate in place and do not
  error). Use `flex` for a genuinely mutable Map.
- **`each` is a MAP** — it yields one value per element (`[1 2 3] each …`
  → a new List). Use `for` for pure side effects.
- **Integer overflow is fail-loud.** Arithmetic is 63-bit and raises
  `integer_overflow` past the range, by design — it never wraps.
- **Keys evaluate now.** Bare `e get code` is "undefined word: code";
  write `e get "code"` (quoted) or `e.code`.

If the full repo is available, `AGENTS.md`, `api.json` (machine-readable
signatures), and `docs/reference.md` have the complete guide;
`test/template_smoke_test.aql` is a runnable example.
