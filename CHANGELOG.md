# Changelog

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
