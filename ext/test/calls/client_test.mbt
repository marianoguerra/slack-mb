// Client::call and Client::paginate, against a scripted transport.
//
// These are the tests that need `async`, which is why they are in `ext` rather
// than beside the code -- see moon.pkg. Everything they assert is about the
// glue: what goes out on the wire, what comes back, and how many requests it
// took.

///|
/// Named `new_client` rather than `client`, because a function called `client`
/// would shadow the `@client` package alias for the whole file.
fn new_client(fake : @testing.FakeTransport) -> @client.Client {
  @client.Client::new(fake, "xoxb-test-token")
}

///|
async test "a call sends the method, the token and the parameters" {
  let fake = @testing.FakeTransport::ok(["{\"ok\":true,\"ts\":\"1.2\"}"])
  let c = new_client(fake)
  let response = c.chat_post_message(channel="C123", text="hello")
  assert_true(response.ok)
  assert_eq(response.get_str("ts"), Some("1.2"))
  assert_eq(fake.sent_count(), 1)
  assert_eq(fake.method_of(0), "chat.postMessage")
  assert_eq(fake.body_of(0), "channel=C123&text=hello")
  assert_eq(
    fake.request(0).headers.get("authorization"),
    Some("Bearer xoxb-test-token"),
  )
  // The token is a header, never a form field.
  assert_false(fake.body_of(0).contains("xoxb"))
}

///|
/// Typed blocks reach the wire as a JSON string inside a form field -- not as a
/// JSON request body. This is the single most common thing people get wrong
/// when they write a Slack client by hand.
async test "blocks travel as JSON inside a form field" {
  let fake = @testing.FakeTransport::ok(["{\"ok\":true}"])
  let c = new_client(fake)
  c.chat_post_message(channel="C1", text="fallback", blocks=[
    @blocks.section_text("*hi*"),
    @blocks.divider(),
  ])
  |> ignore
  assert_eq(
    fake.request(0).headers.get("content-type"),
    Some("application/x-www-form-urlencoded"),
  )
  let body = fake.body_of(0)
  assert_true(body.has_prefix("channel=C1&text=fallback&blocks="))
  assert_true(body.contains("%22type%22%3A%22section%22"))
  assert_true(body.contains("%22type%22%3A%22divider%22"))
}

///|
/// An empty block list is sent as `[]` rather than omitted, which is how a
/// caller REMOVES the blocks from an existing message.
async test "an empty block list clears blocks rather than leaving them" {
  let fake = @testing.FakeTransport::ok(["{\"ok\":true}"])
  let c = new_client(fake)
  c.chat_update(channel="C1", ts="1.2", text="now plain", blocks=[]) |> ignore
  assert_eq(fake.body_of(0), "channel=C1&ts=1.2&text=now%20plain&blocks=%5B%5D")
}

///|
/// `{"ok": false}` arrives with HTTP 200 and must still be an error, carrying
/// the whole response -- `needed` and `provided` are the actual content of a
/// `missing_scope`.
async test "an ok:false response raises with its diagnostics intact" {
  let fake = @testing.FakeTransport::ok([
    (
      #|{"ok":false,"error":"missing_scope","needed":"chat:write","provided":"identify"}
    ),
  ])
  let c = new_client(fake)
  try c.chat_post_message(channel="C1", text="hi") |> ignore catch {
    @api.PlatformError(result~) => {
      assert_eq(result.error, Some("missing_scope"))
      assert_eq(result.needed, Some("chat:write"))
      assert_eq(result.provided, Some("identify"))
    }
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected ok:false to raise")
  }
}

///|
async test "a 429 raises a rate-limit error carrying the delay" {
  let fake = @testing.FakeTransport::new([@testing.rate_limited(17)])
  let c = new_client(fake)
  try c.auth_test() |> ignore catch {
    @api.RateLimitedError(retry_after~) => assert_eq(retry_after, 17)
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a 429 to raise")
  }
}

///|
async test "a 5xx raises an HTTP error, not a platform error" {
  let fake = @testing.FakeTransport::new([
    @testing.response(503, "<html>upstream</html>"),
  ])
  let c = new_client(fake)
  try c.auth_test() |> ignore catch {
    @api.HttpError(status~, body~, ..) => {
      assert_eq(status, 503)
      assert_eq(body, "<html>upstream</html>")
    }
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a 503 to raise")
  }
}

///|
/// A body that is not JSON becomes the error text rather than being swallowed
/// -- a captive portal's login page is far more useful surfaced than hidden.
async test "a non-JSON 200 body surfaces as the error" {
  let fake = @testing.FakeTransport::ok(["<html>login required</html>"])
  let c = new_client(fake)
  try c.auth_test() |> ignore catch {
    @api.PlatformError(result~) =>
      assert_eq(result.error, Some("<html>login required</html>"))
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a non-JSON body to raise")
  }
}

///|
/// An org-wide app has to say which workspace it means, and repeating
/// `team_id` at 300 call sites is how it gets forgotten at one of them.
async test "a client-level team_id is sent on every call" {
  let fake = @testing.FakeTransport::ok(["{\"ok\":true}", "{\"ok\":true}"])
  let c = @client.Client::new(fake, "xoxb-t", team_id="T999")
  c.auth_test() |> ignore
  assert_eq(fake.body_of(0), "team_id=T999")
  // ...and a call that names its own team keeps it.
  let p = @api.Params::new()
  p.put_str("team_id", Some("T111"))
  c.call(@methods.auth_test, p) |> ignore
  assert_eq(fake.body_of(1), "team_id=T111")
}

///|
/// The paginator, end to end: three pages, the last one ending with the empty
/// cursor Slack actually sends.
async test "paginate walks every page and stops on the empty cursor" {
  let fake = @testing.FakeTransport::new([
    @testing.page("channels", [{ "id": "C1" }], next_cursor="c1"),
    @testing.page("channels", [{ "id": "C2" }], next_cursor="c2"),
    @testing.page("channels", [{ "id": "C3" }], next_cursor=""),
  ])
  let c = new_client(fake)
  let items = c.conversations_list_all()
  assert_eq(items.length(), 3)
  assert_eq(items[2], { "id": "C3" })
  assert_eq(fake.sent_count(), 3)
  assert_eq(fake.body_of(0), "limit=200")
  assert_eq(fake.body_of(1), "limit=200&cursor=c1")
  assert_eq(fake.body_of(2), "limit=200&cursor=c2")
}

///|
/// An absent cursor ends the walk just as an empty one does, and one request is
/// all it takes.
async test "paginate stops when there is no cursor at all" {
  let fake = @testing.FakeTransport::new([
    @testing.page("channels", [{ "id": "C1" }]),
  ])
  let c = new_client(fake)
  assert_eq(c.conversations_list_all().length(), 1)
  assert_eq(fake.sent_count(), 1)
}

///|
/// `max_pages` is the guard for a Tier 2 method on a workspace with tens of
/// thousands of channels: fetch a sample without walking the whole thing.
async test "max_pages stops the walk early" {
  let fake = @testing.FakeTransport::new([
    @testing.page("channels", [{ "id": "C1" }], next_cursor="c1"),
    @testing.page("channels", [{ "id": "C2" }], next_cursor="c2"),
  ])
  let c = new_client(fake)
  let items = c.conversations_list_all(max_pages=2)
  assert_eq(items.length(), 2)
  // Two requests, not three: the third was never sent even though Slack
  // offered a cursor.
  assert_eq(fake.sent_count(), 2)
}

///|
/// The callback form: return `false` to stop. node's `shouldStop`, inverted so
/// the common case reads as "keep going".
async test "the page callback can stop the walk" {
  let fake = @testing.FakeTransport::new([
    @testing.page("members", [{ "id": "U1" }], next_cursor="c1"),
    @testing.page("members", [{ "id": "U2" }], next_cursor="c2"),
    @testing.page("members", [{ "id": "U3" }], next_cursor="c3"),
  ])
  let c = new_client(fake)
  let seen = []
  let pages = c.paginate(@methods.users_list, @api.Params::new(), response => {
    for item in @client.page_items(response, "members") {
      seen.push(item)
    }
    seen.length() < 2
  })
  assert_eq(pages, 2)
  assert_eq(seen.length(), 2)
  assert_eq(fake.sent_count(), 2)
}

///|
/// A caller's base parameters ride along on every page, and the paginator's
/// own win where they collide.
async test "base parameters survive pagination" {
  let fake = @testing.FakeTransport::new([
    @testing.page("channels", [], next_cursor="c1"),
    @testing.page("channels", []),
  ])
  let c = new_client(fake)
  c.conversations_list_all(
    types=["public_channel", "private_channel"],
    exclude_archived=true,
    page_size=50,
  )
  |> ignore
  assert_eq(
    fake.body_of(0),
    "types=public_channel%2Cprivate_channel&exclude_archived=true&limit=50",
  )
  assert_eq(
    fake.body_of(1),
    "types=public_channel%2Cprivate_channel&exclude_archived=true&limit=50&cursor=c1",
  )
}

///|
/// One builder from each family, checked for the method name it calls and the
/// body it sends. The families are mechanical once one of each shape exists,
/// so this is the shape check rather than sixty near-identical tests.
async test "one builder from each family" {
  let fake = @testing.FakeTransport::ok([
    "{\"ok\":true}", "{\"ok\":true}", "{\"ok\":true}", "{\"ok\":true}", "{\"ok\":true}",
    "{\"ok\":true}", "{\"ok\":true}", "{\"ok\":true}",
  ])
  let c = new_client(fake)
  c.auth_test() |> ignore
  c.conversations_invite(channel="C1", users=["U1", "U2"]) |> ignore
  c.users_lookup_by_email(email="a@example.com") |> ignore
  c.reactions_add(channel="C1", timestamp="1.2", name="thumbsup") |> ignore
  c.views_open(
    trigger_id="T1",
    view=@client.modal("Title", [@blocks.divider()]),
  )
  |> ignore
  c.files_info(file="F1") |> ignore
  c.team_info() |> ignore
  c.usergroups_users_update(usergroup="S1", users=["U1"]) |> ignore
  assert_eq(fake.method_of(0), "auth.test")
  assert_eq(fake.body_of(0), "")
  assert_eq(fake.method_of(1), "conversations.invite")
  // `users` is comma-joined, per Slack's docs and java-slack-sdk.
  assert_eq(fake.body_of(1), "channel=C1&users=U1%2CU2")
  assert_eq(fake.method_of(2), "users.lookupByEmail")
  assert_eq(fake.body_of(2), "email=a%40example.com")
  assert_eq(fake.method_of(3), "reactions.add")
  assert_eq(fake.body_of(3), "channel=C1&timestamp=1.2&name=thumbsup")
  assert_eq(fake.method_of(4), "views.open")
  assert_true(fake.body_of(4).has_prefix("trigger_id=T1&view="))
  assert_eq(fake.method_of(5), "files.info")
  assert_eq(fake.method_of(6), "team.info")
  assert_eq(fake.method_of(7), "usergroups.users.update")
  assert_eq(fake.body_of(7), "usergroup=S1&users=U1")
}

///|
/// A modal is a `view` payload with typed blocks inside it, and it survives
/// the trip back through the block parser.
async test "a modal carries typed blocks" {
  let view = @client.modal(
    "Report a bug",
    [
      @blocks.input(
        @blocks.TextObject::plain("What happened?"),
        @blocks.plain_text_input(action_id="what", multiline=true),
      ),
    ],
    submit="Send",
    callback_id="bug_report",
  )
  guard view is Object(o) else { fail("expected a view object") }
  assert_eq(o.get("type"), Some(Json::string("modal")))
  assert_eq(o.get("callback_id"), Some(Json::string("bug_report")))
  assert_eq(
    o.get("title"),
    Some({ "type": "plain_text", "text": "Report a bug" }),
  )
  guard o.get("blocks") is Some(blocks_json) else { fail("expected blocks") }
  guard @blocks.parse_blocks(blocks_json) is Some(parsed) else {
    fail("the modal's blocks should parse")
  }
  guard parsed[0] is Input(input) else { fail("expected an input block") }
  guard input.element is Some(PlainTextInput(element)) else {
    fail("expected a plain_text_input")
  }
  assert_eq(element.multiline, Some(true))
}

///|
/// A custom base URL is what a local mock server or an enterprise proxy needs.
async test "a custom base URL is used" {
  let fake = @testing.FakeTransport::ok(["{\"ok\":true}"])
  let c = @client.Client::new(
    fake,
    "xoxb-t",
    base_url="http://localhost:8080/mock",
  )
  c.auth_test() |> ignore
  assert_eq(fake.request(0).url, "http://localhost:8080/mock/auth.test")
}

///|
/// The generic call reaches everything the typed builders do not -- which is
/// the deal that keeps 260-odd methods usable without 260 signatures.
async test "the generic call reaches an unmodelled method" {
  let fake = @testing.FakeTransport::ok(["{\"ok\":true,\"users\":[]}"])
  let c = new_client(fake)
  let p = @api.Params::new()
  p.put_str("team_id", Some("T1"))
  p.put_int("limit", Some(10))
  let response = c.call("admin.users.list", p)
  assert_true(response.ok)
  assert_eq(fake.method_of(0), "admin.users.list")
  assert_eq(fake.body_of(0), "team_id=T1&limit=10")
}
