// The parser's own behaviour, next to it.
//
// The corpus gate in ext/test/modelcorpus proves the properties over 565 real
// payloads; these are the cases a reader needs to see stated, and the ones a
// corpus of scrubbed placeholders cannot show -- an absent field is absent
// there too, so "absent means None and not empty string" has to be pinned here.

///|
test "a user parses, keeps what is not modelled, and round-trips" {
  let payload : Json = {
    "id": "U0123456789",
    "team_id": "T0123456789",
    "name": "alice",
    "is_bot": false,
    "updated": 1700000000,
    "profile": { "display_name": "Alice", "real_name": "Alice Alvarez" },
    "a_field_from_next_tuesday": { "nested": [1, 2, 3] },
  }
  guard @model.User::from_json(payload) is Some(user) else {
    fail("expected a user")
  }
  assert_eq(user.id, "U0123456789")
  assert_eq(user.name, Some("alice"))
  assert_eq(user.is_bot, Some(false))
  assert_eq(user.updated, Some(1700000000L))
  assert_eq(user.profile.unwrap().real_name, Some("Alice Alvarez"))
  // Unmodelled, kept verbatim, and back out unchanged.
  assert_eq(user.extra.length(), 1)
  assert_eq(user.to_json(), payload)
}

///|
/// `id` is the one field that makes a user a user, so a payload without one is
/// not half-parsed -- it is refused, and the caller's `take_obj` leaves it
/// wherever it was.
test "a payload with no id is not a user" {
  assert_eq(@model.User::from_json({ "name": "alice" }), None)
  assert_eq(@model.User::from_json(Json::string("U0123456789")), None)
  assert_eq(@model.User::from_json({ "id": 12345 }), None)
}

///|
/// The rule @jsonx exists for, at the model layer: a field at an unexpected
/// type is never taken, so it survives instead of being dropped or defaulted.
test "a field of the wrong type stays in extra rather than being lost" {
  let payload : Json = { "id": "C0123456789", "name": 42, "is_private": "yes" }
  guard @model.Channel::from_json(payload) is Some(channel) else {
    fail("expected a channel")
  }
  assert_eq(channel.name, None)
  assert_eq(channel.is_private, None)
  assert_eq(channel.to_json(), payload)
}

///|
/// Absent is `None`, not `""`. Slack distinguishes the two -- an unset display
/// name comes back as `""` and a field outside the caller's scopes is missing
/// entirely -- and a model that defaulted would erase the difference.
test "an absent field is None and an empty one is empty" {
  guard @model.User::from_json({ "id": "U1", "real_name": "" }) is Some(user) else {
    fail("expected a user")
  }
  assert_eq(user.real_name, Some(""))
  assert_eq(user.name, None)
}

///|
/// The message's blocks are the same Block Kit this library sends, which is
/// most of the reason to model a message at all.
test "a message's blocks parse into the Block Kit model" {
  let payload : Json = {
    "type": "message",
    "ts": "1700000000.000100",
    "user": "U1",
    "text": "Deploy finished",
    "blocks": [
      {
        "type": "section",
        "text": { "type": "mrkdwn", "text": "*Deploy* finished" },
      },
    ],
  }
  guard @model.Message::from_json(payload) is Some(message) else {
    fail("expected a message")
  }
  assert_eq(message.type_, Some("message"))
  guard message.blocks is Some(blocks) else { fail("expected blocks") }
  assert_eq(blocks.length(), 1)
  assert_true(blocks[0] is Section(_))
  assert_eq(message.to_json(), payload)
}

///|
/// A block type this version has never heard of does not cost the message.
///
/// Same policy as @blocks: an unknown type becomes an opaque variant carrying
/// its JSON, because a bot that breaks on a block released last Tuesday is a
/// worse outcome than one that cannot render it.
test "a message with an unknown block type still parses" {
  let payload : Json = {
    "ts": "1700000000.000100",
    "blocks": [{ "type": "something_new", "payload": { "a": 1 } }],
  }
  guard @model.Message::from_json(payload) is Some(message) else {
    fail("expected a message")
  }
  assert_eq(message.blocks.unwrap().length(), 1)
  assert_eq(message.to_json(), payload)
}

///|
test "display falls back the way Slack's own clients do" {
  let with_display : Json = {
    "id": "U1",
    "name": "alice",
    "real_name": "Alice Alvarez",
    "profile": { "display_name": "Al" },
  }
  assert_eq(@model.User::from_json(with_display).unwrap().display(), "Al")
  // Slack sends "" rather than omitting a display name nobody set.
  let blank_display : Json = {
    "id": "U1",
    "name": "alice",
    "real_name": "Alice Alvarez",
    "profile": { "display_name": "" },
  }
  assert_eq(
    @model.User::from_json(blank_display).unwrap().display(),
    "Alice Alvarez",
  )
  assert_eq(
    @model.User::from_json({ "id": "U1", "name": "alice" }).unwrap().display(),
    "alice",
  )
  // A user the caller has no scope to see the name of is still identifiable.
  assert_eq(@model.User::from_json({ "id": "U1" }).unwrap().display(), "U1")
}

///|
/// A DM has no name at all, so the id is the answer rather than a fallback.
test "a conversation displays its name, or its id when it has none" {
  let named : Json = { "id": "C1", "name": "general" }
  assert_eq(@model.Channel::from_json(named).unwrap().display(), "general")
  let dm : Json = { "id": "D1", "is_im": true, "user": "U1" }
  assert_eq(@model.Channel::from_json(dm).unwrap().display(), "D1")
}

///|
/// The parent of a thread carries `thread_ts == ts`, which is why neither field
/// alone answers "which thread is this".
test "thread_root groups a thread and its parent together" {
  let parent : Json = {
    "ts": "1700000000.000100",
    "thread_ts": "1700000000.000100",
  }
  let reply : Json = {
    "ts": "1700000000.000200",
    "thread_ts": "1700000000.000100",
  }
  let loose : Json = { "ts": "1700000000.000300" }
  let of = j => @model.Message::from_json(j).unwrap()
  assert_eq(of(parent).thread_root(), Some("1700000000.000100"))
  assert_eq(of(reply).thread_root(), Some("1700000000.000100"))
  assert_eq(of(loose).thread_root(), Some("1700000000.000300"))
  assert_eq(of(parent).is_thread_reply(), false)
  assert_eq(of(reply).is_thread_reply(), true)
  assert_eq(of(loose).is_thread_reply(), false)
}

///|
/// Nesting is where a hand-written parser would go wrong, and where the
/// generated one has to be shown working: a message's reactions, its editor,
/// the bot behind it and its files are all separate entities.
test "a message carries its nested entities" {
  let payload : Json = {
    "ts": "1700000000.000100",
    "text": "hello",
    "edited": { "user": "U1", "ts": "1700000000.000200" },
    "reactions": [{ "name": "tada", "count": 2, "users": ["U1", "U2"] }],
    "bot_profile": { "id": "B1", "name": "deploybot" },
    "files": [{ "id": "F1", "name": "log.txt", "size": 1024 }],
  }
  guard @model.Message::from_json(payload) is Some(message) else {
    fail("expected a message")
  }
  assert_eq(message.edited.unwrap().user, Some("U1"))
  assert_eq(message.reactions.unwrap()[0].count, Some(2))
  assert_eq(message.reactions.unwrap()[0].users, Some(["U1", "U2"]))
  assert_eq(message.bot_profile.unwrap().name, Some("deploybot"))
  assert_eq(message.files.unwrap()[0].size, Some(1024))
  assert_eq(message.to_json(), payload)
}

///|
/// All-or-nothing, inherited from `take_arr`: one bad element leaves the whole
/// key alone, because a half-parsed list round-trips as a shorter list.
test "one malformed reaction leaves the whole array in extra" {
  let payload : Json = {
    "ts": "1700000000.000100",
    "reactions": [
      { "name": "tada", "count": 2 },
      Json::string("not a reaction"),
    ],
  }
  guard @model.Message::from_json(payload) is Some(message) else {
    fail("expected a message")
  }
  assert_eq(message.reactions, None)
  assert_eq(message.to_json(), payload)
}
