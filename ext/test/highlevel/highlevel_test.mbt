// The typed client, end to end against @mock.
//
// The point of these is the pairing of a method with the key its payload
// arrives under. That is the one fact @typed knows which nothing else does, it
// cannot be derived, and it is exactly what a scripted transport could not
// check -- a fake answers what its author believed, and the belief is what is
// under test. @mock's output is held to the recorded corpus by
// ext/test/mockshape, so a wrong key here fails rather than agreeing with
// itself.

///|
/// Named `new_api` rather than `api`, which would shadow the `@api` alias.
fn new_api() -> (@mock.Workspace, @typed.Api) {
  let ws = @mock.Workspace::demo()
  (ws, @typed.Api::of(@client.Client::new(ws.transport(), @mock.demo_token)))
}

///|
async test "users.info answers a User, not an envelope" {
  let (ws, api) = new_api()
  let user = api.users_info(user=ws.demo_id("alice"))
  assert_eq(user.id, ws.demo_id("alice"))
  assert_eq(user.name, Some("alice"))
  assert_eq(user.display(), "Alice Alvarez")
  assert_eq(user.is_bot, Some(false))
}

///|
/// `members` holds user objects on `users.list` and bare ids on
/// `conversations.members`. Same key, two types, and the reason there is no
/// generic extractor -- asserted rather than described.
async test "the same key holds users on one method and ids on another" {
  let (ws, api) = new_api()
  let listed = api.users_list()
  assert_true(listed.items.length() >= 5)
  assert_eq(listed.items[0].id, ws.demo_id("alice"))
  let members = api.conversations_members(channel=ws.demo_id("general"))
  assert_true(members.items.length() >= 2)
  assert_true(members.items.contains(ws.demo_id("alice")))
}

///|
async test "conversations.info answers a Channel" {
  let (ws, api) = new_api()
  let channel = api.conversations_info(channel=ws.demo_id("general"))
  assert_eq(channel.id, ws.demo_id("general"))
  assert_eq(channel.display(), "general")
  assert_eq(channel.is_channel, Some(true))
}

///|
/// A DM has no name, so `display` answering the id is the normal case rather
/// than a fallback.
async test "a DM has no name and displays its id" {
  let (ws, api) = new_api()
  let dm = api.conversations_info(channel=ws.demo_id("dm"))
  assert_eq(dm.is_im, Some(true))
  assert_eq(dm.display(), ws.demo_id("dm"))
}

///|
/// `channel` is an OBJECT on conversations.info and a bare STRING here. The
/// clearest case in the whole API for why the method has to name its own key.
async test "chat.postMessage answers ids, not a Channel" {
  let (ws, api) = new_api()
  let posted = api.chat_post_message(
    channel=ws.demo_id("general"),
    text="Deploy finished",
  )
  assert_eq(posted.channel, ws.demo_id("general"))
  assert_true(posted.ts != "")
  assert_eq(posted.message.unwrap().text, Some("Deploy finished"))
}

///|
/// The round trip that makes @model worth having: blocks out as `LayoutBlock`,
/// blocks back as `LayoutBlock`, with no JSON in between.
async test "blocks go out typed and come back typed" {
  let (ws, api) = new_api()
  api.chat_post_message(channel=ws.demo_id("general"), text="fallback", blocks=[
    @blocks.header("Deploy"),
    @blocks.section_text("*done* in 4m12s"),
    @blocks.divider(),
  ])
  |> ignore
  let history = api.conversations_history(
    channel=ws.demo_id("general"),
    limit=1,
  )
  let latest = history.items[0]
  guard latest.blocks is Some(blocks) else {
    fail("expected typed blocks back")
  }
  assert_eq(blocks.length(), 3)
  assert_true(blocks[0] is Header(_))
  assert_true(blocks[2] is Divider(_))
}

///|
/// The parent of a thread carries `thread_ts == ts`, so neither field alone
/// separates it from its replies.
async test "conversations.replies distinguishes the parent from the replies" {
  let (ws, api) = new_api()
  let root = ws.demo_id("thread_root")
  let replies = api.conversations_replies(
    channel=ws.demo_id("general"),
    ts=root,
  )
  assert_true(replies.items.length() >= 2)
  let parent = replies.items[0]
  assert_eq(parent.ts, Some(root))
  assert_eq(parent.is_thread_reply(), false)
  assert_eq(parent.thread_root(), Some(root))
  for reply in replies.items[1:] {
    assert_eq(reply.is_thread_reply(), true)
    assert_eq(reply.thread_root(), Some(root))
  }
}

///|
async test "team.info answers a Team and views.open answers a View" {
  let (_, api) = new_api()
  let team = api.team_info()
  assert_true(team.name is Some(_))
  let view = api.views_open(
    trigger_id="trigger.1",
    view=@client.modal("Deploy", [@blocks.section_text("Ready?")], submit="Go"),
  )
  assert_eq(view.type_, Some("modal"))
  assert_eq(view.title.unwrap().to_json(), {
    "type": "plain_text",
    "text": "Deploy",
  })
}

///|
async test "usergroups and files come back modelled too" {
  let (ws, api) = new_api()
  let groups = api.usergroups_list()
  assert_true(groups.length() >= 1)
  assert_eq(groups[0].id, ws.demo_id("usergroup"))
  let file = api.files_info(file=ws.demo_id("file"))
  assert_eq(file.id, ws.demo_id("file"))
  assert_true(file.name is Some(_))
}

///|
/// A cursor walk, without a `Paginator`. `Page::cursor` normalises Slack's
/// empty `next_cursor` to `None`, which is what stops this being an infinite
/// loop over the last page.
async test "a page carries the cursor, and the last page carries none" {
  let (_, api) = new_api()
  let mut cursor = None
  let seen = []
  let mut pages = 0
  while pages < 10 {
    let page = api.users_list(cursor?, limit=2)
    pages = pages + 1
    for user in page.items {
      seen.push(user.id)
    }
    cursor = page.cursor
    if !page.has_more() {
      break
    }
  }
  assert_true(pages > 1, msg="the walk did not paginate")
  assert_eq(cursor, None)
  let all_at_once = api.users_list_all()
  assert_eq(seen.length(), all_at_once.length())
}

///|
/// A refusal is the low-level error, wrapped and reachable in one step.
async test "a platform refusal arrives as Slack(PlatformError)" {
  let (_, api) = new_api()
  let error = try {
    api.users_info(user="U_NOT_A_USER") |> ignore
    fail("expected a refusal")
  } catch {
    e => @typed.to_typed_error(e)
  }
  assert_eq(error.code(), "slack_webapi_platform_error")
  guard error.slack() is Some(slack) else {
    fail("expected the wrapped SlackError")
  }
  assert_eq(slack.describe_error(), "An API error occurred: user_not_found")
}

///|
/// A 429 is the case a caller most needs to reach through the wrapper, so it is
/// the one worth pinning: `slack()` gets to the retry-after in one step.
async test "a rate limit keeps its retry_after through the wrapper" {
  let (ws, api) = new_api()
  ws.inject("users.info", RateLimited(30))
  let error = try {
    api.users_info(user=ws.demo_id("alice")) |> ignore
    fail("expected a rate limit")
  } catch {
    e => @typed.to_typed_error(e)
  }
  assert_eq(error.code(), "slack_webapi_rate_limited_error")
  assert_true(error.slack() is Some(RateLimitedError(retry_after=30)))
}

///|
/// The case @typed's own error exists for: `ok: true` and a payload that is not
/// what this version models. It cannot be produced from Slack, so it is
/// produced from a scripted transport -- which is the honest way to reach a
/// path that should never happen.
async test "a payload of the wrong shape names the method and the key" {
  let fake = @testing.FakeTransport::ok(["{\"ok\":true,\"user\":\"U123\"}"])
  let api = @typed.Api::of(@client.Client::new(fake, "xoxb-test"))
  let error = try {
    api.users_info(user="U123") |> ignore
    fail("expected a shape error")
  } catch {
    e => @typed.to_typed_error(e)
  }
  assert_eq(error.code(), "slack_response_shape_error")
  assert_true(error.slack() is None)
  assert_eq(
    error.describe_error(),
    "users.info answered ok, but 'user' was missing or not the shape this version models",
  )
}

///|
/// The two levels in one function, which is the expected way to use this: the
/// typed call for what is modelled, `Api::client` for what is not.
async test "the low-level client is always reachable" {
  let (ws, api) = new_api()
  let channel = api.conversations_info(channel=ws.demo_id("general"))
  // `bookmarks.list` has no typed wrapper and no @model entity, so it goes
  // through the client -- in the same function, on the same connection.
  let response = api.client().bookmarks_list(channel_id=channel.id)
  assert_true(response.ok)
  assert_true(response.get("bookmarks") is Some(Array(_)))
}

///|
/// The drift gate: every typed call against the one it wraps.
///
/// Both inputs are generated interfaces, committed and already CI-gated for
/// freshness by `just info-check`, which is what makes reading them safe --
/// the same argument `ext/test/mockshape` makes for its own scrape.
///
/// It catches the two ways this package can rot. A method renamed in `@client`
/// leaves an `Api::` call wrapping nothing, and `Api` promising a name
/// `Client` does not have is a name nobody can guess from the low-level API.
/// Neither is a compile error, because the two are only connected by
/// convention -- so the convention is asserted here.
test "every typed call wraps a client method of the same name" {
  let wrapped = interface_methods("slack/client/pkg.generated.mbti", "Client")
  let typed = interface_methods("slack/typed/pkg.generated.mbti", "Api")
  assert_true(
    wrapped.length() >= 60,
    msg="only \{wrapped.length()} client methods found; the scrape probably broke",
  )
  assert_true(
    typed.length() >= 25,
    msg="only \{typed.length()} typed methods found; the scrape probably broke",
  )
  let orphans = typed.filter(name => !wrapped.contains(name))
  assert_eq(
    orphans,
    [],
    msg="Api methods with no Client counterpart: \{orphans.join(", ")}",
  )
}

///|
/// The `async` methods a generated interface declares on a type.
///
/// Probing for the repo root, for the reason `@fixtures.fixtures_root` does:
/// `moon test` covers the whole workspace from any directory, so a fixed
/// relative path would be green in one place and red in another.
fn interface_methods(relative : String, type_ : String) -> Array[String] raise {
  let mut text = ""
  let mut found = false
  for prefix in ["", "../", "../../"] {
    let path = prefix + relative
    if @fs.path_exists(path) {
      text = @fs.read_file_to_string(path) catch {
        _ => fail("could not read \{path}")
      }
      found = true
      break
    }
  }
  guard found else {
    fail("could not find \{relative} from the working directory")
  }
  let prefix = "pub async fn \{type_}::"
  let names : Array[String] = []
  for line in text.split("\n") {
    let line = line.to_owned()
    guard line.has_prefix(prefix) else { continue }
    let rest = line[prefix.length():].to_owned()
    guard rest.split_once("(") is Some((name, _)) else { continue }
    names.push(name.to_owned())
  }
  names
}
