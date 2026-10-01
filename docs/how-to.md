# How-to guides

Task-oriented recipes. For a guided introduction start with the
[Tutorial](tutorial.md); for the *why* behind any of these, follow the
links into the [Explanation](explanation.md); for exact signatures, the
[Reference](reference.md).

- [Install and run boru](#install-and-run-boru)
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
`boru` binary from source. The library tracks boru-lang/boru **main** (no
pinned commit; last verified against main @ `64c5ab2`, 2026-10-01):

```bash
mkdir -p /tmp/boru && curl -fsSL \
  "https://codeload.github.com/boru-lang/boru/tar.gz/main" \
  | tar -xz -C /tmp/boru --strip-components=1
( cd /tmp/boru/cmd/go && GOWORK=off GOFLAGS=-mod=mod go build -o "$HOME/.local/bin/boru" ./boru )
```

(The codeload tarball works where the `boru-lang/boru` git remote is
egress-blocked; a `git clone` works too. `cmd/go` → `./boru` names the
binary `boru`. `GOWORK=off` is needed because the source tree carries
boru's `go.work`, and `-mod=mod` is refused in workspace mode.) Make sure
`$HOME/.local/bin` is on your `PATH`, then check it:

```bash
boru -version
```

A relative import resolves against the **importing file's own
directory**, so a script next to `template.aql` writes
`import "./template.aql"` and a suite in `test/` writes
`import "../template.aql"`; run them from anywhere:

```bash
boru test/template_smoke_test.aql
```

`boru X` is the only execution path: a static pre-flight check, then
compile to bytecode and run on the VM (the `--compile` /
`--force-compile` / `--no-compile` flags are retired). In Claude Code web
sessions the SessionStart hook builds boru for you.

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
print (Template.engines)   # => ["mustache", "handlebars", "liquid", "jinja"]
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

Failures raise coded errors; trap them with `do … error …` and, in the
handler, read `code` / `message` with a **quoted** key (`get "code"`) or
with `dot code` — `get` evaluates its key, so a bare `get code` is an
`undefined_word` check error.

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

Import by a path relative to *your* file (the importing file's own
directory); you do **not** need to import `boru:parse`,
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

The gate CI runs — every suite compiles and runs green under `boru X`,
`boru check X` reports 0 errors on every suite, and `boru check
template.aql` reports 0 errors:

```bash
BORU=$HOME/.local/bin/boru test/divergence/run.sh   # reuse a binary
test/divergence/run.sh                              # or build boru @ main HEAD
```

> **One execution path.** On boru main every suite fully compiles to
> bytecode and runs on the VM; there is no interpreter fallback to compare
> against. `boru check template.aql` reports 0 errors (six infos: the
> runtime-registered `parse <engine>` calls are dynamic to the static pass,
> and the mutually recursive compiler helpers are read before their
> definition). See [dx-report.md](../dx-report.md), "Migration to boru main
> @ 64c5ab2".
