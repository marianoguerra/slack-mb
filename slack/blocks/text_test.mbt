// Text objects. Small, and the thing every other block leans on.

///|
test "plain_text and mrkdwn round-trip with their own flags" {
  let plain = @blocks.TextObject::plain("hello", emoji=true)
  assert_eq(plain.to_json(), {
    "type": "plain_text",
    "text": "hello",
    "emoji": true,
  })
  let md = @blocks.TextObject::mrkdwn("*hello*", verbatim=true)
  assert_eq(md.to_json(), {
    "type": "mrkdwn",
    "text": "*hello*",
    "verbatim": true,
  })
  for text in [plain, md] {
    guard @blocks.TextObject::from_json(text.to_json()) is Some(back) else {
      fail("expected a text object")
    }
    assert_eq(back, text)
  }
}

///|
/// `emoji` and `verbatim` are absent when unset, never `false`. Sending an
/// explicit `false` is a different instruction to Slack from saying nothing,
/// and a caller who did not mention emoji did not ask for them to be off.
test "unset flags are omitted, not written as false" {
  assert_eq(@blocks.TextObject::plain("hello").to_json(), {
    "type": "plain_text",
    "text": "hello",
  })
  assert_eq(@blocks.TextObject::mrkdwn("hello").to_json(), {
    "type": "mrkdwn",
    "text": "hello",
  })
  // ...and an explicit false is preserved as an explicit false.
  assert_eq(@blocks.TextObject::plain("hello", emoji=false).to_json(), {
    "type": "plain_text",
    "text": "hello",
    "emoji": false,
  })
}

///|
/// The two things that make something a text object are a `type` and a `text`.
/// Anything else is not one, and saying so is what lets the caller's key stay
/// in `extra` rather than being half-consumed.
test "a text object needs a type and a text" {
  assert_eq(@blocks.TextObject::from_json(Json::string("bare")), None)
  assert_eq(@blocks.TextObject::from_json({ "text": "no type" }), None)
  assert_eq(@blocks.TextObject::from_json({ "type": "plain_text" }), None)
  assert_eq(
    @blocks.TextObject::from_json({ "type": "plain_text", "text": 42 }),
    None,
  )
}

///|
/// An empty `text` and an empty `type` are both real values in Slack's scrubbed
/// fixtures, so neither is a reason to refuse.
test "empty strings are values, not absences" {
  guard @blocks.TextObject::from_json({ "type": "", "text": "" }) is Some(t) else {
    fail("an empty type and text should still parse")
  }
  assert_eq(t.kind, Other(""))
  assert_eq(t.text, "")
  assert_eq(t.to_json(), { "type": "", "text": "" })
}

///|
/// Unknown keys survive. Slack adds fields to text objects faster than any SDK
/// adopts them, and an app that reads a message and writes it back must not
/// strip what it did not understand.
test "unknown keys are kept in extra" {
  let json : Json = {
    "type": "mrkdwn",
    "text": "hi",
    "future_field": { "a": 1 },
  }
  guard @blocks.TextObject::from_json(json) is Some(t) else {
    fail("expected a text object")
  }
  assert_eq(t.extra.get("future_field"), Some({ "a": 1 }))
  assert_eq(t.extra.get("text"), None)
  assert_eq(t.to_json(), json)
}

///|
/// A field with the wrong type is not consumed, so it lands in `extra` and
/// comes back out. Without that rule the value would be dropped: `emoji` is
/// modelled as a boolean, so a string `emoji` would parse as `None` and
/// disappear on the way back.
test "a field with an unexpected type falls through to extra" {
  let json : Json = { "type": "plain_text", "text": "hi", "emoji": "yes" }
  guard @blocks.TextObject::from_json(json) is Some(t) else {
    fail("expected a text object")
  }
  assert_eq(t.emoji, None)
  assert_eq(t.extra.get("emoji"), Some(Json::string("yes")))
  assert_eq(t.to_json(), json)
}

///|
test "type_name and validate agree with the kind" {
  assert_eq(@blocks.TextObject::plain("x").type_name(), "plain_text")
  assert_eq(@blocks.TextObject::mrkdwn("x").type_name(), "mrkdwn")
  assert_eq(@blocks.TextKind::of_name("plain_text"), PlainText)
  assert_eq(@blocks.TextKind::of_name("mrkdwn"), Mrkdwn)
  assert_eq(@blocks.TextKind::of_name("something"), Other("something"))
  // A known kind validates; an unknown one raises.
  @blocks.TextObject::plain("x").validate()
  let odd = @blocks.TextObject::{
    kind: Other("weird"),
    text: "x",
    emoji: None,
    verbatim: None,
    extra: Map([]),
  }
  try odd.validate() catch {
    @blocks.UnknownTextObject(t) => assert_eq(t, "weird")
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected an unknown text object to be refused")
  }
}
