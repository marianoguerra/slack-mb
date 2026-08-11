# slack-mb

[![check](https://github.com/marianoguerra/slack-mb/actions/workflows/ci.yml/badge.svg)](https://github.com/marianoguerra/slack-mb/actions/workflows/ci.yml)
[![mooncakes](https://img.shields.io/badge/mooncakes-marianoguerra%2Fslack-blue)](https://mooncakes.io/docs/marianoguerra/slack)

A Slack Web API client for MoonBit.

**The library's own README, with the examples, is [`slack/README.mbt.md`](slack/README.mbt.md).**
This file is about the repository.

```sh
moon add marianoguerra/slack
```

## Three modules

```
slack/   marianoguerra/slack        published; no dependencies; wasm, wasm-gc, js, native
http/    marianoguerra/slack-http   published; the native transport; moonbitlang/async; native
ext/     marianoguerra/slack-ext    not published; the generator, the corpus tests, the demo CLI
```

The split is not cosmetic. In MoonBit the module is the unit of publication
*and* of dependencies, so a single module would make someone who only wants
`@slack/blocks` on wasm-gc resolve an async runtime they will never link.
`slack/` therefore imports nothing outside `moonbitlang/core`, and everything
that would have cost it that lives elsewhere.

That is two different reasons to be elsewhere, which is why there are two other
modules rather than one. `http/` is a dependency a consumer may well want, just
not unconditionally: it is one file, it depends on `moonbitlang/async`, and it
is published so that `moon add marianoguerra/slack-http` is the whole story.
`ext/` is a dependency nobody wants — the code generator and the conformance
tests that read 5 MB of vendored fixtures off disk (`moonbitlang/x/fs`) — so it
is not published at all.

| Package | What is in it |
| --- | --- |
| `slack/api` | `Transport`, request building, form encoding, the response envelope, the error taxonomy |
| `slack/blocks` | Block Kit: layout blocks, elements, rich text, composition objects, builders |
| `slack/client` | `Client`, ~60 typed calls, the paginator |
| `slack/crypto` | SHA-256, HMAC-SHA256, hex, constant-time compare |
| `slack/signature` | Request-signature verification |
| `slack/methods` | 326 method names and their rate-limit tiers (generated) |
| `slack/ratectl` | Leaky-bucket throttling, with an injected clock |
| `slack/testing` | `FakeTransport`: a scripted transport |
| `slack/model` | The domain model: `User`, `Channel`, `Message` and nine more, with `from_json` (generated) |
| `slack/typed` | `Api`: 31 of `Client`'s calls, answering domain types instead of an envelope |
| `slack/mock` | An in-memory Slack: a workspace with state, and a transport over it |
| `slack/internal/jsonx` | The take-and-remove JSON helpers @blocks parses with. Internal; no version guarantee |
| `http/transport` | The native transport, over `moonbitlang/async` |
| `ext/scenario` | The integration scenario, as a library: one `run`, two transports |
| `ext/shape` | Comparing two payloads by shape rather than by value |
| `ext/cmd/main` | A demo CLI, which is how the transport gets exercised |
| `ext/cmd/integration` | The scenario against a real workspace; needs a token |
| `ext/tools/gen_methods` | Generates `slack/methods/generated_methods.mbt` |
| `ext/tools/gen_model` | Generates `slack/model/generated_model.mbt` |
| `ext/test/*` | Conformance tests over the vendored corpus, the mock, the model, the version sites and the async client tests |

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

309 tests: 252 on wasm and 57 more on native (the async client tests, the
scenario against the mock, everything that reads the corpus off disk, and
anything else that needs a runtime).

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

## The domain model

`slack/client` answers an `ApiResponse` whose payload is `Json`, because 326
methods cannot have 326 response types and because a field Slack shipped last
Tuesday must not break a bot. `slack/model` is the other half of that bargain:
twelve entities — `User`, `Profile`, `Channel`, `ChannelText`, `Message`,
`Edited`, `Reaction`, `BotProfile`, `Team`, `Usergroup`, `View`, `File` — as
structs, with everything else still reachable.

```moonbit
let response = client.users_info(user="U0123456789")
guard @model.User::from_json(response.get("user").unwrap()) is Some(user)
println("\{user.display()} in \{user.tz.unwrap_or("an unknown zone")}")
```

Three rules, all inherited from the Block Kit model next door:

- **Every field is optional but `id`**, and absent is `None` rather than `""`.
  Slack sends `""` for an unset display name and omits the field entirely when
  it is outside your scopes; a model that defaulted would erase the difference.
- **Nothing is dropped.** Each struct carries an `extra` holding every field
  this version does not model, and `to_json(from_json(x)) == x` over the whole
  corpus. A field at an unexpected type is never *taken*, so it lands in `extra`
  rather than being silently lost — which is what makes `extra` a mechanism
  instead of a promise.
- **A message's `blocks` are Block Kit**, parsed into `Array[LayoutBlock]` by
  the package that already models them.

Extraction is per method, never generic, and the corpus is why: `channel` is an
object on `conversations.info` and a *string* on `chat.postMessage`, and
`members` is `Array[User]` on `users.list` and `Array[String]` on
`conversations.members`. There is no `ApiResponse::user()`, and there should not
be one.

`slack/model/generated_model.mbt` is generated from `ext/metadata/model.json`,
which records where in the corpus each entity was observed and at which type.
`ext/test/modelcorpus` is the gate: it round-trips every occurrence in both
fixture tiers, fails if a modelled field ever falls into `extra` — the signal
that Slack changed a type and the struct field now reads `None` forever — and
holds a per-entity coverage floor so the first two properties cannot be
satisfied by modelling nothing.

## Two levels

`slack/typed` puts the two together. `Api` wraps a `Client` and offers 31 of its
calls under **the same names and the same arguments**, differing only in what
they answer:

```moonbit
let api = @typed.Api::of(client)

let user = api.users_info(user="U0123456789")          // a User
let page = api.conversations_history(channel="C1")     // a Page[Message]
let posted = api.chat_post_message(channel="C1", text="hi")  // ids and a Message

api.client().bookmarks_list(channel_id="C1")           // and the low level, still there
```

`Api::client()` is not an escape hatch so much as the other half: `Client::call`
reaches all 326 methods and `ApiResponse.raw` reaches every field. Mixing the
two in one function is the expected way to use this.

Failures come back as `TypedError`, which is `Slack(e)` — everything `Client`
could already fail with, untouched — or `ResponseShapeError(api_method~, key~)`
for the case where Slack answered `ok: true` and the payload was not what this
version models. `TypedError::slack()` gets to the wrapped error in one step,
because a rate limit is the case that actually happens. It is a separate type
rather than a seventh `SlackError` variant because `SlackError::code()` returns
node-slack-sdk's `ErrorCode` strings verbatim, and there is no node counterpart
to borrow for this one.

`ext/test/highlevel` runs all of it against `@mock` rather than a scripted
transport, because what these calls know that nothing else does is which key
each method puts its payload under — and a fake would answer whatever its
author believed that key to be. A drift test scrapes the two generated
interfaces and fails if an `Api` method has no `Client` counterpart of the same
name.

## Testing against a Slack that is not there

`slack/mock` is a Slack workspace in memory: users, channels, DMs, threads,
reactions, pins, files and views, behind all 62 methods `Client` exposes. It is
published, and dependency-free, for the same reason `slack/testing` is — an app
built on this library needs it, and would otherwise write it again, slightly
worse.

```moonbit
let ws = @mock.Workspace::new()
let alice = ws.add_user(name="alice", real_name="Alice Alvarez")
let general = ws.add_channel(name="general", members=[alice])
ws.add_message(channel=general, user=alice, text="hello")
ws.install_app(token="xoxb-test", user=alice, scopes=["chat:write", "channels:history"])

let client = @client.Client::new(ws.transport(), "xoxb-test")
```

`@mock.Workspace::demo()` skips the seeding: four people and a bot, three
channels, a DM, an MPIM, a thread with replies and reactions, a pinned message,
a usergroup and a file, plus `demo_token`, which holds every scope.

Which of the two fakes to reach for: `@testing.FakeTransport` when the test is
about one call and the response IS the fixture — a 500, a malformed body, a
specific `ok: false`. `@mock` when the test is about a sequence, and the second
call has to see what the first one did.

It reproduces what an app actually trips over: `missing_scope` with `needed` and
`provided`, `invalid_auth` and `token_revoked`, `already_reacted`, `name_taken`,
`channel_not_found` — including the asymmetry where `chat.postMessage` accepts a
channel *name* and `chat.update` refuses the same string. Faults are injectable
(`ws.inject("chat.postMessage", RateLimited(30))`), which reaches the 429,
5xx, non-JSON and dropped-socket paths mid-scenario rather than only from a
scripted list. Ids and timestamps are deterministic; the clock is an `Int64` the
caller advances, so nothing here reads one.

### What keeps it honest

A mock nobody checks drifts from Slack and becomes a machine for passing tests
that should fail. Four independent checks pin it, all four beside the existing
suite:

| check | where | what it asserts |
| --- | --- | --- |
| shape against the corpus | `ext/test/mockshape` | every field the mock emits exists in `ext/fixtures/java/api/<method>.json` at the same JSON type. Values are never compared, so ids and timestamps diverge harmlessly |
| coverage | `ext/test/mockshape` | 158 of the 190 top-level response fields the samples carry. A floor, so the check above cannot pass by emitting `{"ok": true}` |
| the same scenario, both transports | `ext/test/mockrun` | `ext/scenario`'s `run` — the one `ext/cmd/integration` points at Slack — passes against the mock with **zero failures and zero skips**. Every scope is granted there, so a skip is a mock bug |
| Block Kit round trip | `ext/test/mockshape` | every blocks array the mock emits parses and re-serialises byte for byte, the same property `ext/test/corpus` holds 2,548 real blocks to |

A fifth, opt-in: `ext/recordings/README.md` covers recording a real run and
diffing the mock's against it. It self-skips without a recording.

The mock's handler list is checked against `Client`'s typed methods by scraping
the two generated files, so adding a typed call fails a test until a handler
exists.

Three tolerances are recorded in `ext/test/mockshape`, each with its reason:
they are places where java-slack-sdk's sample is a union of what its maintainers
happened to record and is missing a field Slack documents. Their growth is worth
watching in review — each one is the check being switched off for a path.

## The integration harness

`ext/cmd/integration` runs the same scenario against a real workspace. It never runs
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

# and, to record the run for ext/test/mockrun to replay against:
moon run --target native ext/cmd/integration -- --record
```

The scenario itself lives in `ext/scenario` and is a plain function of a
`Client`, which is what lets `ext/test/mockrun` run it in CI against the mock.
Only the token, the transport and the exit code are here.

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

`slack/` and `http/` are published; `ext/` is not. Each tarball is built from
its own directory, so it must stand up with no workspace around it — which is
what the pre-publish check below proves. Publish `slack/` first: `http/`
depends on it at an exact version.

```sh
cd slack
moon package                     # writes _build/publish/marianoguerra-slack-<version>.zip
# extract it somewhere empty and, from there:
#   for t in wasm wasm-gc js native; do moon check --target $t --deny-warn; done
#   moon test --target all
moon publish

cd ../http
moon package
# extract it somewhere empty and, from there:
#   moon check --target native --deny-warn
moon publish
```

The version lives in **six** places, and only the first is obvious.
`ext/test/version` checks the other five against `slack/moon.mod` and fails
naming whichever went stale, so this table is documentation rather than the
thing standing between you and a bad release. Grep anyway:

```sh
grep -rn "$OLD_VERSION" --include="*.mod" --include="*.mbt" slack http ext
```

| where | what |
| --- | --- |
| `slack/moon.mod` | `version` |
| `slack/api/request.mbt` | `user_agent` hardcodes it. The one site nothing resolves against, so a stale value ships silently — which it did through 0.1.0 and 0.2.0. Now gated |
| `http/moon.mod` | `version`, and the `marianoguerra/slack@` import constraint |
| `ext/moon.mod` | `version`, and both import constraints — or the workspace stops resolving |

Then add a `CHANGELOG.md` entry and tag `v<version>`.
A published version cannot be withdrawn.

## Licence

Apache-2.0. The licence text ships with the package (`slack/LICENSE`). The
vendored fixtures are MIT (java-slack-sdk) and Apache-2.0 (slack-morphism); see
`ext/fixtures/VENDOR.md`.
