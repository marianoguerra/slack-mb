// One successful call to every method the mock implements.
//
// A function rather than a table, because the calls depend on each other: you
// cannot update a message you have not posted, and you cannot delete a
// scheduled message without its id. Running them in order against one workspace
// is also the more honest exercise -- it is what an app does.
//
// Every probe must SUCCEED. A refusal has almost no body, so a probe that
// quietly started failing would compare an empty payload against the corpus and
// pass, which is the failure mode this whole check exists to avoid. `probe`
// therefore fails the test on `ok: false` rather than recording it.

///|
/// One method's answer, ready to be compared against its recorded fixture.
priv struct Probe {
  api_method : String
  body : Json
}

///|
/// The state a probe run threads through itself: the ids the earlier calls
/// minted, which the later ones need.
priv struct Probes {
  ws : @mock.Workspace
  out : Array[Probe]
}

///|
/// Call one method and record what came back.
///
/// Goes through `@api.build_request` and `Workspace::handle` rather than
/// `Workspace::invoke`, so the URL, the `Authorization` header and the form
/// body are all exercised -- the same path a real client takes, which is what
/// makes this a check of the library too and not only of the dispatcher.
fn Probes::probe(
  self : Self,
  api_method : String,
  fields : Array[(String, String)],
) -> Json raise {
  let params = @api.Params::new()
  for entry in fields {
    params.put_str(entry.0, Some(entry.1))
  }
  let request = @api.build_request(
    @api.default_api_url,
    api_method,
    params,
    token=@mock.demo_token,
  )
  let response = self.ws.handle(request) catch {
    e => fail("\{api_method} raised: \{e}")
  }
  let body = @json.parse(response.body) catch {
    _ => fail("\{api_method} did not answer JSON")
  }
  guard body is Object(o) else { fail("\{api_method} answered a non-object") }
  if o.get("ok") is Some(False) {
    let code = match o.get("error") {
      Some(String(c)) => c
      _ => "?"
    }
    fail(
      "probe for \{api_method} was refused with `\{code}` -- fix the probe or the handler; a refusal has no body to compare",
    )
  }
  self.out.push({ api_method, body })
  body
}

///|
/// A string field of a response, for the probes that feed the next one.
fn str_at(body : Json, path : Array[String]) -> String raise {
  let mut here = body
  for key in path {
    guard here is Object(o) && o.get(key) is Some(next) else {
      fail("expected \{key} in \{body.stringify()}")
    }
    here = next
  }
  guard here is String(s) else { fail("\{path.join(".")} is not a string") }
  s
}

///|
/// Drive every implemented method once, in an order where each one can
/// succeed.
fn probe_all(ws : @mock.Workspace) -> Array[Probe] raise {
  let p : Probes = { ws, out: [] }
  let alice = ws.demo_id("alice")
  let carol = ws.demo_id("carol")
  let dave = ws.demo_id("dave")
  let general = ws.demo_id("general")
  let random = ws.demo_id("random")
  let dm = ws.demo_id("dm")
  let thread_root = ws.demo_id("thread_root")
  let pinned = ws.demo_id("pinned")
  let usergroup = ws.demo_id("usergroup")
  let seeded_file = ws.demo_id("file")

  // --- identity and the workspace -----------------------------------------
  p.probe("api.test", [("foo", "bar")]) |> ignore
  p.probe("auth.test", []) |> ignore
  p.probe("team.info", []) |> ignore
  p.probe("team.profile.get", []) |> ignore

  // --- users ---------------------------------------------------------------
  p.probe("users.info", [("user", alice), ("include_locale", "true")]) |> ignore
  p.probe("users.list", [("include_locale", "true")]) |> ignore
  p.probe("users.lookupByEmail", [("email", "alice@example.com")]) |> ignore
  p.probe("users.conversations", [
    ("user", alice),
    ("types", "public_channel,private_channel"),
  ])
  |> ignore
  p.probe("users.getPresence", [("user", alice)]) |> ignore
  p.probe("users.setPresence", [("presence", "auto")]) |> ignore
  p.probe("users.profile.get", [("user", alice)]) |> ignore
  p.probe("users.profile.set", [("name", "title"), ("value", "Principal")])
  |> ignore

  // --- usergroups ----------------------------------------------------------
  // No `include_count` here: `user_count` is in `usergroups.list`'s recorded
  // sample and in neither `usergroups.create`'s nor `usergroups.users.update`'s,
  // so asking for it would be the probe inventing a field rather than the mock.
  p.probe("usergroups.create", [("name", "Design"), ("handle", "design")])
  |> ignore
  p.probe("usergroups.list", [
    ("include_users", "true"),
    ("include_count", "true"),
  ])
  |> ignore
  p.probe("usergroups.users.list", [("usergroup", usergroup)]) |> ignore
  p.probe("usergroups.users.update", [
    ("usergroup", usergroup),
    ("users", "\{alice},\{carol}"),
  ])
  |> ignore

  // --- conversations, reading ----------------------------------------------
  p.probe("conversations.list", [
    ("types", "public_channel,private_channel,im,mpim"),
  ])
  |> ignore
  p.probe("conversations.info", [
    ("channel", general),
    ("include_num_members", "true"),
    ("include_locale", "true"),
  ])
  |> ignore
  p.probe("conversations.members", [("channel", general)]) |> ignore
  p.probe("conversations.history", [("channel", general)]) |> ignore
  p.probe("conversations.replies", [("channel", general), ("ts", thread_root)])
  |> ignore

  // --- conversations, writing ----------------------------------------------
  //
  // A throwaway channel takes the destructive probes, so that the demo
  // workspace the later probes read is left as it was.
  let scratch = str_at(
    p.probe("conversations.create", [("name", "probe-scratch")]),
    ["channel", "id"],
  )
  p.probe("conversations.invite", [("channel", scratch), ("users", dave)])
  |> ignore
  p.probe("conversations.kick", [("channel", scratch), ("user", dave)])
  |> ignore
  p.probe("conversations.join", [("channel", random)]) |> ignore
  p.probe("conversations.rename", [
    ("channel", scratch),
    ("name", "probe-renamed"),
  ])
  |> ignore
  p.probe("conversations.setPurpose", [
    ("channel", scratch),
    ("purpose", "A channel the probes made"),
  ])
  |> ignore
  p.probe("conversations.setTopic", [("channel", scratch), ("topic", "Probing")])
  |> ignore
  p.probe("conversations.mark", [
    ("channel", scratch),
    ("ts", "1700000000.000001"),
  ])
  |> ignore
  p.probe("conversations.leave", [("channel", scratch)]) |> ignore
  p.probe("conversations.archive", [("channel", scratch)]) |> ignore
  p.probe("conversations.open", [("users", carol)]) |> ignore
  p.probe("conversations.close", [("channel", dm)]) |> ignore

  // --- chat ----------------------------------------------------------------
  //
  // Blocks on the way in, so that the round-trip check below has something to
  // walk and the corpus comparison sees a message with a `blocks` array.
  let blocks = @blocks.blocks_to_json([
    @blocks.header("Probe"),
    @blocks.section_text("*bold* and _italic_"),
    @blocks.divider(),
    @blocks.context([@blocks.context_text("posted by the shape probe")]),
  ]).stringify()
  let posted = p.probe("chat.postMessage", [
    ("channel", general),
    ("text", "probe"),
    ("blocks", blocks),
  ])
  let posted_ts = str_at(posted, ["ts"])
  p.probe("chat.postEphemeral", [
    ("channel", general),
    ("user", alice),
    ("text", "only you can see this"),
  ])
  |> ignore
  p.probe("chat.update", [
    ("channel", general),
    ("ts", posted_ts),
    ("text", "probe, updated"),
    ("blocks", blocks),
  ])
  |> ignore
  p.probe("chat.getPermalink", [("channel", general), ("message_ts", posted_ts)])
  |> ignore
  p.probe("chat.unfurl", [
    ("channel", general),
    ("ts", posted_ts),
    ("unfurls", "{}"),
  ])
  |> ignore
  p.probe("chat.meMessage", [("channel", general), ("text", "waves")]) |> ignore
  // Far enough ahead that the workspace clock, which advances a second per
  // call, cannot reach it during the run.
  let scheduled = p.probe("chat.scheduleMessage", [
    ("channel", general),
    ("post_at", "1900000000"),
    ("text", "later"),
  ])
  let scheduled_id = str_at(scheduled, ["scheduled_message_id"])
  p.probe("chat.scheduledMessages.list", [("channel", general)]) |> ignore
  p.probe("chat.deleteScheduledMessage", [
    ("scheduled_message_id", scheduled_id),
  ])
  |> ignore
  p.probe("chat.delete", [("channel", general), ("ts", posted_ts)]) |> ignore

  // --- reactions, pins, bookmarks ------------------------------------------
  p.probe("reactions.add", [
    ("channel", general),
    ("timestamp", pinned),
    ("name", "tada"),
  ])
  |> ignore
  p.probe("reactions.get", [("channel", general), ("timestamp", pinned)])
  |> ignore
  p.probe("reactions.list", [("user", carol)]) |> ignore
  p.probe("reactions.remove", [
    ("channel", general),
    ("timestamp", pinned),
    ("name", "tada"),
  ])
  |> ignore
  p.probe("pins.add", [("channel", general), ("timestamp", thread_root)])
  |> ignore
  p.probe("pins.list", [("channel", general)]) |> ignore
  p.probe("pins.remove", [("channel", general), ("timestamp", thread_root)])
  |> ignore
  p.probe("bookmarks.add", [
    ("channel", general),
    ("title", "Docs"),
    ("type", "link"),
    ("link", "https://example.com/docs"),
  ])
  |> ignore
  p.probe("bookmarks.list", [("channel_id", general)]) |> ignore

  // --- files ---------------------------------------------------------------
  let reserved = p.probe("files.getUploadURLExternal", [
    ("filename", "notes.txt"),
    ("length", "12"),
  ])
  let file_id = str_at(reserved, ["file_id"])
  p.probe("files.completeUploadExternal", [
    ("files", "[{\"id\":\"\{file_id}\",\"title\":\"Notes\"}]"),
    ("channel_id", general),
  ])
  |> ignore
  p.probe("files.info", [("file", seeded_file)]) |> ignore
  p.probe("files.list", [("count", "10"), ("page", "1")]) |> ignore
  p.probe("files.delete", [("file", file_id)]) |> ignore

  // --- views ---------------------------------------------------------------
  let modal = @client.modal("Probe", [@blocks.section_text("Hello")]).stringify()
  let opened = p.probe("views.open", [
    ("trigger_id", "123.456.abc"),
    ("view", modal),
  ])
  let view_id = str_at(opened, ["view", "id"])
  p.probe("views.push", [("trigger_id", "123.456.def"), ("view", modal)])
  |> ignore
  p.probe("views.update", [("view_id", view_id), ("view", modal)]) |> ignore
  p.probe("views.publish", [
    ("user_id", alice),
    ("view", @client.home_view([@blocks.divider()]).stringify()),
  ])
  |> ignore

  // --- last, because it stops the token working ----------------------------
  //
  // `test=true` is the dry run. Doing it for real would make every probe after
  // this one fail with `token_revoked`, and there is nothing after it -- but
  // relying on being last is exactly how that breaks later.
  p.probe("auth.revoke", [("test", "true")]) |> ignore
  p.out
}
