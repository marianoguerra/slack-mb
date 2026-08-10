// Ported from slack-morphism's `src/models/blocks/kit.rs` `mod test`.
//
// Its fixtures are embedded as raw strings rather than read from
// ext/fixtures/morphism/: they total under 6 KB, and embedding them is what
// keeps this package free of filesystem access and therefore buildable on every
// backend. The corpus tests in ext/ are where file reading belongs.
//
// Every test here is a round trip. morphism's are too -- `serde_json` gives it
// them for free -- and they are the assertions that catch a model quietly
// dropping a field, which "does it parse" never will.

///|
fn parse(text : String) -> Json {
  @json.parse(text) catch {
    _ => abort("bad JSON in test data: \{text}")
  }
}

///|
/// Parse a single block, round-trip it, and return the parsed form.
fn round_trip(text : String) -> @blocks.LayoutBlock raise {
  let json = parse(text)
  let block = @blocks.LayoutBlock::from_json(json)
  assert_eq(block.to_json(), json, msg="round trip changed the payload")
  block
}

///|
/// morphism `slack_rich_text_block.json`: every rich-text item type and all
/// four section types in one block.
test "a rich text block with every item type" {
  let block = round_trip(
    (
      #|{"type":"rich_text","block_id":"test_block","elements":[
      #|{"type":"rich_text_section","elements":[
      #|{"type":"text","text":"Hello ","style":{"bold":true}},
      #|{"type":"user","user_id":"U123ABC456"},
      #|{"type":"text","text":"! Check out "},
      #|{"type":"link","url":"https://example.com","text":"this link","style":{"italic":true}},
      #|{"type":"emoji","name":"wave"},
      #|{"type":"channel","channel_id":"C123ABC456"},
      #|{"type":"broadcast","range":"here"}]},
      #|{"type":"rich_text_list","style":"bullet","indent":0,"elements":[
      #|{"type":"rich_text_section","elements":[{"type":"text","text":"Item one"}]},
      #|{"type":"rich_text_section","elements":[{"type":"text","text":"Item two"}]}]},
      #|{"type":"rich_text_preformatted","elements":[{"type":"text","text":"fn main() {}\n"}],"border":1},
      #|{"type":"rich_text_quote","elements":[{"type":"text","text":"A wise quote","style":{"italic":true}}]}]}
    ),
  )
  guard block is RichText(b) else { fail("expected a rich_text block") }
  assert_eq(b.block_id, Some("test_block"))
  guard b.elements is Some(sections) else { fail("expected sections") }
  assert_eq(sections.length(), 4)

  // The first section: seven items, with styles and mentions intact.
  guard sections[0] is Section(elements=items, ..) else {
    fail("expected a rich_text_section first")
  }
  assert_eq(items.length(), 7)
  guard items[0] is Text(text~, style~, ..) else { fail("expected a text run") }
  assert_eq(text, Some("Hello "))
  assert_eq(style.unwrap().bold, Some(true))
  guard items[1] is User(user_id~, ..) else { fail("expected a user mention") }
  assert_eq(user_id, Some("U123ABC456"))
  guard items[6] is Broadcast(range~, ..) else { fail("expected a broadcast") }
  assert_eq(range, Some("here"))

  // The list nests sections inside sections -- the part a flat model gets wrong.
  guard sections[1] is List(style~, indent~, elements=list_items, ..) else {
    fail("expected a rich_text_list")
  }
  assert_eq(style, Some("bullet"))
  assert_eq(indent, Some(0))
  assert_eq(list_items.length(), 2)
  guard list_items[0] is Section(..) else {
    fail("a list's elements are sections, not items")
  }
  guard sections[2] is Preformatted(border~, ..) else {
    fail("expected rich_text_preformatted")
  }
  assert_eq(border, Some(1))
  guard sections[3] is Quote(..) else { fail("expected rich_text_quote") }
}

///|
/// morphism `test_conversation_filter_roundtrip` and
/// `slack_conversations_select_with_filter.json`.
test "a conversations select with a filter" {
  let block = round_trip(
    (
      #|{"type":"section","text":{"type":"plain_text","text":"Pick a channel"},
      #|"accessory":{"type":"conversations_select","action_id":"channel_select",
      #|"placeholder":{"type":"plain_text","text":"Select a channel"},
      #|"filter":{"include":["public","private"],"exclude_external_shared_channels":true,"exclude_bot_users":true}}}
    ),
  )
  guard block is Section(b) else { fail("expected a section") }
  guard b.accessory is Some(Select(select)) else {
    fail("expected a select accessory")
  }
  assert_eq(select.kind, Conversations)
  assert_eq(select.action_id, Some("channel_select"))
  guard select.filter is Some(filter) else { fail("expected a filter") }
  assert_eq(filter.include_, Some(["public", "private"]))
  assert_eq(filter.exclude_external_shared_channels, Some(true))
  assert_eq(filter.exclude_bot_users, Some(true))
}

///|
/// morphism `test_conversation_filter_none_omitted`.
///
/// An absent filter must not serialise as `"filter": {}`. Slack reads an empty
/// filter as "offer nothing", so the difference between omitting the field and
/// sending an empty object is the difference between a working menu and an
/// empty one.
test "an absent filter is omitted, not sent as an empty object" {
  let element = @blocks.conversations_select(action_id="c")
  let json = element.to_json()
  guard json is Object(o) else { fail("expected an object") }
  assert_eq(o.get("filter"), None)
  assert_eq(o.get("placeholder"), None)
  assert_eq(o.get("initial_conversation"), None)
  // Only the two fields actually set.
  assert_eq(o.length(), 2)
  assert_eq(o.get("type"), Some(Json::string("conversations_select")))
}

///|
/// morphism's exact-JSON assertion for the filter object.
test "a filter serialises to exactly its set fields" {
  let filter = @blocks.ConversationFilterObject::new(
    include_=["im", "mpim"],
    exclude_bot_users=true,
  )
  assert_eq(filter.to_json(), {
    "include": ["im", "mpim"],
    "exclude_bot_users": true,
  })
}

///|
/// morphism `slack_image_blocks.json`: an image accessory, an image block with
/// an `image_url`, and an image block with a `slack_file` instead.
test "image blocks in all three shapes" {
  let json = parse(
    (
      #|{"blocks":[
      #|{"type":"section","text":{"type":"mrkdwn","text":"*Farmhouse Cuisine*"},
      #|"accessory":{"type":"image","image_url":"https://example.com/o.jpg","alt_text":"alt text for image"}},
      #|{"type":"image","title":{"type":"plain_text","text":"I don't love tacos","emoji":true},
      #|"image_url":"https://example.com/tacos.jpg","alt_text":"not so delicious tacos"},
      #|{"type":"image","title":{"type":"plain_text","text":"I love tacos","emoji":true},
      #|"slack_file":{"id":"F00000000"},"alt_text":"delicious tacos"}]}
    ),
  )
  guard @blocks.parse_message_blocks(json) is Some(parsed) else {
    fail("expected blocks")
  }
  assert_eq(parsed.length(), 3)
  assert_eq(@blocks.blocks_to_json(parsed), parse_blocks_field(json))
  guard parsed[0] is Section(s) else { fail("expected a section") }
  guard s.accessory is Some(Image(acc)) else {
    fail("expected an image accessory")
  }
  assert_eq(acc.alt_text, Some("alt text for image"))
  guard parsed[1] is Image(b1) else { fail("expected an image block") }
  assert_eq(b1.image_url, Some("https://example.com/tacos.jpg"))
  assert_eq(b1.title.unwrap().emoji, Some(true))
  // The `slack_file` alternative to `image_url`.
  guard parsed[2] is Image(b2) else { fail("expected an image block") }
  assert_eq(b2.image_url, None)
  assert_eq(b2.slack_file.unwrap().id, Some("F00000000"))
}

///|
fn parse_blocks_field(message : Json) -> Json {
  guard message is Object(o) && o.get("blocks") is Some(blocks) else {
    abort("no blocks field")
  }
  blocks
}

///|
/// morphism `slack_home_view.json`.
test "a home view's blocks" {
  let json = parse(
    (
      #|{"blocks":[{"type":"rich_text","block_id":"test-block-id","elements":[
      #|{"type":"rich_text_section","elements":[{"type":"text","text":"hi!"}]}]}],
      #|"private_metadata":"","callback_id":"test-callback-id"}
    ),
  )
  guard @blocks.parse_message_blocks(json) is Some(parsed) else {
    fail("expected blocks")
  }
  assert_eq(parsed.length(), 1)
  assert_eq(parsed[0].block_id(), Some("test-block-id"))
  assert_eq(@blocks.blocks_to_json(parsed), parse_blocks_field(json))
}

///|
/// morphism `slack_workflow_button.json`. The `workflow` object's shape is
/// defined by the workflow itself -- `customizable_input_parameters` is a list
/// whose keys the workflow author chose -- so it is kept raw, and the round
/// trip is what proves nothing was lost.
test "a workflow button keeps its trigger verbatim" {
  let block = round_trip(
    (
      #|{"type":"actions","block_id":"workflow_actions","elements":[
      #|{"type":"workflow_button","action_id":"start_workflow",
      #|"text":{"type":"plain_text","text":"Start Workflow"},
      #|"workflow":{"trigger":{"url":"https://slack.com/shortcuts/Ft0ABC123/xyz",
      #|"customizable_input_parameters":[{"name":"user_input","value":"hello"}]}},
      #|"style":"primary"}]}
    ),
  )
  guard block is Actions(b) else { fail("expected an actions block") }
  guard b.elements is Some([WorkflowButton(wb)]) else {
    fail("expected one workflow_button")
  }
  assert_eq(wb.action_id, Some("start_workflow"))
  assert_eq(wb.style, Some("primary"))
  guard wb.workflow is Some(Object(w)) else {
    fail("expected a workflow object")
  }
  assert_true(w.get("trigger") is Some(_))
}

///|
/// morphism `slack_alert_block.json`.
test "an alert block" {
  let block = round_trip(
    (
      #|{"type":"alert","block_id":"alert_block_1","text":{"type":"mrkdwn","text":"Your disk is almost full."},"level":"warning"}
    ),
  )
  guard block is Alert(b) else { fail("expected an alert block") }
  assert_eq(b.level, Some("warning"))
  assert_eq(b.text.unwrap().kind, Mrkdwn)
}

///|
/// morphism `slack_card_block.json`.
test "a card block" {
  let block = round_trip(
    (
      #|{"type":"card","block_id":"card_block_1","title":{"type":"mrkdwn","text":"My Card"},
      #|"subtitle":{"type":"mrkdwn","text":"A short subtitle."},
      #|"body":{"type":"mrkdwn","text":"A short description of the card."},
      #|"hero_image":{"type":"image","image_url":"https://example.com/hero.png","alt_text":"hero image"},
      #|"actions":[{"type":"button","action_id":"card_action_1","text":{"type":"plain_text","text":"Open"},"style":"primary","value":"open"}]}
    ),
  )
  guard block is Card(b) else { fail("expected a card block") }
  assert_eq(b.title.unwrap().text, "My Card")
  guard b.hero_image is Some(Image(hero)) else { fail("expected a hero image") }
  assert_eq(hero.alt_text, Some("hero image"))
  guard b.actions is Some([Button(button)]) else { fail("expected one button") }
  assert_eq(button.value, Some("open"))
}

///|
/// morphism `slack_context_actions_block.json`. Its `icon_button` element is
/// not in the Block Kit reference, so it lands in `Unknown` -- and the round
/// trip proves that costs nothing.
test "a context_actions block keeps an unmodelled element intact" {
  let block = round_trip(
    (
      #|{"type":"context_actions","block_id":"context_actions_1","elements":[
      #|{"type":"icon_button","action_id":"delete_action","icon":"trash",
      #|"text":{"type":"plain_text","text":"Delete"},"value":"delete_item"}]}
    ),
  )
  guard block is ContextActions(b) else { fail("expected context_actions") }
  guard b.elements is Some([element]) else { fail("expected one element") }
  guard element is Unknown(type_=t, ..) else {
    fail("icon_button is not modelled, so it should be Unknown")
  }
  assert_eq(t, "icon_button")
}

///|
/// morphism `slack_table_block.json`. `rows` stays raw JSON because a cell is
/// either a `raw_text` or a `rich_text` and the shape is not in the Block Kit
/// reference -- modelling it from one fixture would be guessing.
test "a table block keeps its rows verbatim" {
  let block = round_trip(
    (
      #|{"type":"table","block_id":"table_block_1",
      #|"column_settings":[{"is_wrapped":true},{"align":"right"}],
      #|"rows":[[{"type":"raw_text","text":"Header A"},{"type":"raw_text","text":"Header B"}],
      #|[{"type":"raw_text","text":"Data 1A"},{"type":"rich_text","elements":[
      #|{"type":"rich_text_section","elements":[{"type":"link","url":"https://slack.com","text":"Data 1B"}]}]}]]}
    ),
  )
  guard block is Table(b) else { fail("expected a table block") }
  guard b.rows is Some(Array(rows)) else { fail("expected rows") }
  assert_eq(rows.length(), 2)
  guard b.column_settings is Some(Array(settings)) else {
    fail("expected column settings")
  }
  assert_eq(settings.length(), 2)
}

///|
/// morphism `slack_task_card_block.json`. Note `title` is a bare string here,
/// unlike every other title in Block Kit -- which is exactly the sort of thing
/// a hand-written model gets wrong and a round trip catches.
test "a task_card block" {
  let block = round_trip(
    (
      #|{"type":"task_card","task_id":"task_1","title":"Fetching weather data",
      #|"block_id":"task_card_block_1","status":"in_progress",
      #|"output":{"type":"rich_text","elements":[{"type":"rich_text_section","elements":[
      #|{"type":"text","text":"Found weather data for Chicago from 2 sources"}]}]},
      #|"sources":[{"type":"url","url":"https://weather.com/","text":"weather.com"}]}
    ),
  )
  guard block is TaskCard(b) else { fail("expected a task_card block") }
  assert_eq(b.task_id, Some("task_1"))
  assert_eq(b.title, Some("Fetching weather data"))
  assert_eq(b.status, Some("in_progress"))
  assert_true(b.output is Some(_))
  assert_true(b.sources is Some(_))
}

///|
/// morphism's `emoji.rs` deserialize tests: a URL with escaped slashes, which
/// is how Slack's own encoder writes them. If the JSON parser mishandled `\/`
/// the emoji URL would come back with backslashes in it.
test "escaped slashes in a JSON string decode to plain slashes" {
  let json = parse(
    (
      #|{"type":"image","image_url":"https:\/\/emoji.slack-edge.com\/test_emoji.png","alt_text":"e"}
    ),
  )
  let element = @blocks.BlockElement::from_json(json)
  guard element is Image(image) else { fail("expected an image element") }
  assert_eq(
    image.image_url,
    Some("https://emoji.slack-edge.com/test_emoji.png"),
  )
  // ...and writing it back does NOT re-escape them, matching every reference SDK.
  assert_eq(
    element.to_json().stringify(),
    (
      #|{"type":"image","image_url":"https://emoji.slack-edge.com/test_emoji.png","alt_text":"e"}
    ),
  )
}
