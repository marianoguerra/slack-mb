// Ported from java-slack-sdk's five `parse_unknown_*` / `parse_fail_on_unknown_*`
// pairs in BlockKitTest.
//
// Each payload is tested twice, once per policy, with java's payloads and its
// exact error strings. The pairing is the point: lenient must keep the payload
// intact, strict must name what it refused, and a change to one without the
// other is a bug.

///|
/// Parse leniently and assert nothing was lost.
fn lenient(text : String) -> Array[@blocks.LayoutBlock] raise {
  let json = parse(text)
  guard @blocks.parse_message_blocks(json) is Some(parsed) else {
    fail("lenient parsing should never fail")
  }
  assert_eq(
    @blocks.blocks_to_json(parsed),
    parse_blocks_field(json),
    msg="lenient parsing lost part of the payload",
  )
  parsed
}

///|
/// Parse strictly and return the message of the error it raised.
fn strict_error(text : String) -> String raise {
  let json = parse(text)
  try @blocks.parse_message_blocks(json, policy=Strict) |> ignore catch {
    e => e.to_string()
  } noraise {
    _ => fail("expected a strict parse to be refused")
  }
}

///|
/// java `unknownBlocksJson`: an unknown block containing an unknown element.
let unknown_block_payload : String =
  #|{"blocks":[{"type":"unknown_block","block_id":"input123",
  #|"label":{"type":"plain_text","text":"Label of input"},
  #|"element":{"type":"unknown_element","action_id":"plain_input",
  #|"placeholder":{"type":"plain_text","text":"Enter some plain text"}}}]}

///|
/// java `parse_unknown_blocks`.
test "an unknown block parses leniently and keeps its payload" {
  let parsed = lenient(unknown_block_payload)
  assert_eq(parsed.length(), 1)
  guard parsed[0] is Unknown(type_=t, raw~) else {
    fail("expected an Unknown block")
  }
  assert_eq(t, "unknown_block")
  // Not merely "it did not crash": the whole block is still there, nested
  // element and all, which is what makes rendering-what-you-can possible.
  guard raw is Object(o) else { fail("expected an object") }
  assert_eq(o.get("block_id"), Some(Json::string("input123")))
  assert_true(o.get("element") is Some(_))
  assert_eq(parsed[0].block_id(), Some("input123"))
}

///|
/// java `parse_fail_on_unknown_blocks`. Reported outside in: the block is named
/// even though it also contains an unknown element.
test "an unknown block is refused strictly, by name" {
  assert_eq(
    strict_error(unknown_block_payload),
    "Unsupported layout block type: unknown_block",
  )
}

///|
/// java `unknownBlockElementsJson`: a known block, an unknown element.
let unknown_element_payload : String =
  #|{"blocks":[{"type":"input","block_id":"input123",
  #|"label":{"type":"plain_text","text":"Label of input"},
  #|"element":{"type":"unknown_element","action_id":"plain_input",
  #|"placeholder":{"type":"plain_text","text":"Enter some plain text"}}}]}

///|
/// java `parse_unknown_block_elements`.
test "an unknown element parses leniently inside a known block" {
  let parsed = lenient(unknown_element_payload)
  guard parsed[0] is Input(b) else { fail("expected an input block") }
  assert_eq(b.label.unwrap().text, "Label of input")
  guard b.element is Some(Unknown(type_=t, ..)) else {
    fail("expected an Unknown element")
  }
  assert_eq(t, "unknown_element")
}

///|
/// java `parse_fail_on_unknown_block_elements`.
test "an unknown element is refused strictly, by name" {
  assert_eq(
    strict_error(unknown_element_payload),
    "Unknown block element type: unknown_element",
  )
}

///|
/// java `unknownContextBlockElementsJson`.
let unknown_context_element_payload : String =
  #|{"blocks":[{"type":"context","elements":[
  #|{"type":"image","image_url":"https://example.com/pin.jpg","alt_text":"images"},
  #|{"type":"unknown_element","text":"something"}]}]}

///|
/// java `parse_unknown_context_block_elements`. The known element beside it
/// still parses -- one unrecognised entry does not poison the list.
test "an unknown context element parses leniently" {
  let parsed = lenient(unknown_context_element_payload)
  guard parsed[0] is Context(b) else { fail("expected a context block") }
  guard b.elements is Some(elements) else { fail("expected elements") }
  assert_eq(elements.length(), 2)
  guard elements[0] is Image(image) else { fail("expected an image element") }
  assert_eq(image.alt_text, Some("images"))
  guard elements[1] is Unknown(type_=t, ..) else { fail("expected an Unknown") }
  assert_eq(t, "unknown_element")
}

///|
/// java `parse_fail_on_unknown_context_block_elements`.
///
/// A DIFFERENT message from the same element type in an `element` slot. java
/// distinguishes the two and its tests assert both strings, because knowing
/// which slot refused is most of the debugging.
test "an unknown context element is refused with the context wording" {
  assert_eq(
    strict_error(unknown_context_element_payload),
    "Unknown context block element type: unknown_element",
  )
}

///|
/// java `unknownTextObjectsJson`.
let unknown_text_payload : String =
  #|{"blocks":[{"type":"section","text":{"type":"unknown_text",
  #|"text":"This is a section block with a button."},
  #|"accessory":{"type":"button","text":{"type":"plain_text","text":"Click Me"},
  #|"value":"click_me_123","action_id":"button"}}]}

///|
/// java `parse_unknown_text_objects`.
///
/// The unknown text type is kept as `TextKind::Other` rather than dropped, so
/// the section still has its text and the payload still round-trips.
test "an unknown text type parses leniently as Other" {
  let parsed = lenient(unknown_text_payload)
  guard parsed[0] is Section(b) else { fail("expected a section") }
  guard b.text is Some(text) else {
    fail("expected the section to keep its text")
  }
  assert_eq(text.kind, Other("unknown_text"))
  assert_eq(text.text, "This is a section block with a button.")
  // The accessory beside it is unaffected.
  guard b.accessory is Some(Button(button)) else { fail("expected a button") }
  assert_eq(button.value, Some("click_me_123"))
}

///|
/// java `parse_fail_on_unknown_text_objects`.
test "an unknown text type is refused strictly, by name" {
  assert_eq(
    strict_error(unknown_text_payload),
    "Unknown text object type: unknown_text",
  )
}

///|
/// java `unknownTextObjectsInInputBlocksJson`: an unknown text type in a
/// `label` and in a `placeholder`.
let unknown_text_in_input_payload : String =
  #|{"blocks":[{"type":"input","block_id":"input123",
  #|"label":{"type":"plain_text2","text":"Label of input"},
  #|"element":{"type":"plain_text_input","action_id":"plain_input",
  #|"placeholder":{"type":"plain_text2","text":"Enter some plain text"}}}]}

///|
/// java `parse_unknown_text_objects_input`.
test "an unknown text type in a label parses leniently" {
  let parsed = lenient(unknown_text_in_input_payload)
  guard parsed[0] is Input(b) else { fail("expected an input block") }
  assert_eq(b.label.unwrap().kind, Other("plain_text2"))
  guard b.element is Some(PlainTextInput(pti)) else {
    fail("expected a plain_text_input")
  }
  assert_eq(pti.placeholder.unwrap().kind, Other("plain_text2"))
}

///|
/// A deliberate divergence from java-slack-sdk.
///
/// java's `parse_never_fails_on_unknown_text_objects_input` asserts that even a
/// STRICT parse accepts an unknown text type in a `label` or a `placeholder` --
/// its input block uses a forgiving deserializer for those two slots while
/// every other slot raises. That is an acknowledged inconsistency in one SDK's
/// implementation, not a fact about Slack: Slack itself rejects
/// `"type": "plain_text2"` wherever it appears.
///
/// So strict is strict here, everywhere. The test is kept, inverted, so the
/// divergence is a decision on the record rather than an accident.
test "strict refuses an unknown text type in a label, unlike java-slack-sdk" {
  assert_eq(
    strict_error(unknown_text_in_input_payload),
    "Unknown text object type: plain_text2",
  )
}

///|
/// java `rich_text_default_behavior_with_unknown` / `rich_text_fail_on_unknown`,
/// folded into one pair.
test "an unknown rich text item, both ways" {
  let payload =
    #|{"blocks":[{"type":"rich_text","elements":[{"type":"rich_text_section","elements":[
    #|{"type":"text","text":"hi "},{"type":"unknown_item","value":"x"}]}]}]}
  let parsed = lenient(payload)
  guard parsed[0] is RichText(b) else { fail("expected rich_text") }
  guard b.elements is Some([Section(elements=items, ..)]) else {
    fail("expected one section")
  }
  assert_eq(items.length(), 2)
  guard items[1] is Unknown(type_=t, ..) else {
    fail("expected an Unknown item")
  }
  assert_eq(t, "unknown_item")
  assert_eq(
    strict_error(payload),
    "Unknown rich text element type: unknown_item",
  )
}

///|
/// The same, one level up: an unrecognised rich-text SECTION type.
test "an unknown rich text section, both ways" {
  let payload =
    #|{"blocks":[{"type":"rich_text","elements":[
    #|{"type":"rich_text_table","rows":[]}]}]}
  let parsed = lenient(payload)
  guard parsed[0] is RichText(b) else { fail("expected rich_text") }
  guard b.elements is Some([section]) else { fail("expected one section") }
  guard section is Unknown(type_=t, ..) else { fail("expected an Unknown") }
  assert_eq(t, "rich_text_table")
  assert_eq(
    strict_error(payload),
    "Unknown rich text element type: rich_text_table",
  )
}

///|
/// Lenient is the default, and it is the right default: Slack ships block types
/// faster than any SDK adopts them, and a bot that stops working because a
/// coworker used a block released last Tuesday is worse than one that renders
/// it as nothing.
test "lenient is the default policy" {
  let json = parse(unknown_block_payload)
  // No policy argument: must not raise.
  assert_true(@blocks.parse_message_blocks(json) is Some(_))
}

///|
/// The empty type is a real value, not a missing field: Slack's scrubbed
/// fixtures contain literal `"type": ""`, and 8 blocks in the vendored corpus
/// have one. It must round-trip, and strict must report it as the empty name
/// rather than as something misleading.
test "an empty type is unmodelled but survives" {
  let payload =
    #|{"blocks":[{"type":"","block_id":"b","text":"whatever"}]}
  let parsed = lenient(payload)
  guard parsed[0] is Unknown(type_=t, ..) else { fail("expected an Unknown") }
  assert_eq(t, "")
  assert_eq(strict_error(payload), "Unsupported layout block type: ")
}

///|
/// A payload that is not an array is a caller mistake, not "no blocks", so it
/// is `None` rather than an empty list -- which would silently send a message
/// with nothing in it.
test "a non-array blocks value is None, not an empty list" {
  assert_eq(@blocks.parse_blocks(Json::string("not an array")), None)
  assert_eq(@blocks.parse_blocks({ "type": "section" }), None)
  guard @blocks.parse_blocks(Json::array([])) is Some(empty) else {
    fail("an empty array is a valid, empty block list")
  }
  assert_eq(empty.length(), 0)
}
