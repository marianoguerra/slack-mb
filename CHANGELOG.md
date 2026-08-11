# Changelog

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
