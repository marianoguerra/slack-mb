# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) workspace holding a Slack Web
API client. Read `README.md` for the layout and `slack/README.mbt.md` for the
library's own documentation.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- Two modules, joined by `moon.work`: `slack/` (published, dependency-free,
  every backend) and `ext/` (not published; the native HTTP transport, the code
  generator, the fixture-corpus tests). The rationale is in `README.md` — in
  short, a single module would put an async runtime in the dependency graph of
  anyone who only wants Block Kit on wasm.

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In each module's toplevel directory there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Rules specific to this repository

- **`slack/` must not gain a dependency.** Not `moonbitlang/async`, not
  `moonbitlang/x`, nothing outside `moonbitlang/core`. It is what lets the
  library build on wasm, wasm-gc, js and native, and `just backends` is the
  gate. Anything that needs a socket, a filesystem or a clock goes in `ext/`,
  or behind an argument the caller supplies (`now : Int64`, `&Transport`).

- **That includes `slack/mock`,** which is the package most tempted to break it:
  a mock Slack wants a clock and wants to read fixtures off disk. It gets
  neither. `now` is an `Int64` the caller advances, `Workspace::demo()` is code
  rather than a file, and the whole state machine is synchronous so that
  `Workspace::invoke` can be tested in the package itself -- only the two-line
  `Transport` impl is async.

- **The mock answers to the corpus.** `slack/mock/render.mbt` may only emit
  fields that appear in `ext/fixtures/java/api/<method>.json`, at the type they
  appear at. `ext/test/mockshape` is the gate, and its `allow_unknown` table is
  the check being switched off for a path -- an entry there needs a reason
  saying why the corpus is wrong rather than the mock. Adding a typed method to
  `@client` fails the drift gate until a handler exists in `@mock`.

- **`slack/methods/generated_methods.mbt` is generated.** Do not edit it. Change
  `ext/metadata/rate_limit_tiers.json` and run `just gen`; `just gen-check` is a
  CI gate and `ext/test/coverage` is a normal test.

- **Every behavioural rule should cite its source.** The point of this library
  is that its semantics come from Slack's own SDKs rather than from guesswork,
  so a test that pins a rule names the upstream test it came from, and a
  deliberate divergence says so and says why. There are three today: boolean
  encoding, the signature timestamp window, and strict parsing of an unknown
  text type in a `label`.

- **The round-trip property is not optional.** `to_json(from_json(x)) == x` for
  every Block Kit payload, including fields this version does not model. That is
  what the `extra : Map[String, Json]` on every struct is for, and what
  `ext/test/corpus` checks against 2,548 real blocks. A new modelled field must
  be *taken* out of the input (`take_str`, `take_obj`, ...) so that a value of an
  unexpected type falls through to `extra` rather than being dropped.

- **`async test` needs `moonbitlang/async`,** which `slack/` does not have. Tests
  that must be async live in `ext/test/calls/`. Everything that can be
  synchronous already is, next to the code.

- A package's own name is in scope as an alias, so a test package called
  `client` would shadow `@client`. `ext/test/calls` is named that way for this
  reason.

- MoonBit's `Compare` for `String` is **shortlex** (shorter strings sort first).
  Use `lexical_compare` when you want dictionary order — the generated method
  table depends on it.

## Tooling

- `just` is the task runner: `just` (check + test), `just ci` (everything CI
  runs), `just fmt`, `just gen`, `just fixtures`.

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- `moon check` does NOT recurse into workspace members. Check each module in its
  own directory, which is what `just check` does. `moon test` DOES cover the
  whole workspace from any directory — which is why the tests that read files
  probe for their fixtures instead of assuming a working directory.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.
