# Reference

Technical description of the `Template` module's public surface. This page
is information-oriented: what each word is, its call shape, and what it
returns. For *why* it behaves this way, see the
[Explanation](explanation.md); for goal-directed recipes, the
[How-to guides](how-to.md).

> **AI agents:** [AGENTS.md](../AGENTS.md) condenses the calling
> convention, idioms, and common mistakes for machine use.

The module exports a single namespace, `Template`, plus the `Compiled`
type. Import it with:

```boru
import "./template.aql"
```

A consuming script does **not** need to import `boru:parse`,
`boru:parselang`, `boru:string-util`, or `boru:vm` — `template.aql` imports
them internally.

---

## Calling convention

Every operation is a verb with its arguments **forward** — `Template.verb
arg1 arg2` — and a value to the **left** of the verb pipes into the verb's
**last** parameter. The `Template.render` receiver (the `Compiled`) is the
**last** parameter, so the canonical forward form puts it last —
`Template.render context compiled` — and piping
`compiled Template.render context` is equivalent; only
`Template.render compiled context` misbinds. Group a call in parens to use
its result as a value. There is no `Template.verb(args)` and no
`tpl.render(ctx)`.

---

## Types

### `Compiled`

A sealed `class` instance produced by `Template.compile`. Fields:

| Field     | Type   | Meaning                                              |
|-----------|--------|-----------------------------------------------------|
| `engine`  | String | the engine this template was compiled for           |
| `program` | String | the generated boru program run in the sandbox        |

Construct only through `Template.compile`; treat the fields as read-only.

---

## Words

### `Template.compile`

Parse and compile a template once.

| | |
|--|--|
| **Call**    | `{engine: String, source: String} Template.compile` |
| **Stack in**| an options Map with keys `engine` and `source` |
| **Returns** | `Compiled` |
| **Errors**  | `bad_input` if `engine`/`source` are missing or not Strings; `unknown_engine` if the engine is not implemented |

```boru
def tpl ({engine:'mustache' source:'Hi {{name}}!'} Template.compile)
```

### `Template.render`

Render a template against a context. Two forms:

| | |
|--|--|
| **Call (two-step)** | `Template.render context compiled` (receiver last; `compiled Template.render context` pipes too) |
| **Call (one-shot)** | `{engine, source, context} Template.render` |
| **Stack in**| a `Compiled` + a context value, **or** an options Map |
| **Returns** | `String` |
| **Errors**  | `template_syntax` for a malformed template (one-shot also raises `bad_input` / `unknown_engine` from the implicit compile) |

The context is any value; usually a Map of the fields the template
references. The render runs in a sandboxed sub-engine (see
[Explanation](explanation.md)).

```boru
print (tpl Template.render {name:'Ada'})
print ({engine:'liquid' source:'{{ x | upcase }}' context:{x:'hi'}} Template.render)
```

### `Template.engines`

The engines this build implements.

| | |
|--|--|
| **Call**    | `Template.engines` |
| **Returns** | `List` — `['mustache' 'handlebars' 'liquid' 'jinja']` |

---

## Engines and features

All engines share dotted lookups (`a.b.c`), the `{{ }}` output delimiter,
and identical context data. **Escaping:** mustache and handlebars
HTML-escape `{{x}}` (`& < > "`), with `{{{x}}}` / `{{& x}}` raw; liquid and
jinja are raw by default (use the `escape` filter).

### mustache

| Construct | Meaning |
|-----------|---------|
| `{{name}}` | escaped interpolation |
| `{{{name}}}`, `{{& name}}` | raw interpolation |
| `{{#s}}…{{/s}}` | section: list iteration (`{{.}}` = item), map context, or truthy scalar |
| `{{^s}}…{{/s}}` | inverted section (renders iff falsy/empty) |
| `{{! comment }}` | comment (renders nothing) |
| `{{a.b.c}}`, `{{.}}` | dotted lookup, implicit current item |

### handlebars

Mustache lexer + block helpers:

| Construct | Meaning |
|-----------|---------|
| `{{#if x}}…{{else}}…{{/if}}` | conditional on truthiness of `x` |
| `{{#unless x}}…{{/unless}}` | negated conditional |
| `{{#each xs}}…{{/each}}` | iterate; `{{this}}`, `{{@index}}`, `{{@first}}`, `{{@last}}`, item fields, `{{else}}` for empty |
| `{{#with obj}}…{{/with}}` | enter an object's fields (merged onto the context) |

A `{{#name}}` whose first word is not a helper falls back to a mustache
section.

### liquid

`{{ output }}` + `{% tags %}`:

| Construct | Meaning |
|-----------|---------|
| `{{ x \| f: a }}` | output through a filter chain |
| `{% if c %}…{% elsif c %}…{% else %}…{% endif %}` | conditional chain |
| `{% unless c %}…{% endunless %}` | negated conditional |
| `{% for x in xs %}…{% else %}…{% endfor %}` | loop; `forloop.{index,index0,first,last,length,rindex}` |
| `{% assign v = expr %}` | bind a variable for the rest of the block |
| `{% comment %}…{% endcomment %}` | block comment |

Conditions: `== != < > <= >=`, joined by `and` / `or`.

### jinja

`{{ }}` + `{% %}` + `{# comments #}`:

| Construct | Meaning |
|-----------|---------|
| `{{ x \| f }}` | output through a filter chain |
| `{% if c %}…{% elif c %}…{% else %}…{% endif %}` | conditional chain |
| `{% for x in xs %}…{% else %}…{% endfor %}` | loop; `loop.{index,index0,first,last,length,rindex}` |
| `{% set v = expr %}` | bind a variable for the rest of the block |
| `{# … #}` | comment (lexer-level) |

### Built-in filters (liquid / jinja)

`upcase`/`upper`, `downcase`/`lower`, `capitalize`, `size`/`length`,
`first`, `last`, `join` (arg = separator), `default` (arg = fallback),
`append` (arg), `prepend` (arg), `replace` (args = find, repl), `escape`,
`strip`/`trim`. An unknown filter passes the value through unchanged.

### Not implemented (any engine)

Partials / includes, template inheritance, custom helpers / filters,
set-delimiter tags, lambdas, and **parent-context fallback in
mustache/handlebars sections** (liquid/jinja `for` and handlebars
`each`/`with` *do* see the surrounding context, since they merge it).
Filter arguments are literals or paths; commas inside quotes are handled,
but a pipe inside a quoted argument is not.

---

## Errors at a glance

All failures raise coded errors; catch with `do […] error […]` and read
`(e get "code")` / `(e get "message")` (a **quoted** key — `get` evaluates
its argument on this build).

| Code | Raised by | Situation |
|------|-----------|-----------|
| `bad_input` | `compile` / `render` | `engine` or `source` missing or not a String |
| `unknown_engine` | `compile` / `render` | the requested engine is not implemented |
| `template_syntax` | `compile` / `render` | malformed template: unbalanced, mismatched, or unclosed tag; unsupported `{% tag %}` |
| `parse_syntax_error` | the parser | a tag with no closing delimiter (`{{`/`{%`/`{#` never closed) |

---

## Sandbox guarantees

Every render runs in a fresh `boru:vm` sub-engine under a policy that
**uninstalls** the network, fileops, process, env, and sqlite capability
scopes and allows only the import of `boru:string-util`. A template
therefore cannot perform I/O or escape the sandbox. The policy also
declares step/time/output limits; note that the current `boru:vm` build
does **not** enforce the step/time limits (see
[dx-report.md](../dx-report.md) §5) — capability isolation is the operative
guarantee, and a template cannot express unbounded computation anyway.
