# marianoguerra/slack

A Slack Web API client for MoonBit.

- **No dependencies.** Builds and tests on `wasm`, `wasm-gc`, `js` and `native`.
  A Slack app compiled to wasm can verify a request signature and parse a Block
  Kit payload with nothing but this library.
- **Every method reachable.** 326 method names with their rate-limit tiers,
  generated from Slack's own metadata, plus typed calls for the families most
  apps use and a generic `call` for the rest.
- **Typed Block Kit** that round-trips: parsing a message and writing it back
  produces the same bytes, including the fields this version does not model.
  That property is checked against 2,548 real Slack payloads.
- **Request-signature verification**, with SHA-256 and HMAC written here because
  MoonBit's standard library has neither.

Bringing the network is your job: the library hands you a request and reads the
response, and a `Transport` trait sits between. `marianoguerra/slack-ext` has a
native one over `moonbitlang/async`; a browser host implements it over `fetch`
in about fifteen lines.

## Install

```sh
moon add marianoguerra/slack
```

Then import the packages you need, per package:

```
import {
  "marianoguerra/slack/api",
  "marianoguerra/slack/blocks",
  "marianoguerra/slack/client",
}
```

## Sending a message

```mbt nocheck
// nocheck: needs a transport and a real token.

///|
let client = @client.Client::new(transport, "xoxb-...")

///|
let response = client.chat_post_message(
  channel="C0123456789",
  text="Deploy finished", // what shows in notifications
  blocks=[
    @blocks.header("Deploy finished"),
    @blocks.section_text("*api* 1.4.2 -> 1.4.3"),
    @blocks.divider(),
    @blocks.actions([
      @blocks.button("Roll back", action_id="rollback", style="danger"),
    ]),
  ],
)
```

Always set `text` even when you send `blocks`: it is what appears in
notifications, in the channel sidebar and in clients that cannot render blocks.

## Blocks

Blocks are values. They compare, they round-trip, and they carry fields this
version has never heard of.

```mbt check
///|
test {
  let blocks = [
    @blocks.header("Report"),
    @blocks.section_text("*Revenue* is up"),
    @blocks.divider(),
  ]
  let json = @blocks.blocks_to_json(blocks)
  inspect(
    json.stringify(),
    content=(
      #|[{"type":"header","text":{"type":"plain_text","text":"Report"}},{"type":"section","text":{"type":"mrkdwn","text":"*Revenue* is up"}},{"type":"divider"}]
    ),
  )
  // ...and reading them back gives the same values.
  let parsed = @blocks.parse_blocks(json).unwrap()
  assert_eq(parsed, blocks)
}
```

Parsing never fails. A block type newer than this library becomes `Unknown`,
keeps its payload, and writes back unchanged -- so a bot does not stop working
because a coworker used a block that shipped last Tuesday.

```mbt check
///|
test {
  let payload : Json = [{ "type": "some_block_from_2027", "id": "x" }]
  let parsed = @blocks.parse_blocks(payload).unwrap()
  assert_eq(parsed[0].type_name(), "some_block_from_2027")
  // Nothing was dropped.
  assert_eq(@blocks.blocks_to_json(parsed), payload)
}
```

Pass `policy=Strict` when refusing is the point -- a linter, a test, a
validating endpoint:

```mbt check
///|
test {
  let payload : Json = [{ "type": "some_block_from_2027" }]
  try @blocks.parse_blocks(payload, policy=Strict) |> ignore catch {
    e =>
      assert_eq(
        e.to_string(),
        "Unsupported layout block type: some_block_from_2027",
      )
  } noraise {
    _ => fail("expected Strict to refuse an unmodelled block")
  }
}
```

## Verifying requests from Slack

Every request Slack sends your app is signed. Check it before you trust anything
in the body -- and check the **raw** body, byte for byte, before any framework
has parsed and re-serialised it.

```mbt check
///|
test {
  let verifier = @signature.Verifier::new("8f742231b10e8888abcd99yyyzzz85a5")
  let body = "token=xyzz0WbapA4vBCDEFasx0q6G&team_id=T1DC2JH3J&text=hi"
  let timestamp = "1531420618"
  let signature = verifier.sign(body, timestamp)

  // `now` is an argument rather than a clock read, so this package builds on
  // wasm and every expiry test is deterministic. In a receiver, pass the
  // current epoch second.
  verifier.verify_at_time(signature, body, timestamp, 1531420620L)

  // A tampered body is refused.
  try
    verifier.verify_at_time(signature, body + "!", timestamp, 1531420620L)
  catch {
    @signature.WrongSignature(..) => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a tampered body to be refused")
  }
}
```

The window is five minutes and two-sided, so a timestamp from the future is
refused too. Widen it per verifier with `max_age_seconds` if your clocks
disagree.

## Pagination

`conversations.list`, `users.list` and friends answer one page at a time.

```mbt nocheck
// nocheck: needs a transport.

///|
let channels = client.conversations_list_all(
  types=["public_channel"],
  max_pages=5, // a Tier 2 method on a big workspace will rate-limit you
)
```

The state machine underneath is pure, so the two ways to get pagination wrong
are both testable without a network: treating Slack's empty `next_cursor` as a
real one (an infinite loop over the last page), and forgetting the page size
after the first request.

```mbt check
///|
test {
  let paginator = @client.Paginator::new()
  inspect(@api.encode_form(paginator.next().unwrap()), content="limit=200")

  // Slack sends a cursor: there is another page.
  paginator.accept(
    @api.ApiResponse::of_json({
      "ok": true,
      "response_metadata": { "next_cursor": "dXNlcjpVMDYxTkZUVDI=" },
    }),
  )
  inspect(
    @api.encode_form(paginator.next().unwrap()),
    content="limit=200&cursor=dXNlcjpVMDYxTkZUVDI%3D",
  )

  // Slack sends an EMPTY cursor: that was the last page.
  paginator.accept(
    @api.ApiResponse::of_json({
      "ok": true,
      "response_metadata": { "next_cursor": "" },
    }),
  )
  assert_true(paginator.is_finished())
  assert_eq(paginator.next(), None)
}
```

## Rate limits

Every method's tier is in the table, so you can pace yourself rather than
collecting 429s.

```mbt check
///|
test {
  // chat.postMessage is roughly one message per second PER CHANNEL, which is
  // why the bucket key includes the channel.
  assert_eq(
    @methods.tier_of(@methods.chat_post_message),
    Some(SpecialChatPostMessage),
  )
  assert_eq(@methods.allowed_requests_per_minute("conversations.list"), 20)

  let throttler = @ratectl.Throttler::new()
  let now = 1_700_000_000_000L // epoch milliseconds; this package reads no clock
  for _ in 0..<20 {
    assert_eq(throttler.acquire(@methods.conversations_list, now), 0L)
  }
  // The 21st call in the same instant is told to wait.
  assert_true(throttler.acquire(@methods.conversations_list, now) > 0L)
}
```

Waiting is yours to do: sleeping needs an async runtime, and depending on one
would make this library native-only.

## Errors

Slack answers a refusal with HTTP 200 and `{"ok": false}`, so the status code
and `ok` are two different questions. The error codes and message text are
node-slack-sdk's, verbatim, so a team migrating keeps its log queries.

```mbt check
///|
test {
  let response = @api.ApiResponse::of_json({
    "ok": false,
    "error": "missing_scope",
    "needed": "chat:write",
    "provided": "identify",
  })
  let error = @api.SlackError::PlatformError(result=response)
  assert_eq(error.code(), "slack_webapi_platform_error")
  assert_eq(error.describe_error(), "An API error occurred: missing_scope")
  // The java-slack-sdk phrasing, which is the one that shows what was missing.
  assert_eq(
    error.describe_error_java(),
    "status: 200, error: missing_scope, needed: chat:write, provided: identify, warning: ",
  )
}
```

`response_metadata.messages` is where Slack explains itself on an
`invalid_blocks` -- and it arrives on successful responses too.

```mbt check
///|
test {
  let response = @api.ApiResponse::of_json({
    "ok": true,
    "response_metadata": {
      "messages": [
        "[ERROR] unsupported type: sections [json-pointer:/blocks/0/type]",
      ],
    },
  })
  let diagnostics = response.response_metadata.diagnostics()
  assert_eq(diagnostics[0].0, @api.Severity::Err)
  assert_eq(
    diagnostics[0].1,
    "unsupported type: sections [json-pointer:/blocks/0/type]",
  )
}
```

## Testing your app

There are two fakes, and which one you want depends on what the test is about.

`@testing.FakeTransport` answers a scripted list of responses and remembers
every request, so you can assert on what went out. Reach for it when the test is
about ONE call and the response is the fixture: a 500, a body that is not JSON,
a specific `ok: false`.

```mbt check
///|
test {
  let fake = @testing.FakeTransport::ok(["{\"ok\":true,\"ts\":\"1.2\"}"])
  let client = @client.Client::new(fake, "xoxb-test")
  // ... your code calls client.chat_post_message(...) ...
  ignore(client)
  assert_eq(fake.sent_count(), 0)
  assert_eq(fake.describe(), "fake transport")
}
```

`@mock.Workspace` is a Slack in memory: users, channels, DMs, threads,
reactions, pins, files and views, behind every method `Client` exposes. Reach
for it when the test is about a SEQUENCE, and the second call has to see what
the first one did -- which a scripted list cannot do, and which is most of what
an app actually does.

```mbt check
///|
test {
  let ws = @mock.Workspace::new()
  let alice = ws.add_user(name="alice", real_name="Alice Alvarez")
  let general = ws.add_channel(name="general", members=[alice])
  ws.install_app(token="xoxb-test", user=alice, scopes=[
    "chat:write", "channels:history",
  ])
  |> ignore

  // Post, and read it back. Two calls, one workspace.
  let posted = ws.invoke(
    "chat.postMessage",
    @mock.Form::of([("channel", general), ("text", "hello")]),
    token="xoxb-test",
  )
  assert_eq(posted.status, 200)
  assert_eq(ws.messages(general).length(), 1)

  // A scope it was not granted is refused the way Slack refuses it, with the
  // `needed` and `provided` that `describe_error_java` reads.
  let refused = ws.invoke("users.list", @mock.Form::new(), token="xoxb-test")
  let result = @api.ApiResponse::of_http(refused)
  assert_eq(result.error, Some("missing_scope"))
  assert_eq(result.needed, Some("users:read"))
}
```

The example above drives the workspace directly, because this README is
compiled and `Client` is async. In a real test you would hand `ws.transport()`
to `Client::new` and call the typed methods.

`@mock.Workspace::demo()` skips the seeding: four people and a bot, three
channels, a DM, an MPIM, a thread with replies and reactions, a pinned message,
a usergroup and a file, plus `@mock.demo_token`, which holds every scope.

Faults are injectable, which is how the paths a client only meets in production
become reachable in a test:

```mbt check
///|
test {
  let ws = @mock.Workspace::demo()
  ws.inject("chat.postMessage", RateLimited(30))
  ws.inject(
    "conversations.history",
    Http(status=503, body="upstream", headers=[]),
  )
  ws.inject("auth.test", Disconnect("connection reset"))
  assert_eq(ws.pending_faults(), 3)
}
```

Ids and timestamps are deterministic and the clock is an `Int64` you advance, so
two runs of the same test produce the same bytes. They are not Slack's real ids,
and nothing else about the mock is guesswork: what it answers is checked against
548 recorded Slack responses, and the integration scenario that runs against a
real workspace is run against it too. See "What keeps it honest" in the
repository README.

## Writing a transport

```mbt nocheck
// nocheck: sketch.

///|
pub impl @api.Transport for MyTransport with fn send(self, request) {
  // request.url, request.http_method, request.headers, request.body (Bytes)
  let response = my_http_post(request.url, request.headers, request.body)
  {
    status: response.status,
    // Header names MUST be lowercased: Slack's own casing is not stable.
    headers: lowercase_keys(response.headers),
    body: response.text,
  }
}

///|
pub impl @api.Transport for MyTransport with fn describe(self) {
  "my transport"
}
```

Use `request.content_length()` for `Content-Length`. It is the UTF-8 byte count,
not the string length -- MoonBit strings are UTF-16, and a body with one
accented character in it will otherwise declare fewer bytes than it sends.

## Packages

| Package | What is in it |
| --- | --- |
| `marianoguerra/slack/api` | `Transport`, request building, form encoding, the response envelope, the error taxonomy |
| `marianoguerra/slack/blocks` | Block Kit: layout blocks, elements, rich text, composition objects, builders |
| `marianoguerra/slack/client` | `Client`, the typed calls, the paginator |
| `marianoguerra/slack/crypto` | SHA-256, HMAC-SHA256, hex, constant-time compare |
| `marianoguerra/slack/signature` | Request-signature verification |
| `marianoguerra/slack/methods` | 326 method names and their rate-limit tiers |
| `marianoguerra/slack/ratectl` | Leaky-bucket throttling, with an injected clock |
| `marianoguerra/slack/testing` | `FakeTransport`: a scripted transport |
| `marianoguerra/slack/mock` | An in-memory Slack workspace, and a transport over it |

## Not included

- **File uploads.** `files.getUploadURLExternal` and
  `files.completeUploadExternal` are here, but the `PUT` of the bytes between
  them is an ordinary HTTP request to a URL Slack gives you, not a Web API call.
  Do it with your own HTTP client.
- **`admin.analytics.getFile`'s gzip response.** Ungzipping would need a
  dependency that is native-only. The method works; you get the raw body.
- **Typed event payloads.** `blocks` parses the Block Kit inside an event, but
  there are no typed `AppMentionEvent`-style structs.
- **Socket Mode and the RTM API.** Web API only.

## Provenance

The behaviour here is not invented. Almost every rule is pinned by a test ported
from one of Slack's own SDKs or a well-established community one, and the test
says which:

- [slackapi/java-slack-sdk](https://github.com/slackapi/java-slack-sdk) -- the
  signature golden vector, `RequestFormBuilderTest`'s form-encoding cases,
  `BlockKitTest`'s parse tests and its lenient/strict pairs,
  `MethodsTest#verifyTheCoverage`, the rate-limit tier table, and 565 recorded
  API responses.
- [slackapi/node-slack-sdk](https://github.com/slackapi/node-slack-sdk) -- the
  form-encoding golden bodies, the response-envelope rules, the error codes and
  message text, and the pagination suite.
- [abdolence/slack-morphism-rust](https://github.com/abdolence/slack-morphism-rust)
  -- the second signature vector, the Block Kit round-trip fixtures, and the
  throttling-counter arithmetic.
- [tumf/slack-rs](https://github.com/tumf/slack-rs) -- the `Retry-After`
  fallback.

Where they disagree, the divergence is a test with a comment saying which way it
went and why. There are three: booleans encode as `true`/`false` (node) rather
than `1`/`0` (java), with a knob; the signature timestamp window is two-sided
(morphism) rather than one-sided (java); and a strict parse refuses an unknown
text type in a `label`, which java's implementation lets through.

## Licence

Apache-2.0.
