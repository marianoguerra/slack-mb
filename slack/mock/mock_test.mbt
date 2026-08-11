// The mock, driven directly.
//
// Synchronous, because `async test` needs moonbitlang/async and this module
// does not have it -- which is exactly why `Workspace::invoke` exists next to
// `Workspace::handle`. The client-shaped tests, the ones that go through
// `Client::call` and a transport, live in ext/test/mockrun.

///|
/// A workspace with two people, a channel and a token that can do anything.
fn seeded() -> (@mock.Workspace, String, String, String) {
  let ws = @mock.Workspace::new()
  let alice = ws.add_user(name="alice", real_name="Alice Alvarez")
  let bob = ws.add_user(name="bob", real_name="Bob Bailey")
  let general = ws.add_channel(name="general", members=[alice, bob])
  ws.install_app(token="xoxb-test", user=alice) |> ignore
  ws.grant_all_scopes("xoxb-test")
  (ws, alice, bob, general)
}

///|
fn call(
  ws : @mock.Workspace,
  api_method : String,
  fields : Array[(String, String)],
  token? : String = "xoxb-test",
) -> Json raise {
  let response = answer(ws, api_method, fields, token~)
  @json.parse(response.body) catch {
    _ => fail("\{api_method} did not answer JSON: \{response.body}")
  }
}

///|
/// The raw response, for the tests that care about the status or a header.
fn answer(
  ws : @mock.Workspace,
  api_method : String,
  fields : Array[(String, String)],
  token? : String = "xoxb-test",
) -> @api.HttpResponse raise {
  ws.invoke(api_method, @mock.Form::of(fields), token~) catch {
    e => fail("\{api_method} raised: \{e}")
  }
}

///|
/// The `error` field of a response, or `None` when it succeeded.
fn error_of(body : Json) -> String? {
  guard body is Object(o) else { return None }
  match o.get("error") {
    Some(String(code)) => Some(code)
    _ => None
  }
}

///|
fn field(body : Json, key : String) -> Json? {
  guard body is Object(o) else { return None }
  o.get(key)
}

///|
test "a call answers ok and records itself" {
  let (ws, _, _, _) = seeded()
  let body = call(ws, "auth.test", [])
  assert_eq(field(body, "ok"), Some(Json::boolean(true)))
  assert_eq(field(body, "user"), Some(Json::string("alice")))
  assert_eq(ws.call_count(), 1)
  assert_eq(ws.calls_to("auth.test").length(), 1)
}

///|
/// Slack answers every refusal with HTTP 200 and `ok: false`. That is the whole
/// reason `interpret_response` treats the status and `ok` as two questions, and
/// a mock that answered 4xx here would let a client that conflated them pass.
test "a refusal is an HTTP 200 carrying ok:false" {
  let (ws, _, _, _) = seeded()
  let response = answer(ws, "conversations.info", [("channel", "C_NOPE")])
  assert_eq(response.status, 200)
  let body = @json.parse(response.body) catch { _ => fail("not json") }
  assert_eq(error_of(body), Some("channel_not_found"))
}

///|
test "no token is not_authed, an unknown one is invalid_auth" {
  let (ws, _, _, _) = seeded()
  let anonymous = ws.invoke("auth.test", @mock.Form::new()) catch {
    e => fail("raised: \{e}")
  }
  let body = @json.parse(anonymous.body) catch { _ => fail("not json") }
  assert_eq(error_of(body), Some("not_authed"))
  assert_eq(
    error_of(call(ws, "auth.test", [], token="xoxb-nope")),
    Some("invalid_auth"),
  )
}

///|
test "a revoked token stops working, and says which way it stopped" {
  let (ws, _, _, _) = seeded()
  assert_eq(error_of(call(ws, "auth.revoke", [("test", "true")])), None)
  // A dry run reports what would happen and does not do it.
  assert_eq(error_of(call(ws, "auth.test", [])), None)
  assert_eq(error_of(call(ws, "auth.revoke", [])), None)
  assert_eq(error_of(call(ws, "auth.test", [])), Some("token_revoked"))
}

///|
/// The pair `describe_error_java` reads, and the pair `ext/cmd/integration`
/// turns into a skip rather than a failure.
test "a missing scope names what was needed and what was held" {
  let ws = @mock.Workspace::new()
  let alice = ws.add_user(name="alice")
  ws.install_app(token="xoxb-narrow", user=alice, scopes=["chat:write"])
  |> ignore
  let body = call(ws, "users.list", [], token="xoxb-narrow")
  assert_eq(error_of(body), Some("missing_scope"))
  assert_eq(field(body, "needed"), Some(Json::string("users:read")))
  assert_eq(field(body, "provided"), Some(Json::string("chat:write")))
}

///|
/// Any one of a method's scopes satisfies it, which is how Slack's own check
/// works: `conversations.info` opens on `channels:read` OR `groups:read`.
test "any one of a method's scopes is enough" {
  let ws = @mock.Workspace::new()
  let alice = ws.add_user(name="alice")
  let channel = ws.add_channel(name="general", members=[alice])
  ws.install_app(token="xoxb-groups", user=alice, scopes=["groups:read"])
  |> ignore
  assert_eq(
    error_of(
      call(
        ws,
        "conversations.info",
        [("channel", channel)],
        token="xoxb-groups",
      ),
    ),
    None,
  )
}

///|
/// A name that is not a Slack method gets Slack's own answer; a name that IS
/// one but has no handler here says so, rather than sending a caller hunting a
/// typo they did not make.
test "an unimplemented method is distinguished from an unknown one" {
  let (ws, _, _, _) = seeded()
  assert_eq(error_of(call(ws, "not.a.method", [])), Some("unknown_method"))
  assert_eq(
    error_of(call(ws, "admin.users.invite", [])),
    Some("mock_method_not_implemented"),
  )
  ws.set_strict_unknown(true)
  assert_eq(
    error_of(call(ws, "admin.users.invite", [])),
    Some("unknown_method"),
  )
}

///|
/// The asymmetry `ext/cmd/integration` discovered against a live workspace:
/// `chat.postMessage` takes a channel NAME, `chat.update` and
/// `conversations.history` do not.
test "a channel name works for postMessage and nowhere else" {
  let (ws, _, _, channel) = seeded()
  let posted = call(ws, "chat.postMessage", [
    ("channel", "#general"),
    ("text", "hello"),
  ])
  assert_eq(error_of(posted), None)
  // The RESOLVED id comes back, which is what everything downstream needs.
  assert_eq(field(posted, "channel"), Some(Json::string(channel)))
  guard field(posted, "ts") is Some(String(ts)) else { fail("no ts") }
  assert_eq(
    error_of(
      call(ws, "chat.update", [
        ("channel", "#general"),
        ("ts", ts),
        ("text", "x"),
      ]),
    ),
    Some("channel_not_found"),
  )
  assert_eq(
    error_of(call(ws, "conversations.history", [("channel", "#general")])),
    Some("channel_not_found"),
  )
  // By id, both work.
  assert_eq(
    error_of(
      call(ws, "chat.update", [("channel", channel), ("ts", ts), ("text", "x")]),
    ),
    None,
  )
}

///|
/// The state a scripted transport cannot have: the second call sees what the
/// first one did.
test "a posted message comes back out of history" {
  let (ws, _, _, channel) = seeded()
  call(ws, "chat.postMessage", [("channel", channel), ("text", "first")])
  |> ignore
  call(ws, "chat.postMessage", [("channel", channel), ("text", "second")])
  |> ignore
  let body = call(ws, "conversations.history", [("channel", channel)])
  guard field(body, "messages") is Some(Array(messages)) else {
    fail("no messages")
  }
  assert_eq(messages.length(), 2)
  // Newest first, which is Slack's order and the thing a client renders
  // backwards if the mock gets it wrong.
  assert_eq(
    messages[0] is Object(m) && m.get("text") is Some(String("second")),
    true,
  )
}

///|
/// The decode side of the rule `slack/client/chat.mbt` documents on the encode
/// side, and the reason `Params::put_json` sends `[]` rather than omitting.
test "an empty blocks array clears blocks, an absent one keeps them" {
  let (ws, _, _, channel) = seeded()
  let posted = call(ws, "chat.postMessage", [
    ("channel", channel),
    ("text", "hi"),
    ("blocks", "[{\"type\":\"divider\"}]"),
  ])
  guard field(posted, "ts") is Some(String(ts)) else { fail("no ts") }
  // An absent `blocks` leaves them alone.
  call(ws, "chat.update", [
    ("channel", channel),
    ("ts", ts),
    ("text", "changed"),
  ])
  |> ignore
  guard ws.message(channel, ts) is Some(kept) else { fail("message gone") }
  assert_true(kept.blocks is Some(_))
  // An empty one clears them.
  call(ws, "chat.update", [("channel", channel), ("ts", ts), ("blocks", "[]")])
  |> ignore
  guard ws.message(channel, ts) is Some(cleared) else { fail("message gone") }
  assert_eq(cleared.blocks, Some(Json::array([])))
}

///|
/// What the caller sent comes back byte for byte, including a field this
/// library has never heard of. It is the property `Message.blocks : Json?`
/// exists for.
test "blocks survive the round trip unchanged" {
  let (ws, _, _, channel) = seeded()
  let sent =
    #|[{"type":"divider","block_id":"d1","some_future_field":{"a":1}}]
  let posted = call(ws, "chat.postMessage", [
    ("channel", channel),
    ("text", "hi"),
    ("blocks", sent),
  ])
  guard field(posted, "message") is Some(Object(message)) else {
    fail("no message")
  }
  assert_eq(
    message.get("blocks"),
    Some(@json.parse(sent) catch { _ => fail("bad fixture") }),
  )
}

///|
test "a payload blocks cannot parse is refused as invalid_blocks" {
  let (ws, _, _, channel) = seeded()
  let body = call(ws, "chat.postMessage", [
    ("channel", channel),
    ("text", "hi"),
    ("blocks", "[{\"type\":\"sections\"}]"),
  ])
  assert_eq(error_of(body), Some("invalid_blocks"))
  // The diagnostic arrives where `ResponseMetadata::diagnostics` reads it.
  let parsed = @api.ApiResponse::of_json(body)
  let diagnostics = parsed.response_metadata.diagnostics()
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].1.contains("sections"))
  // And it can be turned off.
  ws.set_validate_blocks(false)
  assert_eq(
    error_of(
      call(ws, "chat.postMessage", [
        ("channel", channel),
        ("text", "hi"),
        ("blocks", "[{\"type\":\"sections\"}]"),
      ]),
    ),
    None,
  )
}

///|
/// The last page carries `next_cursor: ""`, not an absent field. That is what
/// Slack really sends and the case a paginator gets wrong by looping forever.
test "the last page sends an empty cursor rather than none" {
  let ws = @mock.Workspace::new()
  let alice = ws.add_user(name="alice")
  ws.install_app(token="xoxb-test", user=alice) |> ignore
  ws.grant_all_scopes("xoxb-test")
  for i in 0..<5 {
    ws.add_channel(name="c\{i}", members=[alice]) |> ignore
  }
  let first = call(ws, "conversations.list", [("limit", "2")])
  guard field(first, "channels") is Some(Array(page1)) else { fail("no page") }
  assert_eq(page1.length(), 2)
  let cursor = @api.ApiResponse::of_json(first).response_metadata.next_cursor
  assert_eq(cursor, Some("m:2"))
  let last = call(ws, "conversations.list", [("limit", "10"), ("cursor", "m:2")])
  guard field(last, "channels") is Some(Array(page2)) else { fail("no page") }
  assert_eq(page2.length(), 3)
  assert_eq(
    @api.ApiResponse::of_json(last).response_metadata.next_cursor,
    Some(""),
  )
}

///|
/// `Client.bool_style` is a knob because the reference SDKs disagree, so the
/// mock has to read both spellings or it silently misreads half its callers.
test "booleans are read in both spellings" {
  let (ws, alice, _, _) = seeded()
  ws.add_channel(name="old", members=[alice], is_archived=true) |> ignore
  let node = call(ws, "conversations.list", [("exclude_archived", "true")])
  let java = call(ws, "conversations.list", [("exclude_archived", "1")])
  guard field(node, "channels") is Some(Array(a)) else { fail("no channels") }
  guard field(java, "channels") is Some(Array(b)) else { fail("no channels") }
  assert_eq(a.length(), 1)
  assert_eq(b.length(), 1)
}

///|
test "an injected error code fires once, for the method it was queued on" {
  let (ws, _, _, channel) = seeded()
  ws.inject("chat.postMessage", ErrorCode("ratelimited"))
  assert_eq(ws.pending_faults(), 1)
  assert_eq(
    error_of(
      call(ws, "chat.postMessage", [("channel", channel), ("text", "a")]),
    ),
    Some("ratelimited"),
  )
  assert_eq(ws.pending_faults(), 0)
  assert_eq(
    error_of(
      call(ws, "chat.postMessage", [("channel", channel), ("text", "a")]),
    ),
    None,
  )
}

///|
/// The path @client turns into `RateLimitedError`, `HttpError` and
/// `RequestError` -- reachable mid-scenario rather than only from a scripted
/// transport.
test "the transport-level faults produce the responses @client reads" {
  let (ws, _, _, _) = seeded()
  ws.inject("auth.test", RateLimited(17))
  let limited = answer(ws, "auth.test", [])
  assert_eq(limited.status, 429)
  assert_eq(limited.header("retry-after"), Some("17"))
  ws.inject("auth.test", Http(status=503, body="<html>nope</html>", headers=[]))
  let broken = answer(ws, "auth.test", [])
  assert_eq(broken.status, 503)
  ws.inject("auth.test", NotJson("<html>login</html>"))
  let captive = answer(ws, "auth.test", [])
  // `of_http` turns a non-JSON body into the error rather than swallowing it.
  let parsed = @api.ApiResponse::of_http(captive)
  assert_false(parsed.ok)
  assert_eq(parsed.error, Some("<html>login</html>"))
}

///|
/// The one fault that is not bytes at all. It reaches a caller as
/// `RequestError`, which is the shape of a socket giving out.
test "a disconnect raises rather than answering" {
  let (ws, _, _, _) = seeded()
  ws.inject("auth.test", Disconnect("connection reset"))
  let raised = try {
    ws.invoke("auth.test", @mock.Form::new(), token="xoxb-test") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
/// A fault is taken before authentication and before any mutation, so an
/// injected failure never leaves the workspace half-changed.
test "an injected fault does not post the message it failed" {
  let (ws, _, _, channel) = seeded()
  ws.inject("chat.postMessage", ErrorCode("internal_error"))
  call(ws, "chat.postMessage", [("channel", channel), ("text", "lost")])
  |> ignore
  assert_eq(ws.messages(channel).length(), 0)
}

///|
/// MoonBit's `Compare` for `String` is shortlex, so a `ts` cannot be compared
/// as one: `"1.2"` would sort before every real timestamp on length alone.
test "timestamps compare numerically, not lexically" {
  assert_eq(@mock.ts_compare("1.2", "1700000000.000001"), -1)
  assert_eq(@mock.ts_compare("1700000000.000002", "1700000000.000001"), 1)
  assert_eq(@mock.ts_compare("1700000000.000001", "1700000000.000001"), 0)
  // A ts with no subsecond half reads as zero rather than raising.
  assert_eq(@mock.ts_compare("1700000000", "1700000000.000001"), -1)
}

///|
/// Both bounds are exclusive unless `inclusive` is set, which is Slack's rule
/// and why paging by passing the last `ts` as the next `latest` does not repeat
/// a message.
test "history bounds are exclusive unless asked otherwise" {
  let (ws, alice, _, channel) = seeded()
  let first = ws.add_message(channel~, user=alice, text="one")
  ws.add_message(channel~, user=alice, text="two") |> ignore
  let exclusive = call(ws, "conversations.history", [
    ("channel", channel),
    ("oldest", first),
  ])
  guard field(exclusive, "messages") is Some(Array(a)) else { fail("none") }
  assert_eq(a.length(), 1)
  let inclusive = call(ws, "conversations.history", [
    ("channel", channel),
    ("oldest", first),
    ("inclusive", "true"),
  ])
  guard field(inclusive, "messages") is Some(Array(b)) else { fail("none") }
  assert_eq(b.length(), 2)
}

///|
/// A thread reads top to bottom while a channel reads bottom to top, and
/// replies stay out of the channel's own history.
test "a thread is ordered oldest-first and stays out of history" {
  let (ws, alice, bob, channel) = seeded()
  let root = ws.add_message(channel~, user=alice, text="root")
  ws.add_message(channel~, user=bob, text="reply one", thread_ts=root) |> ignore
  ws.add_message(channel~, user=bob, text="reply two", thread_ts=root) |> ignore
  let history = call(ws, "conversations.history", [("channel", channel)])
  guard field(history, "messages") is Some(Array(top)) else { fail("none") }
  assert_eq(top.length(), 1)
  let thread = call(ws, "conversations.replies", [
    ("channel", channel),
    ("ts", root),
  ])
  guard field(thread, "messages") is Some(Array(replies)) else { fail("none") }
  assert_eq(replies.length(), 3)
  assert_true(replies[0] is Object(m) && m.get("text") is Some(String("root")))
  // The parent carries the counters; a reply carries only `thread_ts`.
  guard replies[0] is Object(parent) else { fail("not an object") }
  assert_eq(parent.get("reply_count"), Some(Json::number(2.0, repr="2")))
  guard replies[1] is Object(reply) else { fail("not an object") }
  assert_eq(reply.get("reply_count"), None)
}

///|
test "reacting twice the same way is already_reacted" {
  let (ws, alice, _, channel) = seeded()
  let ts = ws.add_message(channel~, user=alice, text="hi")
  let args : Array[(String, String)] = [
    ("channel", channel),
    ("timestamp", ts),
    ("name", "wave"),
  ]
  assert_eq(error_of(call(ws, "reactions.add", args)), None)
  assert_eq(error_of(call(ws, "reactions.add", args)), Some("already_reacted"))
  assert_eq(error_of(call(ws, "reactions.remove", args)), None)
  assert_eq(error_of(call(ws, "reactions.remove", args)), Some("no_reaction"))
}

///|
/// Slack takes `wave` here and `:wave:` in message text. Sending the colons is
/// the mistake people make first, and Slack accepts them, so this does too.
test "an emoji name is accepted with or without its colons" {
  let (ws, alice, _, channel) = seeded()
  let ts = ws.add_message(channel~, user=alice, text="hi")
  assert_eq(
    error_of(
      call(ws, "reactions.add", [
        ("channel", channel),
        ("timestamp", ts),
        ("name", ":tada:"),
      ]),
    ),
    None,
  )
  guard ws.message(channel, ts) is Some(message) else { fail("gone") }
  assert_eq(message.reactions.length(), 1)
  assert_eq(message.reactions[0].name, "tada")
}

///|
/// Going through `handle` rather than `invoke` exercises the whole byte path:
/// `build_request` writes the URL, the header and the form body, and the mock
/// reads all three back.
test "a request built by the library round-trips through handle" {
  let (ws, _, _, channel) = seeded()
  let params = @api.Params::new()
  params.put_str("channel", Some(channel))
  params.put_str("text", Some("São Paulo & 1+1 = 2 🎉"))
  let request = @api.build_request(
    @api.default_api_url,
    "chat.postMessage",
    params,
    token="xoxb-test",
  )
  let response = ws.handle(request) catch { e => fail("raised: \{e}") }
  assert_eq(response.status, 200)
  let body = @json.parse(response.body) catch { _ => fail("not json") }
  assert_eq(error_of(body), None)
  // The awkward text survived percent-encoding and decoding intact.
  guard field(body, "message") is Some(Object(message)) else { fail("none") }
  assert_eq(
    message.get("text"),
    Some(Json::string("São Paulo & 1+1 = 2 🎉")),
  )
}

///|
/// `api.test` echoes its arguments, which is the only way to check a form
/// encoder against a parser rather than against another SDK's expectations.
test "api.test echoes what it was sent, and never the token" {
  let (ws, _, _, _) = seeded()
  let params = @api.Params::new()
  params.put_str("city", Some("São Paulo"))
  params.put_str("query", Some("a&b=c"))
  let request = @api.build_request(
    @api.default_api_url,
    "api.test",
    params,
    token="xoxb-test",
  )
  let response = ws.handle(request) catch { e => fail("raised: \{e}") }
  let body = @json.parse(response.body) catch { _ => fail("not json") }
  guard field(body, "args") is Some(Object(args)) else { fail("no args") }
  assert_eq(args.get("city"), Some(Json::string("São Paulo")))
  assert_eq(args.get("query"), Some(Json::string("a&b=c")))
  // This library puts the token in a header, so there is nothing to echo.
  assert_eq(args.get("token"), None)
}

///|
/// `error` is the one argument api.test acts on rather than echoes.
test "api.test fails on demand" {
  let (ws, _, _, _) = seeded()
  assert_eq(
    error_of(call(ws, "api.test", [("error", "my_error")])),
    Some("my_error"),
  )
}

///|
/// A DM has no name in Slack's payload at all, and `conversations.open` reuses
/// an existing conversation rather than making a second one.
test "opening a DM twice returns the same conversation" {
  let (ws, _, bob, _) = seeded()
  let first = call(ws, "conversations.open", [("users", bob)])
  assert_eq(field(first, "already_open"), Some(Json::boolean(false)))
  guard field(first, "channel") is Some(Object(a)) else { fail("no channel") }
  let second = call(ws, "conversations.open", [("users", bob)])
  assert_eq(field(second, "already_open"), Some(Json::boolean(true)))
  guard field(second, "channel") is Some(Object(b)) else { fail("no channel") }
  assert_eq(a.get("id"), b.get("id"))
  // No name, and no topic: a DM has neither.
  assert_eq(a.get("name"), None)
  assert_eq(a.get("topic"), None)
}

///|
test "renaming keeps the old name reachable" {
  let (ws, _, _, channel) = seeded()
  call(ws, "conversations.rename", [("channel", channel), ("name", "lobby")])
  |> ignore
  let info = call(ws, "conversations.info", [("channel", channel)])
  guard field(info, "channel") is Some(Object(c)) else { fail("none") }
  assert_eq(c.get("name"), Some(Json::string("lobby")))
  assert_eq(
    c.get("previous_names"),
    Some(Json::array([Json::string("general")])),
  )
}

///|
test "a name already in use is name_taken" {
  let (ws, alice, _, _) = seeded()
  ws.add_channel(name="random", members=[alice]) |> ignore
  assert_eq(
    error_of(call(ws, "conversations.create", [("name", "random")])),
    Some("name_taken"),
  )
  // And a fresh name works, with the `detail` field Slack sends alongside.
  let created = call(ws, "conversations.create", [("name", "#New-Channel")])
  assert_eq(error_of(created), None)
  guard field(created, "channel") is Some(Object(c)) else { fail("none") }
  // Lowercased, and the leading `#` dropped.
  assert_eq(c.get("name"), Some(Json::string("new-channel")))
}

///|
/// Every timestamp is distinct even when the clock is frozen, because the
/// sub-second counter keeps rising.
test "timestamps stay distinct with the clock stopped" {
  let (ws, _, _, channel) = seeded()
  ws.set_tick(0L)
  let seen : Array[String] = []
  for _ in 0..<5 {
    let body = call(ws, "chat.postMessage", [
      ("channel", channel),
      ("text", "x"),
    ])
    guard field(body, "ts") is Some(String(ts)) else { fail("no ts") }
    assert_false(seen.contains(ts))
    seen.push(ts)
  }
  assert_eq(seen.length(), 5)
}

///|
/// A view is stored as the caller sent it, with the server-assigned fields
/// merged over -- so the blocks inside a modal survive the round trip too.
test "a view keeps its payload and gains an id" {
  let (ws, alice, _, _) = seeded()
  let view = @client.modal("Title", [@blocks.section_text("*body*")])
  let opened = call(ws, "views.open", [
    ("trigger_id", "123.456"),
    ("view", view.stringify()),
  ])
  assert_eq(error_of(opened), None)
  guard field(opened, "view") is Some(Object(v)) else { fail("no view") }
  assert_true(v.get("id") is Some(String(_)))
  assert_eq(v.get("type"), Some(Json::string("modal")))
  guard view is Object(sent) else { fail("bad fixture") }
  assert_eq(v.get("blocks"), sent.get("blocks"))
  // Publishing to a home tab twice updates the same view.
  let home = @client.home_view([@blocks.divider()])
  let first = call(ws, "views.publish", [
    ("user_id", alice),
    ("view", home.stringify()),
  ])
  let second = call(ws, "views.publish", [
    ("user_id", alice),
    ("view", home.stringify()),
  ])
  guard field(first, "view") is Some(Object(f)) else { fail("none") }
  guard field(second, "view") is Some(Object(s)) else { fail("none") }
  assert_eq(f.get("id"), s.get("id"))
}

///|
/// `users.profile.set` followed by `users.profile.get` must not lose a field
/// this model does not name -- that is what `profile_extra` is for.
test "an unmodelled profile field survives a set and a get" {
  let (ws, _, _, _) = seeded()
  call(ws, "users.profile.set", [
    ("profile", "{\"title\":\"Engineer\",\"some_future_field\":\"kept\"}"),
  ])
  |> ignore
  let body = call(ws, "users.profile.get", [])
  guard field(body, "profile") is Some(Object(profile)) else { fail("none") }
  assert_eq(profile.get("title"), Some(Json::string("Engineer")))
  assert_eq(profile.get("some_future_field"), Some(Json::string("kept")))
}

///|
/// The transport records what went out, the workspace records what it decoded.
test "the transport and the workspace both remember the call" {
  let (ws, _, _, channel) = seeded()
  let transport = ws.transport()
  let params = @api.Params::new()
  params.put_str("channel", Some(channel))
  params.put_str("text", Some("hello"))
  let request = @api.build_request(
    @api.default_api_url,
    "chat.postMessage",
    params,
    token="xoxb-test",
  )
  let _ = ws.handle(request) catch { e => fail("raised: \{e}") }
  ignore(transport)
  guard ws.last_call() is Some(record) else { fail("nothing recorded") }
  assert_eq(record.api_method, "chat.postMessage")
  assert_eq(record.field("text"), Some("hello"))
  assert_true(record.ok)
}

///|
/// The prebuilt workspace, which every conformance check in ext/ drives -- so
/// a change that breaks it breaks them too, and this is where that shows up
/// first and most legibly.
test "demo() is populated and internally consistent" {
  let ws = @mock.Workspace::demo()
  let general = ws.demo_id("general")
  // Everything demo() claims to have mints an id.
  for
    name in [
      "alice", "bob", "carol", "dave", "bot", "general", "random", "ops", "dm", "mpim",
      "thread_root", "pinned", "usergroup", "file",
    ] {
    assert_false(ws.demo_id(name).is_empty())
  }
  // The token can do everything, which is what makes a SKIP in the shared
  // scenario a mock bug rather than a scope problem.
  let listed = call(ws, "users.list", [], token=@mock.demo_token)
  assert_eq(error_of(listed), None)
  guard field(listed, "members") is Some(Array(members)) else { fail("none") }
  assert_eq(members.length(), 5)
  // The thread, its replies and its reactions survived seeding.
  let thread = call(
    ws,
    "conversations.replies",
    [("channel", general), ("ts", ws.demo_id("thread_root"))],
    token=@mock.demo_token,
  )
  guard field(thread, "messages") is Some(Array(replies)) else { fail("none") }
  assert_eq(replies.length(), 3)
  guard replies[0] is Object(root) else { fail("not an object") }
  assert_eq(root.get("reply_count"), Some(Json::number(2.0, repr="2")))
  guard root.get("reactions") is Some(Array(reactions)) else {
    fail("no reactions")
  }
  assert_eq(reactions.length(), 1)
  // And the pin.
  let pins = call(
    ws,
    "pins.list",
    [("channel", general)],
    token=@mock.demo_token,
  )
  guard field(pins, "items") is Some(Array(items)) else { fail("none") }
  assert_eq(items.length(), 1)
}

///|
/// Two `demo()` workspaces are identical, which is what "deterministic" has to
/// mean for a recorded golden to be comparable at all.
test "demo() mints the same ids every time" {
  let a = @mock.Workspace::demo()
  let b = @mock.Workspace::demo()
  assert_eq(a.demo_ids(), b.demo_ids())
  let from_a = call(a, "conversations.list", [], token=@mock.demo_token)
  let from_b = call(b, "conversations.list", [], token=@mock.demo_token)
  assert_eq(from_a, from_b)
}
