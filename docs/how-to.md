# How-to guides

Task-oriented recipes. For a guided introduction start with the
[Tutorial](tutorial.md); for the *why* behind any of these, follow the
links into the [Explanation](explanation.md); for exact signatures, the
[Reference](reference.md).

- [Install and run boru](#install-and-run-aql)
- [Render a template](#render-a-template)
- [Compile once and render many contexts](#compile-once-and-render-many-contexts)
- [Choose an engine](#choose-an-engine)
- [Escape (or not) interpolated values](#escape-or-not-interpolated-values)
- [Loop over a list](#loop-over-a-list)
- [Branch with conditionals](#branch-with-conditionals)
- [Use filters (liquid / jinja)](#use-filters-liquid--jinja)
- [Set a variable mid-template (liquid / jinja)](#set-a-variable-mid-template-liquid--jinja)
- [Handle a bad engine or template](#handle-a-bad-engine-or-template)
- [Use the library from your own script](#use-the-library-from-your-own-script)
- [Run the tests](#run-the-tests)

---

## Install and run boru

The module is written in boru, which has no tagged release, so build the
interpreter from source at the commit this library pins
(`6185620`, latest `main`):

```bash
mkdir -p /tmp/aql && curl -fsSL \
  "https://codeload.github.com/boru-lang/boru/tar.gz/618562025d9e0154107306927911a8b1b046333c" \
  | tar -xz -C /tmp/boru --strip-components=1
( cd /tmp/aql/cmd/go && GOFLAGS=-mod=mod go build -o "$HOME/.local/bin/boru" ./boru )
```

(The codeload tarball works where the `boru-lang/boru` git remote is
egress-blocked; a `git clone` + `git checkout 6185620…` works too.) Make
sure `$HOME/.local/bin` is on your `PATH`, then check it:

```bash
boru -version
```

Run any script in this repo from the repo root (so `./template.aql`
resolves):

```bash
boru test/template_smoke_test.aql
```

This module is verified against boru commit `6185620`. In Claude Code web
sessions the SessionStart hook builds it for you.

---

## Render a template

The one-shot form compiles and renders in a single call:

```boru
import "./template.aql"
print ({engine:'mustache' source:'Hi {{name}}!' context:{name:'Ada'}} Template.render)
# => Hi Ada!
```

The context can be any value — usually a Map of the fields your template
references.

---

## Compile once and render many contexts

Split the work: `Template.compile` returns a reusable `Compiled`, and
`Template.render` runs it against each context. `render`'s receiver (the
`Compiled`) is its **last** argument, so the canonical forward form is
`Template.render context compiled`; piping `compiled Template.render context`
(below) is equivalent.

```boru
import "./template.aql"
def tpl ({engine:'mustache' source:'<li>{{label}}</li>'} Template.compile)
print (Template.render {label:'a'} tpl)   # forward form (canonical)
print (tpl Template.render {label:'b'})   # piping — also correct
```

---

## Choose an engine

The `engine` field selects the language; the config and context data are
identical across all four. `Template.engines` lists what this build
implements.

```boru
import "./template.aql"
print (Template.engines)   # => [mustache, handlebars, liquid, jinja]
```

---

## Escape (or not) interpolated values

Mustache and handlebars HTML-escape `{{x}}`; use `{{{x}}}` or `{{& x}}`
for raw. Liquid and jinja are raw by default; pipe through `escape` for
HTML.

```boru
import "./template.aql"
print ({engine:'mustache' source:'{{x}} | {{{x}}}' context:{x:'<b>&"'}} Template.render)
# => &lt;b&gt;&amp;&quot; | <b>&"
print ({engine:'liquid' source:'{{ x }} | {{ x | escape }}' context:{x:'<b>'}} Template.render)
# => <b> | &lt;b&gt;
```

---

## Loop over a list

Each engine has its own loop syntax over the same list data:

```boru
import "./template.aql"
print ({engine:'mustache'   source:'{{#xs}}[{{.}}]{{/xs}}'                 context:{xs:['a' 'b']}} Template.render)  # => [a][b]
print ({engine:'handlebars' source:'{{#each xs}}{{@index}}:{{this}} {{/each}}' context:{xs:['a' 'b']}} Template.render)  # => 0:a 1:b
print ({engine:'liquid'     source:'{% for x in xs %}{{ x }}-{% endfor %}'  context:{xs:['a' 'b']}} Template.render)  # => a-b-
print ({engine:'jinja'      source:'{% for x in xs %}{{ loop.index }}{% endfor %}' context:{xs:['a' 'b']}} Template.render)  # => 12
```

Liquid exposes `forloop.{index,index0,first,last,length}`; jinja exposes
`loop.{…}`. Both `for`s take an `{% else %}` branch for the empty case.

---

## Branch with conditionals

```boru
import "./template.aql"
# handlebars
print ({engine:'handlebars' source:'{{#if ok}}Y{{else}}N{{/if}}' context:{ok:true}} Template.render)   # => Y
# liquid (with elsif and comparisons)
print ({engine:'liquid' source:'{% if n > 2 %}big{% elsif n == 2 %}two{% else %}small{% endif %}' context:{n:5}} Template.render)  # => big
# jinja (elif)
print ({engine:'jinja' source:'{% if a and b %}both{% endif %}' context:{a:true b:true}} Template.render)  # => both
```

Liquid/jinja conditions support `== != < > <= >=` and `and` / `or`.

---

## Use filters (liquid / jinja)

Pipe a value through one or more filters; some take arguments:

```boru
import "./template.aql"
print ({engine:'liquid' source:'{{ name | upcase }}'            context:{name:'ada'}} Template.render)        # => ADA
print ({engine:'liquid' source:'{{ xs | join: ", " }}'         context:{xs:['a' 'b' 'c']}} Template.render)  # => a, b, c
print ({engine:'liquid' source:'{{ missing | default: "n/a" }}' context:{}} Template.render)                  # => n/a
print ({engine:'jinja'  source:'{{ name | lower | capitalize }}' context:{name:'WORLD'}} Template.render)      # => World
```

Built-in filters: `upcase`/`upper`, `downcase`/`lower`, `capitalize`,
`size`/`length`, `first`, `last`, `join`, `default`, `append`, `prepend`,
`replace`, `escape`, `strip`/`trim`.

---

## Set a variable mid-template (liquid / jinja)

```boru
import "./template.aql"
print ({engine:'liquid' source:'{% assign who = "world" %}Hi {{ who }}, {{ name }}' context:{name:'Ada'}} Template.render)
# => Hi world, Ada
print ({engine:'jinja'  source:'{% set n = 3 %}{{ n }}' context:{}} Template.render)
# => 3
```

The assigned variable is visible for the rest of its enclosing block, on
top of the surrounding context.

---

## Handle a bad engine or template

Failures raise coded errors; trap them with `do … error …` and read
`code` / `message` with a **quoted** key.

```boru
import "./template.aql"
# unknown engine ('erb' is not implemented)
print (do [{engine:'erb' source:'x' context:{}} Template.render] error [ get "code" ])
# => unknown_engine

# malformed template
print (do [{engine:'mustache' source:'{{#a}}x{{/b}}' context:{}} Template.render] error [ get "message" ])
# => mismatched close: expected {{/a}}, got {{/b}}
```

Codes: `bad_input` (compile/render arguments missing or wrong type),
`unknown_engine`, `template_syntax` (malformed/unbalanced template; a
truly unterminated tag surfaces as `parse_syntax_error` from the parser).

---

## Use the library from your own script

Import by relative path; you do **not** need to import `boru:parse`,
`boru:parselang`, `boru:string-util`, or `boru:vm` — `template.aql` pulls in
its own dependencies.

```boru
import "./template.aql"
def page ({engine:'liquid' source:'<h1>{{ title }}</h1>'} Template.compile)
print (page Template.render {title:'Home'})
```

`test/template_smoke_test.aql` is a complete worked example.

---

## Run the tests

```bash
boru test/template_unit_test.aql    # mustache unit tests — direct (boru:test)
boru test/template_unit_spec.aql    # mustache unit tests — declarative spec
boru test/template_prop_test.aql    # mustache property tests — direct
boru test/template_prop_spec.aql    # mustache property tests — declarative spec
boru test/template_smoke_test.aql   # end-to-end smoke over all four engines
boru test/handlebars_unit_test.aql  # handlebars engine
boru test/liquid_unit_test.aql      # liquid engine
boru test/jinja_unit_test.aql       # jinja engine
```

Or all at once:

```bash
for f in test/*.aql; do boru "$f"; done
```

Each assertion-bearing suite ends by asserting `Test.fail-count` is `0`
and prints `all green`, so a failure makes `boru` exit non-zero.

> **Execution surfaces.** Everything runs cleanly on the interpreter, and
> `boru -compile X` (bytecode) is byte-identical to it. `boru check` and
> `boru -force-compile` report false positives on this module (runtime-
> registered parsers are invisible to static analysis) — see
> [dx-report.md](../dx-report.md) §11–13.
