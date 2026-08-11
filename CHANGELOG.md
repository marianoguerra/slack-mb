# Changelog

## 0.3.0

### Added

- **`marianoguerra/slack-http` — the native HTTP transport, now published.** It
  was `ext/transport_http`, which meant the only ready-made way to reach Slack
  over a socket lived in a module explicitly marked "not published"; the
  documented answer was to copy the file. It is its own module now, one package
  and one file, depending on `marianoguerra/slack` and `moonbitlang/async` and
  nothing else.

  ```sh
  moon add marianoguerra/slack-http
  ```

  ```moonbit
  let client = @client.Client::new(@transport.HttpTransport::new(), token)
  ```

  A third module rather than a package of `marianoguerra/slack`, because in
  MoonBit an import is module-wide: putting it there would hand an async runtime
  to everyone who only wants Block Kit on wasm-gc. The public API is byte for
  byte what it was — `HttpTransport`, `HttpTransport::new(description?)` and the
  `@api.Transport` impl — so the only change for an existing caller is the
  import path, `marianoguerra/slack-ext/transport_http` becoming
  `marianoguerra/slack-http/transport`.

- **`slack/model` — the domain model.** Twelve entities as MoonBit structs:
  `User`, `Profile`, `Channel`, `ChannelText`, `Message`, `Edited`, `Reaction`,
  `BotProfile`, `Team`, `Usergroup`, `View` and `File`. Until now the only way
  to read a response was to walk `ApiResponse.raw` by hand, with no
  compile-time help and no single place where Slack's field names lived.

  ```moonbit
  let response = client.users_info(user="U0123456789")
  guard @model.User::from_json(response.get("user").unwrap()) is Some(user)
  println("\{user.display()} in \{user.tz.unwrap_or("an unknown zone")}")
  ```

  It does not replace `raw`, it sits beside it. Every field but `id` is
  optional, absent is `None` rather than `""`, and each struct carries an
  `extra` holding everything this version does not model — so a field Slack
  ships next Tuesday arrives intact rather than breaking anything. A message's
  `blocks` parse into the `LayoutBlock` values `@blocks` already models, which
  is most of the reason to model a message at all.

  There is deliberately no generic extractor. `channel` is an object on
  `conversations.info` and a string on `chat.postMessage`; `members` is a list
  of users on `users.list` and a list of ids on `conversations.members`. Only
  the method knows which, so only the caller can say.

  `generated_model.mbt` comes from `ext/metadata/model.json`, which records
  where in the corpus each entity was observed and at which type — the same
  arrangement the method table has had since 0.1.0. `just gen-check` is the
  drift gate.

  Five hand-written accessors sit on top, each one collapsing an option chain
  that is easy to get subtly wrong: `User::display` falls back display_name →
  real_name → name → id the way Slack's own clients do, and
  `Message::thread_root` answers the question neither `ts` nor `thread_ts`
  answers alone.

- **`slack/typed` — the same calls, one level up.** `Api` wraps a `Client` and
  offers 31 of its methods under **the same names and the same arguments**,
  differing only in what they answer: a `User` rather than an `ApiResponse`, a
  `Page[Message]` rather than an envelope to walk.

  ```moonbit
  let api = @typed.Api::of(client)
  let page = api.conversations_history(channel="C1", limit=50)
  for message in page.items {
    println(api.users_info(user=message.user.unwrap()).display())
  }
  api.client().bookmarks_list(channel_id="C1")   // and the low level, still there
  ```

  A wrapper struct rather than more methods on `Client`, for two reasons.
  MoonBit only allows a method in the package that defines its type. And
  keeping them apart is what lets a call here take the same name as the one it
  wraps — `client.users_info(...)` gives an envelope, `api.users_info(...)`
  gives a `User`.

  `Api::client()` is the other half rather than an escape hatch: `Client::call`
  reaches all 326 methods, `ApiResponse.raw` reaches every field, and mixing
  the two levels in one function is the expected way to use this.

  `Page[T]` carries the items, the whole response, and a `cursor` normalised to
  `None` on the last page — Slack ends a walk with an *empty* `next_cursor`
  rather than by omitting it, which is the easiest way there is to write an
  infinite loop over the last page.

  Failures are `TypedError`: `Slack(e)`, which is everything `Client` could
  already fail with, untouched; or `ResponseShapeError(api_method~, key~)` for
  `ok: true` with a payload this version cannot read. `TypedError::slack()`
  reaches the wrapped error in one step, because a rate limit is the case that
  actually happens. A separate type rather than a seventh `SlackError` variant
  on purpose: that taxonomy's `code()` strings are node-slack-sdk's `ErrorCode`
  values verbatim, there is no node counterpart to borrow for this, and
  inventing one would make @api's claim to be a faithful port false. Nothing in
  `@api` or `@client` changed.

### Verification

- **`ext/test/highlevel`** runs all 31 calls against `@mock` rather than a
  scripted transport. What a typed call knows that nothing else does is which
  key its method puts the payload under, and a fake would answer whatever its
  author believed that key to be — the belief being the thing under test. The
  mock's own output is held to the recorded corpus by `ext/test/mockshape`, so
  a wrong key fails instead of agreeing with itself. A drift test scrapes the
  two generated interfaces and fails if an `Api` method has no `Client`
  counterpart of the same name.

- **`ext/test/modelcorpus`** holds three properties over both fixture tiers:
  every entity occurrence round-trips byte for byte — 279 in the small tier and
  327 in the large one, where the messages are; no modelled field is ever left
  in `extra`, which is what catches Slack changing a field's type and the struct
  quietly reading `None` forever; and a per-entity coverage floor, so the first
  two cannot be satisfied by modelling nothing. Coverage today: `User` 50 of 52
  observed fields, `Channel` 61 of 68, `Message` 38 of 52, `File` 57 of 159 —
  the last deliberately, since most of the rest are thumbnail dimensions in a
  dozen sizes.

### Changed

- **`slack/internal/jsonx`** — the take-and-remove JSON helpers moved out of
  `@blocks` into an internal package, unchanged, so a second parser can inherit
  the discipline rather than a second copy of it. `@blocks`'s `.mbti` is
  untouched, which is the proof the refactor is one; the helpers now carry six
  tests of their own, pinning invariants their doc comments had been claiming on
  the strength of `ext/test/corpus` alone. `internal/` means no version
  guarantee: nothing outside this repo should import it.

  Preparation for a domain-model package (`User`, `Channel`, `Message`) over the
  responses `ApiResponse.raw` currently hands back as `Json`.

## 0.2.0

### Added

- **`slack/mock` — an in-memory Slack.** A workspace with state in it: users,
  channels, DMs, MPIMs, threads, reactions, pins, bookmarks, usergroups, files
  and views, behind all 62 methods `Client` exposes. Published and
  dependency-free, for the reason `slack/testing` already is — an app built on
  this library needs one, and would otherwise write it again, slightly worse.

  `@testing.FakeTransport` answers a scripted list, which cannot express "the
  second call sees what the first one did"; this can. It reproduces the
  refusals an app actually meets (`missing_scope` with `needed`/`provided`,
  `invalid_auth`, `token_revoked`, `already_reacted`, `name_taken`), including
  the asymmetry where `chat.postMessage` takes a channel *name* and
  `chat.update` answers `channel_not_found` for the same string. Faults are
  injectable, reaching the 429, 5xx, non-JSON and dropped-socket paths
  mid-scenario. Ids and timestamps are deterministic and the clock is an `Int64`
  the caller advances — nothing here reads one, which is what keeps the package
  on every backend.

- **`@api.decode_form` and `@api.percent_decode_component`** — the inverse of
  the form encoder, beside it. The mock needs it, and so does anyone handling a
  slash command or an interactivity payload, which arrive as form bodies.
  Pinned by a round-trip property stated modulo `to_wire`, since the wire has no
  types.

### Verification

Four independent checks keep the mock from drifting into a machine for passing
tests that should fail:

- **Shape against the corpus** (`ext/test/mockshape`) — every field the mock
  emits exists in that method's recorded sample at the same JSON type. Values
  are never compared, so ids and timestamps diverge harmlessly. It found three
  invented fields while being written.
- **Coverage** — 158 of the 190 top-level response fields the samples carry,
  with a floor, so the check above cannot be satisfied by emitting `{"ok": true}`.
- **One scenario, two transports** (`ext/test/mockrun`) — `ext/cmd/integration`'s
  scenario moved into `ext/scenario` as a plain function of a `Client`. The CLI
  still points it at Slack; CI now points it at the mock and asserts **zero
  failures and zero skips**, since every scope is granted there.
- **Block Kit round trip on the mock's own output** — the property
  `ext/test/corpus` holds 2,548 real blocks to.

Plus a drift gate: the mock's handler list is derived a third way, from
`Client`'s typed methods, so adding one fails a test until a handler exists.

An opt-in fifth check records a real run, scrubs it, and diffs the mock's
against it; see `ext/recordings/README.md`.

### Changed

- `ext/cmd/integration` keeps its environment variables, defaults, output and
  exit codes, and gains `--record`. Its scenario now lives in `ext/scenario`.

## 0.1.0

First release.

A Slack Web API client whose semantics are borrowed rather than guessed: every
behavioural rule is pinned by a test ported from one of Slack's own SDKs or a
well-established community one, and each test names the upstream it came from.
211 tests, no network, no token required.

### The library — `marianoguerra/slack`

No dependencies outside `moonbitlang/core`. Builds and passes its full test
suite on `wasm`, `wasm-gc`, `js` and `native`.

- **`api`** — the `Transport` seam, request building, `application/x-www-form-urlencoded`
  encoding, the response envelope and the error taxonomy. `ErrorCode` strings
  and message text are node-slack-sdk's verbatim, so a team migrating keeps its
  log queries. Slack answers refusals with HTTP 200, so the status code and `ok`
  stay two separate questions throughout.
- **`blocks`** — typed Block Kit that round-trips: `to_json(from_json(x)) == x`,
  including fields this version does not model. Layout blocks, elements, rich
  text, composition objects and builders. Parsing is total — an unmodelled type
  becomes `Unknown` and keeps its payload — with strictness as a separate
  `validate` walk, so there is one parser rather than two that can drift.
- **`crypto`** — SHA-256 and HMAC-SHA256 in pure MoonBit, because
  `moonbitlang/core` has neither. RFC 6234 and RFC 4231 vectors.
- **`signature`** — Slack request-signature verification. `now` is an argument
  rather than a clock read, so expiry is deterministic and the package still
  builds on wasm.
- **`methods`** — 326 method names and their rate-limit tiers, generated from
  Slack's own metadata.
- **`ratectl`** — a leaky bucket with an injected clock, keyed so that
  `chat.postMessage` throttles per channel rather than per workspace.
- **`client`** — `Client`, a pure `Paginator`, and ~60 typed calls across
  `chat`, `conversations`, `users`, `auth`, `team`, `usergroups`, `views`,
  `reactions`, `files`, `pins` and `bookmarks`, with a generic `call` for the
  other 260 methods.
- **`testing`** — `FakeTransport`, published because a consumer testing their
  own Slack app needs exactly this.

### Verification

- **2,548 real Slack blocks round-trip byte for byte**, from java-slack-sdk's
  recorded `json-logs` corpus — payloads nobody hand-picked, merged so each file
  is the union of every shape its method has been observed to return.
- The form encoder is checked against **Slack's own parser** by an integration
  harness, not only against other SDKs' expectations: `api.test` echoes its
  arguments, so `São Paulo`, `a&b=c`, `1+1 = 2` and an astral-plane emoji are
  compared with what Slack decoded.
- Block Kit round-tripping is checked against blocks **Slack generates today**,
  by posting a message and reading it back — the recorded corpus can only speak
  for whenever it was recorded.

### Deliberate divergences from the reference SDKs

Each is a test with a comment saying which way it went and why.

- Booleans encode as `true`/`false` (node-slack-sdk) rather than `1`/`0`
  (java-slack-sdk). `BoolStyle` selects either, so both SDKs' golden bodies are
  testable literally.
- The signature timestamp window is two-sided (slack-morphism) rather than
  one-sided (java-slack-sdk), so a timestamp from the future is refused too.
  `max_age_seconds` widens it per verifier.
- A strict parse refuses an unknown text-object type in a `label` or
  `placeholder`, which java-slack-sdk's implementation lets through. Slack
  itself rejects it, so this follows Slack rather than the SDK.
- `limit` is sent on every paginated request including the first;
  node-slack-sdk adds it only from the second, which silently gives page one a
  different size from every later page.

### Not included

- The binary `PUT` of a file upload. `files.getUploadURLExternal` and
  `files.completeUploadExternal` are here; the transfer between them is an
  ordinary HTTP request to a URL Slack gives you, not a Web API call.
- `admin.analytics.getFile`'s gzip response — ungzipping needs a native-only
  dependency. The method works; you get the raw body.
- Typed event payload structs. `blocks` parses the Block Kit inside an event,
  but there are no `AppMentionEvent`-style types.
- Socket Mode and the RTM API. Web API only.
