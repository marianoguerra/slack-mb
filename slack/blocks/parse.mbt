// The entry points.

///|
/// Parse a `blocks` array.
///
/// Under `Lenient` -- the default -- this never fails: anything unmodelled
/// becomes an `Unknown` variant carrying its original JSON, which renders as
/// nothing but round-trips exactly. Under `Strict` the first unmodelled thing
/// raises, naming it.
///
/// A value that is not an array is not "no blocks", it is a caller mistake, so
/// it is `None` rather than an empty list.
pub fn parse_blocks(
  j : Json,
  policy? : UnknownPolicy = Lenient,
) -> Array[LayoutBlock]? raise BlockParseError {
  guard j is Array(items) else { return None }
  let blocks = items.map(LayoutBlock::from_json)
  if policy is Strict {
    for block in blocks {
      block.validate()
    }
  }
  Some(blocks)
}

///|
/// Parse the `blocks` field of a message, view or payload object.
///
/// `None` when there is no `blocks` field at all, which is different from an
/// empty one -- see the `blocks: []` case in @api's form encoder.
pub fn parse_message_blocks(
  message : Json,
  policy? : UnknownPolicy = Lenient,
) -> Array[LayoutBlock]? raise BlockParseError {
  guard message is Object(o) else { return None }
  guard o.get("blocks") is Some(blocks) else { return None }
  parse_blocks(blocks, policy~)
}

///|
/// Serialise a block list, ready for `Params::put_json("blocks", ...)`.
pub fn blocks_to_json(blocks : Array[LayoutBlock]) -> Json {
  Json::array(blocks.map(LayoutBlock::to_json))
}

///|
/// Raise on the first unmodelled thing in a block list.
pub fn validate_blocks(
  blocks : Array[LayoutBlock],
) -> Unit raise BlockParseError {
  for block in blocks {
    block.validate()
  }
}

///|
/// Every block type name this version models. For tests, and for anyone
/// checking what a payload will survive.
pub let known_block_types : Array[String] = [
  "actions", "call", "context", "divider", "file", "header", "image", "input", "markdown",
  "rich_text", "section", "video",
]

///|
/// Every element type name this version models.
pub let known_element_types : Array[String] = [
  "button", "channels_select", "checkboxes", "conversations_select", "datepicker",
  "datetimepicker", "external_select", "image", "mrkdwn", "multi_channels_select",
  "multi_conversations_select", "multi_external_select", "multi_static_select", "multi_users_select",
  "overflow", "plain_text", "plain_text_input", "radio_buttons", "rich_text_input",
  "static_select", "timepicker", "users_select", "workflow_button",
]
