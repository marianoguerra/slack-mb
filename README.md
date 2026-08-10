# slack-mb

[![check](https://github.com/marianoguerra/slack-mb/actions/workflows/ci.yml/badge.svg)](https://github.com/marianoguerra/slack-mb/actions/workflows/ci.yml)
[![mooncakes](https://img.shields.io/badge/mooncakes-marianoguerra%2Fslack-blue)](https://mooncakes.io/docs/marianoguerra/slack)

A Slack Web API client for MoonBit.

**The library's own README, with the examples, is [`slack/README.mbt.md`](slack/README.mbt.md).**
This file is about the repository.

```sh
moon add marianoguerra/slack
```

## Two modules

```
slack/   marianoguerra/slack       published; no dependencies; wasm, wasm-gc, js, native
ext/     marianoguerra/slack-ext   not published; native HTTP, the generator, the corpus tests
```

The split is not cosmetic. In MoonBit the module is the unit of publication
*and* of dependencies, so a single module would make someone who only wants
`@slack/blocks` on wasm-gc resolve an async runtime they will never link.
`slack/` therefore imports nothing outside `moonbitlang/core`, and everything
that would have cost it that — the HTTP transport (`moonbitlang/async`, native
only), the code generator and the conformance tests that read 5 MB of vendored
fixtures off disk (`moonbitlang/x/fs`) — lives in `ext/`.

| Package | What is in it |
| --- | --- |
| `slack/api` | `Transport`, request building, form encoding, the response envelope, the error taxonomy |
| `slack/blocks` | Block Kit: layout blocks, elements, rich text, composition objects, builders |
| `slack/client` | `Client`, ~60 typed calls, the paginator |
| `slack/crypto` | SHA-256, HMAC-SHA256, hex, constant-time compare |
| `slack/signature` | Request-signature verification |
| `slack/methods` | 326 method names and their rate-limit tiers (generated) |
| `slack/ratectl` | Leaky-bucket throttling, with an injected clock |
| `slack/testing` | `FakeTransport` |
| `ext/transport_http` | The native transport, over `moonbitlang/async` |
| `ext/cmd/main` | A demo CLI, which is how `transport_http` gets exercised |
| `ext/tools/gen_methods` | Generates `slack/methods/generated_methods.mbt` |
| `ext/test/*` | Conformance tests over the vendored corpus, and the async client tests |

## Working on it

```sh
just            # check + test
just ci         # everything CI runs
just check      # moon check --deny-warn, per module
just backends   # the library on wasm, wasm-gc, js and native
just test       # moon test, then moon test --target native
just fmt        # moon fmt && moon info
```

`moon check` does **not** recurse into workspace members, so each module is
checked in its own directory — checking only from the root would silently skip
most of it. `moon test`, on the other hand, covers the whole workspace from
wherever it was invoked, which is why the tests that read files probe for their
fixtures rather than assuming a working directory.

211 tests: 183 on wasm and 28 more on native (the async client tests, the
large-fixture corpus, and anything else that needs a runtime).

## Where the behaviour comes from

Almost nothing here was invented. Each rule is pinned by a test ported from one
of Slack's own SDKs or a well-established community one, and the test says
which — see "Provenance" in [`slack/README.mbt.md`](slack/README.mbt.md).

The largest piece of borrowed evidence is java-slack-sdk's `json-logs`: 565 real
API responses, recorded live, scrubbed to type-representative placeholders, and
merged so that each file is the union of every shape its method has been
observed to return. `ext/test/corpus` parses all of them and asserts that every
Block Kit payload inside round-trips byte for byte — 2,548 blocks, including
fields this library has never heard of.

## The integration harness

`ext/cmd/integration` runs the library against a real workspace. It never runs
in CI — it needs a token — but it checks two things no fixture can:

- **the form encoder against Slack's own parser.** `api.test` echoes its
  arguments back, so awkward values (`São Paulo`, `a&b=c`, `1+1 = 2`, `🎉`) are
  compared with what Slack *decoded*, not with another SDK's expectations.
- **the Block Kit round trip on blocks Slack generates today.** The vendored
  corpus was recorded at some point in the past; a field Slack added since would
  show up here first.

```sh
export SLACK_BOT_TOKEN=xoxb-...
export SLACK_TEST_CHANNEL='#slack-integration'   # optional; this is the default
moon run --target native ext/cmd/integration
```

It skips, loudly, whatever the token's scopes do not allow, so it is useful with
a minimal token and more useful with a broad one. Everything it posts, it
deletes. `SLACK_CLEANUP_TS=<ts>` also deletes a message an earlier run left
behind.

The widest useful bot scopes are `chat:write`, `chat:write.public`,
`channels:read`, `channels:history`, `users:read`, `team:read`, `emoji:read`,
`reactions:write`. Without `chat:write.public` the bot must be invited to the
channel.

Two Slack behaviours it discovered, both now handled:

- `chat.postMessage` accepts a channel **name** (`#slack-integration`);
  `chat.update`, `chat.delete` and `conversations.history` do not, and answer
  `channel_not_found` for the same string. The resolved id comes back in the
  post response, so everything downstream uses that.
- `api.test` echoes the **token** back in its `args`, even though this library
  sends it in the `Authorization` header and never in the body. Anything that
  pretty-prints a response must redact — `ext/cmd/main` does, matching
  node-slack-sdk's debug-logging behaviour.

## The vendored corpus

```sh
just fixtures   # fetch the 17 fixtures too large to commit (38 MB)
```

`ext/fixtures/` holds 548 files (~5 MB), committed. The 17 at or above 512 KB
are 38 MB between them, only one test reads them, and they are therefore
gitignored; `ext/test/corpus_large` skips with a log line when they are absent,
so a fresh clone is green without them.

Re-vendor from local clones of the upstream SDKs with:

```sh
just vendor ../java-slack-sdk ../slack-morphism-rust
just gen        # regenerate the method table from the refreshed metadata
```

`ext/fixtures/VENDOR.md` and `ext/metadata/SOURCE.md` record what came from
where, at which commit, under which licence.

## Generated code

`slack/methods/generated_methods.mbt` is produced by `ext/tools/gen_methods`
from `ext/metadata/rate_limit_tiers.json`. Two independent gates keep it honest:
`just gen-check` fails CI when the checked-in file has drifted, and
`ext/test/coverage` — a port of java-slack-sdk's `MethodsTest#verifyTheCoverage`
— fails a normal `moon test` when the table stops covering Slack's documented
surface. The second is a test rather than a CI step on purpose: whether the
library covers the API is a product question, and a product question should fail
on a developer's machine too.

## Releasing

`slack/` is the published module; `ext/` is not published. The tarball is built
from `slack/` alone, so it must stand up with no workspace around it — which is
what the pre-publish check below proves.

```sh
cd slack
moon package                     # writes _build/publish/marianoguerra-slack-<version>.zip
# extract it somewhere empty and, from there:
#   for t in wasm wasm-gc js native; do moon check --target $t --deny-warn; done
#   moon test --target all
moon publish
```

Bump `version` in `slack/moon.mod`, add a `CHANGELOG.md` entry, tag `v<version>`.
A published version cannot be withdrawn.

## Licence

Apache-2.0. The licence text ships with the package (`slack/LICENSE`). The
vendored fixtures are MIT (java-slack-sdk) and Apache-2.0 (slack-morphism); see
`ext/fixtures/VENDOR.md`.
