# Tutorial

A learning-oriented walk from nothing to rendering templates in four
languages. Follow it in order; each step builds on the last. For exact
signatures see the [Reference](reference.md); for the *why*, the
[Explanation](explanation.md); for goal-directed recipes, the
[How-to guides](how-to.md).

You need a working `boru` interpreter — see
[How-to → Install and run boru](how-to.md#install-and-run-aql). Run each
snippet by saving it to a file and running `boru file.aql` from the
directory that contains `template.aql`.

## 1. Render your first template

`Template` turns a template string into text using a data **context**. The
simplest call is the one-shot form — compile and render in one go:

```boru
import "./template.aql"
print ({engine:'mustache' source:'Hello {{name}}!' context:{name:'Ada'}} Template.render)
# => Hello Ada!
```

Three things to notice, because boru is not C/Python/JS:

- The call reads **forward**: the options map sits to the left of the verb
  `Template.render` and flows into it. There is no `Template.render(opts)`.
- `{{name}}` is a **placeholder** filled from the context's `name` field.
- The whole call is wrapped in parens so its result becomes the argument
  to `print`.

## 2. Compile once, render many

If you render the same template repeatedly, compile it once and reuse the
`Compiled` value:

```boru
import "./template.aql"
def row ({engine:'mustache' source:'<li>{{label}}</li>'} Template.compile)
print (row Template.render {label:'first'})
print (row Template.render {label:'second'})
# => <li>first</li>
# => <li>second</li>
```

`Template.compile` does the parsing and code generation; `Template.render`
just runs the result against a context. Its receiver (the `Compiled`) is
the **last** argument, so the canonical forward form is
`Template.render {label:'first'} row`; piping it in from the left, as above,
is equivalent. (`tpl.engine` tells you which engine a compiled template was
built for.)

## 3. Escaping

In mustache and handlebars, `{{x}}` is **HTML-escaped** — a safe default
for web output. Use triple-stache for raw output:

```boru
import "./template.aql"
print ({engine:'mustache' source:'{{x}} | {{{x}}}' context:{x:'<b>'}} Template.render)
# => &lt;b&gt; | <b>
```

(Liquid and Jinja do **not** escape by default — see step 6.)

## 4. Sections and lists

A section repeats or conditionally shows a block. Over a list it iterates,
with `{{.}}` standing for the current item:

```boru
import "./template.aql"
print ({engine:'mustache' source:'{{#items}}[{{.}}]{{/items}}' context:{items:['a' 'b' 'c']}} Template.render)
# => [a][b][c]
```

Over a map, the section enters that map as the context; an inverted section
`{{^...}}` renders only when the value is falsy or empty:

```boru
import "./template.aql"
def src '{{#user}}{{name}}{{/user}}{{^user}}(none){{/user}}'
print ({engine:'mustache' source:src context:{user:{name:'Ada'}}} Template.render)   # => Ada
print ({engine:'mustache' source:src context:{}} Template.render)                     # => (none)
```

## 5. Handlebars block helpers

Handlebars reuses mustache's `{{ }}` and adds named block helpers — `if`,
`unless`, `each` (with `{{this}}` and `{{@index}}`), and `with`:

```boru
import "./template.aql"
print ({engine:'handlebars'
  source:'{{#if ok}}{{#each xs}}{{@index}}:{{this}} {{/each}}{{else}}none{{/if}}'
  context:{ok:true xs:['x' 'y']}} Template.render)
# => 0:x 1:y
```

## 6. Liquid and Jinja: filters and tags

Liquid and Jinja split syntax into `{{ output }}` and `{% tags %}` (Jinja
adds `{# comments #}`). Output can be piped through **filters**, and tags
give you `if`/`for`/`assign` (Liquid) or `if`/`for`/`set` (Jinja):

```boru
import "./template.aql"
# Liquid: a filter and a loop
print ({engine:'liquid'
  source:'{% for x in xs %}{{ x | upcase }} {% endfor %}'
  context:{xs:['a' 'b']}} Template.render)
# => A B

# Jinja: loop metadata + a comment
print ({engine:'jinja'
  source:'{% for x in xs %}{{ loop.index }}{% endfor %}{# done #}'
  context:{xs:['a' 'b' 'c']}} Template.render)
# => 123
```

Liquid and Jinja output is raw by default; pipe through the `escape` filter
when you need HTML escaping.

## 7. Handling a bad template

Errors are values you can catch. `do […] error […]` runs the handler with
the error on the stack; read its `code` with a **quoted** key:

```boru
import "./template.aql"
def result (do [{engine:'mustache' source:'{{#a}}x{{/b}}' context:{}} Template.render] error [
  get "code"
])
print (result)   # => template_syntax
```

## Where next

- Recipes for specific tasks: [How-to guides](how-to.md).
- Every signature and the per-engine feature tables: [Reference](reference.md).
- How the parse → compile → sandbox pipeline works: [Explanation](explanation.md).
