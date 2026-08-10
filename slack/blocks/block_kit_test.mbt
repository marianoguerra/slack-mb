// Ported from java-slack-sdk's `BlockKitTest`.
//
// Its payloads are real ones, taken from Slack's own documentation and from
// support cases, which is why they are reproduced here rather than invented.
// Every one is round-tripped as well as inspected: java only asserts that
// parsing produced something non-null, which would not have caught a model that
// silently dropped `focus_on_load`.

///|
/// Parse a `{"blocks": [...]}` payload, round-trip it, and return the blocks.
fn message_blocks(text : String) -> Array[@blocks.LayoutBlock] raise {
  let json = parse(text)
  guard @blocks.parse_message_blocks(json) is Some(parsed) else {
    fail("expected a blocks array")
  }
  assert_eq(
    @blocks.blocks_to_json(parsed),
    parse_blocks_field(json),
    msg="round trip changed the payload",
  )
  parsed
}

///|
/// java `parseHeader`.
test "a header block" {
  let parsed = message_blocks(
    (
      #|{"blocks":[{"type":"header","block_id":"b","text":{"type":"plain_text","text":"Budget Performance"}}]}
    ),
  )
  guard parsed[0] is Header(b) else { fail("expected a header block") }
  assert_eq(b.block_id, Some("b"))
  assert_eq(b.text.unwrap().text, "Budget Performance")
  assert_eq(b.text.unwrap().kind, PlainText)
}

///|
/// java `parseMarkdownBlock`. The markdown block carries a bare string, not a
/// text object -- it exists so an AI app can hand Slack ordinary markdown
/// instead of converting it to Slack's `mrkdwn` dialect first.
test "a markdown block carries a bare string" {
  let block = round_trip(
    (
      #|{"type":"markdown","text":"**this is bold**"}
    ),
  )
  guard block is Markdown(b) else { fail("expected a markdown block") }
  assert_eq(b.text, Some("**this is bold**"))
}

///|
/// java `parseCheckboxes`: checkboxes in an input block and as a section
/// accessory, with and without option descriptions.
test "checkboxes in an input and as an accessory" {
  let parsed = message_blocks(
    (
      #|{"blocks":[
      #|{"type":"input","element":{"type":"checkboxes","action_id":"input-action-id","options":[
      #|{"text":{"type":"plain_text","text":"*this is plain_text text*","emoji":true},"value":"value-0"},
      #|{"text":{"type":"plain_text","text":"*this is plain_text text*","emoji":true},"value":"value-1"}]},
      #|"label":{"type":"plain_text","text":"Label","emoji":true}},
      #|{"type":"section","text":{"type":"mrkdwn","text":"This is a section block with checkboxes."},
      #|"accessory":{"type":"checkboxes","action_id":"section-action-id","options":[
      #|{"text":{"type":"mrkdwn","text":"*this is mrkdwn text*"},"description":{"type":"mrkdwn","text":"*this is mrkdwn text*"},"value":"value-0"}]}}]}
    ),
  )
  guard parsed[0] is Input(input) else { fail("expected an input block") }
  guard input.element is Some(Options(checks)) else {
    fail("expected checkboxes")
  }
  assert_eq(checks.kind, Checkboxes)
  assert_eq(checks.action_id, Some("input-action-id"))
  assert_eq(checks.options.unwrap().length(), 2)
  assert_eq(checks.options.unwrap()[0].value, Some("value-0"))
  assert_eq(checks.options.unwrap()[0].text.emoji, Some(true))
  guard parsed[1] is Section(section) else { fail("expected a section") }
  guard section.accessory is Some(Options(accessory)) else {
    fail("expected a checkboxes accessory")
  }
  // The description is the field a model that only knows `text` and `value`
  // would drop.
  assert_eq(
    accessory.options.unwrap()[0].description.unwrap().text,
    "*this is mrkdwn text*",
  )
}

///|
/// java `confirm_style`. `style` was added to the confirmation dialog late; a
/// model written before it silently discards the caller's `danger`.
test "a confirmation dialog carries its style" {
  let json = parse(
    (
      #|{"title":{"type":"plain_text","text":"Are you sure?"},
      #|"text":{"type":"mrkdwn","text":"Wouldn't you prefer a good game of _chess_?"},
      #|"confirm":{"type":"plain_text","text":"Do it"},
      #|"deny":{"type":"plain_text","text":"Stop, I've changed my mind!"},
      #|"style":"primary"}
    ),
  )
  guard @blocks.ConfirmationDialogObject::from_json(json) is Some(dialog) else {
    fail("expected a confirmation dialog")
  }
  assert_eq(dialog.style, Some("primary"))
  assert_eq(dialog.title.unwrap().text, "Are you sure?")
  assert_eq(dialog.deny.unwrap().text, "Stop, I've changed my mind!")
  assert_eq(dialog.to_json(), json)
}

///|
/// java `testResponseUrlEnabled_conversations`.
test "response_url_enabled on a conversations select" {
  let parsed = message_blocks(
    (
      #|{"blocks":[{"type":"input","element":{"type":"conversations_select",
      #|"placeholder":{"type":"plain_text","text":"Select a conversation","emoji":true},
      #|"response_url_enabled":true},
      #|"label":{"type":"plain_text","text":"Choose the conversation to publish your result to:","emoji":true}}]}
    ),
  )
  guard parsed[0] is Input(input) else { fail("expected an input block") }
  guard input.element is Some(Select(select)) else { fail("expected a select") }
  assert_eq(select.kind, Conversations)
  assert_eq(select.response_url_enabled, Some(true))
}

///|
/// java `defaultToCurrentConversation`, on both the single and multi variants.
test "default_to_current_conversation on both conversation selects" {
  let parsed = message_blocks(
    (
      #|{"blocks":[
      #|{"type":"section","text":{"type":"mrkdwn","text":"Test block with multi conversations select"},
      #|"accessory":{"type":"multi_conversations_select",
      #|"placeholder":{"type":"plain_text","text":"Select conversations","emoji":true},
      #|"default_to_current_conversation":true}},
      #|{"type":"section","text":{"type":"mrkdwn","text":"Test block with multi conversations select"},
      #|"accessory":{"type":"conversations_select",
      #|"placeholder":{"type":"plain_text","text":"Select conversations","emoji":true},
      #|"default_to_current_conversation":true}}]}
    ),
  )
  guard parsed[0] is Section(a) else { fail("expected a section") }
  guard a.accessory is Some(Select(multi)) else { fail("expected a select") }
  assert_eq(multi.kind, MultiConversations)
  assert_eq(multi.default_to_current_conversation, Some(true))
  guard parsed[1] is Section(b) else { fail("expected a section") }
  guard b.accessory is Some(Select(single)) else { fail("expected a select") }
  assert_eq(single.kind, Conversations)
  assert_eq(single.default_to_current_conversation, Some(true))
}

///|
/// java `timePickerElement`.
test "a timepicker accessory" {
  let block = round_trip(
    (
      #|{"type":"section","block_id":"section1234","text":{"type":"mrkdwn","text":"Pick a date for the deadline."},
      #|"accessory":{"type":"timepicker","action_id":"timepicker123","initial_time":"11:40",
      #|"placeholder":{"type":"plain_text","text":"Select a time"}}}
    ),
  )
  guard block is Section(b) else { fail("expected a section") }
  guard b.accessory is Some(Picker(p)) else { fail("expected a picker") }
  assert_eq(p.kind, Time)
  assert_eq(p.initial_time, Some("11:40"))
  assert_eq(p.action_id, Some("timepicker123"))
}

///|
/// java `focusOnLoad` and `noFocusOnLoad`, as a pair: present means `Some(true)`
/// and absent means `None`, never `Some(false)`. The difference matters --
/// `false` would be written back to Slack as an explicit "do not focus".
test "focus_on_load is present or absent, never defaulted" {
  let with_focus = message_blocks(
    (
      #|{"blocks":[{"type":"input","element":{"type":"conversations_select",
      #|"placeholder":{"type":"plain_text","text":"Select a conversation"},"focus_on_load":true},
      #|"label":{"type":"plain_text","text":"Choose the conversation to publish your result to:"}}]}
    ),
  )
  guard with_focus[0] is Input(a) else { fail("expected an input") }
  guard a.element is Some(Select(sa)) else { fail("expected a select") }
  assert_eq(sa.focus_on_load, Some(true))
  let without = message_blocks(
    (
      #|{"blocks":[{"type":"input","element":{"type":"conversations_select",
      #|"placeholder":{"type":"plain_text","text":"Select a conversation"}},
      #|"label":{"type":"plain_text","text":"Choose the conversation to publish your result to:"}}]}
    ),
  )
  guard without[0] is Input(b) else { fail("expected an input") }
  guard b.element is Some(Select(sb)) else { fail("expected a select") }
  assert_eq(sb.focus_on_load, None)
}

///|
/// java `parseVideoBlocks`. Ten fields, most of them optional, which makes it
/// the block where a dropped field is easiest to miss.
test "a video block" {
  let parsed = message_blocks(
    (
      #|{"blocks":[{"type":"video","block_id":"bid",
      #|"title":{"type":"plain_text","text":"How to use Slack.","emoji":true},
      #|"title_url":"https://www.youtube.com/watch?v=RRxQQxiM7AA",
      #|"description":{"type":"plain_text","text":"Slack is a new way to communicate with your team.","emoji":true},
      #|"video_url":"https://www.youtube.com/embed/RRxQQxiM7AA?feature=oembed&autoplay=1",
      #|"alt_text":"How to use Slack?",
      #|"thumbnail_url":"https://i.ytimg.com/vi/RRxQQxiM7AA/hqdefault.jpg",
      #|"author_name":"Arcado Buendia","provider_name":"YouTube",
      #|"provider_icon_url":"https://a.slack-edge.com/80588/img/unfurl_icons/youtube.png"}]}
    ),
  )
  guard parsed[0] is Video(b) else { fail("expected a video block") }
  assert_eq(b.block_id, Some("bid"))
  assert_eq(b.alt_text, Some("How to use Slack?"))
  assert_eq(b.author_name, Some("Arcado Buendia"))
  assert_eq(b.provider_name, Some("YouTube"))
  assert_eq(b.title.unwrap().text, "How to use Slack.")
  assert_eq(b.description.unwrap().emoji, Some(true))
  assert_eq(b.title_url, Some("https://www.youtube.com/watch?v=RRxQQxiM7AA"))
}

///|
/// java `rich_text_color_code`: a colour swatch between two text runs.
test "a rich text colour swatch" {
  let parsed = message_blocks(
    (
      #|{"blocks":[{"type":"rich_text","block_id":"d77H","elements":[
      #|{"type":"rich_text_section","elements":[
      #|{"type":"text","text":"Hello\n\n"},{"type":"color","value":"#FFFFFF"},
      #|{"type":"text","text":"\n\n"},{"type":"emoji","name":"wave"}]}]}]}
    ),
  )
  guard parsed[0] is RichText(b) else { fail("expected rich_text") }
  guard b.elements is Some([Section(elements=items, ..)]) else {
    fail("expected one section")
  }
  assert_eq(items.length(), 4)
  guard items[1] is Color(value~, ..) else { fail("expected a colour item") }
  assert_eq(value, Some("#FFFFFF"))
  guard items[3] is Emoji(name~, ..) else { fail("expected an emoji") }
  assert_eq(name, Some("wave"))
}

///|
/// java `testRichTextSkinToneEmoji` and `richText_emoji_with_style`.
///
/// `skin_tone` is an integer beside `name`, and `unicode` is the resolved code
/// point that Slack sends for standard emoji and omits for custom ones.
test "a rich text emoji with a skin tone and a style" {
  let parsed = message_blocks(
    (
      #|{"blocks":[{"type":"rich_text","elements":[{"type":"rich_text_section","elements":[
      #|{"type":"emoji","name":"wave","unicode":"1f44b-1f3fb","skin_tone":2,"style":{"bold":true}}]}]}]}
    ),
  )
  guard parsed[0] is RichText(b) else { fail("expected rich_text") }
  guard b.elements is Some([Section(elements=items, ..)]) else {
    fail("expected one section")
  }
  guard items[0] is Emoji(name~, unicode~, skin_tone~, style~, ..) else {
    fail("expected an emoji")
  }
  assert_eq(name, Some("wave"))
  assert_eq(unicode, Some("1f44b-1f3fb"))
  assert_eq(skin_tone, Some(2))
  assert_eq(style.unwrap().bold, Some(true))
}

///|
/// java `parseCallBlock`. The `call` payload belongs to the Calls API rather
/// than to Block Kit -- nested participant lists, eleven icon sizes -- so it is
/// kept raw, and the round trip is what proves that costs nothing.
test "a call block keeps its call payload verbatim" {
  let block = round_trip(
    (
      #|{"type":"call","call_id":"R111","block_id":"hH9L","api_decoration_available":false,
      #|"call":{"v1":{"id":"R111","app_id":"A111","date_start":1596711312,
      #|"active_participants":[{"external_id":"anon-111","display_name":"anonymous user 1"},{"slack_id":"USLACKBOT"}],
      #|"display_id":"ext-display-id-111","join_url":"https://www.example.com/"}}}
    ),
  )
  guard block is Call(b) else { fail("expected a call block") }
  assert_eq(b.call_id, Some("R111"))
  assert_eq(b.api_decoration_available, Some(false))
  guard b.call is Some(Object(call)) else { fail("expected a call payload") }
  assert_true(call.get("v1") is Some(_))
}

///|
/// java `parseInputOnes`: every input element in one modal.
test "input blocks with each element family" {
  let parsed = message_blocks(
    (
      #|{"blocks":[
      #|{"type":"input","label":{"type":"plain_text","text":"Text"},
      #|"element":{"type":"plain_text_input","action_id":"t","multiline":true,"min_length":1,"max_length":100},
      #|"hint":{"type":"plain_text","text":"A hint"},"optional":true},
      #|{"type":"input","label":{"type":"plain_text","text":"Date"},
      #|"element":{"type":"datepicker","action_id":"d","initial_date":"1990-04-28"}},
      #|{"type":"input","label":{"type":"plain_text","text":"When"},
      #|"element":{"type":"datetimepicker","action_id":"dt","initial_date_time":1628633820}},
      #|{"type":"input","label":{"type":"plain_text","text":"Radio"},
      #|"element":{"type":"radio_buttons","action_id":"r","options":[
      #|{"text":{"type":"plain_text","text":"One"},"value":"1"}]}}]}
    ),
  )
  assert_eq(parsed.length(), 4)
  guard parsed[0] is Input(text_input) else { fail("expected an input") }
  assert_eq(text_input.optional, Some(true))
  assert_eq(text_input.hint.unwrap().text, "A hint")
  guard text_input.element is Some(PlainTextInput(pti)) else {
    fail("expected a plain_text_input")
  }
  assert_eq(pti.multiline, Some(true))
  assert_eq(pti.min_length, Some(1))
  assert_eq(pti.max_length, Some(100))
  guard parsed[1] is Input(date) else { fail("expected an input") }
  guard date.element is Some(Picker(dp)) else { fail("expected a datepicker") }
  assert_eq(dp.kind, Date)
  assert_eq(dp.initial_date, Some("1990-04-28"))
  guard parsed[2] is Input(when_) else { fail("expected an input") }
  guard when_.element is Some(Picker(dtp)) else {
    fail("expected a datetimepicker")
  }
  assert_eq(dtp.kind, DateTime)
  assert_eq(dtp.initial_date_time, Some(1628633820))
  guard parsed[3] is Input(radio) else { fail("expected an input") }
  guard radio.element is Some(Options(opts)) else { fail("expected radios") }
  assert_eq(opts.kind, RadioButtons)
}

///|
/// java `parseMultiSelectOnes`: option groups, which only the static and
/// external menus support.
test "a multi static select with option groups" {
  let block = round_trip(
    (
      #|{"type":"section","text":{"type":"mrkdwn","text":"Pick items"},
      #|"accessory":{"type":"multi_static_select","action_id":"m","max_selected_items":3,
      #|"placeholder":{"type":"plain_text","text":"Select items"},
      #|"option_groups":[{"label":{"type":"plain_text","text":"Group 1"},
      #|"options":[{"text":{"type":"plain_text","text":"One"},"value":"1"},
      #|{"text":{"type":"plain_text","text":"Two"},"value":"2"}]}]}}
    ),
  )
  guard block is Section(b) else { fail("expected a section") }
  guard b.accessory is Some(Select(select)) else { fail("expected a select") }
  assert_eq(select.kind, MultiStatic)
  assert_eq(select.max_selected_items, Some(3))
  guard select.option_groups is Some([group]) else {
    fail("expected one option group")
  }
  assert_eq(group.label.text, "Group 1")
  assert_eq(group.options.length(), 2)
  // `options` and `option_groups` are alternatives; only one is present.
  assert_eq(select.options, None)
}

///|
/// java `parseRichTextOnes`: nested lists, the case a flat rich-text model gets
/// wrong. A list's elements are sections, and a section's elements are items.
test "nested rich text lists" {
  let block = round_trip(
    (
      #|{"type":"rich_text","elements":[
      #|{"type":"rich_text_list","style":"ordered","indent":0,"offset":0,"border":0,"elements":[
      #|{"type":"rich_text_section","elements":[{"type":"text","text":"outer"}]}]},
      #|{"type":"rich_text_list","style":"bullet","indent":1,"elements":[
      #|{"type":"rich_text_section","elements":[{"type":"text","text":"inner"}]}]}]}
    ),
  )
  guard block is RichText(b) else { fail("expected rich_text") }
  guard b.elements is Some(sections) else { fail("expected sections") }
  assert_eq(sections.length(), 2)
  guard sections[0] is List(style~, indent~, offset~, border~, ..) else {
    fail("expected a list")
  }
  assert_eq(style, Some("ordered"))
  assert_eq(indent, Some(0))
  assert_eq(offset, Some(0))
  assert_eq(border, Some(0))
  guard sections[1] is List(style=inner_style, indent=inner_indent, ..) else {
    fail("expected a list")
  }
  assert_eq(inner_style, Some("bullet"))
  assert_eq(inner_indent, Some(1))
}

///|
/// The builders produce what Slack expects, and nothing more: an unset option
/// is an absent key, never an explicit null.
test "builders emit only the fields they were given" {
  assert_eq(@blocks.section_text("hello").to_json(), {
    "type": "section",
    "text": { "type": "mrkdwn", "text": "hello" },
  })
  assert_eq(@blocks.divider().to_json(), { "type": "divider" })
  assert_eq(@blocks.header("Title").to_json(), {
    "type": "header",
    "text": { "type": "plain_text", "text": "Title" },
  })
  assert_eq(@blocks.button("Click", action_id="a", value="v").to_json(), {
    "type": "button",
    "text": { "type": "plain_text", "text": "Click" },
    "action_id": "a",
    "value": "v",
  })
  assert_eq(@blocks.image("https://example.com/a.png", "a picture").to_json(), {
    "type": "image",
    "image_url": "https://example.com/a.png",
    "alt_text": "a picture",
  })
}

///|
/// A built block list survives the trip through JSON unchanged, which is the
/// property that lets a caller build, send, read back and compare.
test "built blocks round-trip" {
  let built = [
    @blocks.header("Report"),
    @blocks.section_text("*Revenue* is up"),
    @blocks.divider(),
    @blocks.actions([
      @blocks.button("Approve", action_id="approve", style="primary"),
      @blocks.button("Deny", action_id="deny", style="danger"),
    ]),
    @blocks.context([@blocks.context_text("Updated just now")]),
  ]
  let json = @blocks.blocks_to_json(built)
  guard @blocks.parse_blocks(json) is Some(reparsed) else {
    fail("expected the built blocks to parse")
  }
  assert_eq(reparsed, built)
  assert_eq(@blocks.blocks_to_json(reparsed), json)
}
