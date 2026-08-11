// The two takers the generator cannot write itself, and the rule they follow.
//
// Both delegate to @blocks, which already models this ground. A message's
// `blocks` are the same Block Kit this library sends, so parsing them into
// `Array[LayoutBlock]` rather than leaving them as `Json` is most of the reason
// this package exists.

///|
/// Block Kit, leniently.
///
/// `parse_blocks` is total under its default policy -- an unrecognised type
/// becomes an `Unknown*` variant carrying the original JSON, so a bot does not
/// break because a coworker used a block released last Tuesday. The `catch`
/// covers the strict path's error type, which this call cannot reach; if it
/// ever did, the key would stay in `extra` and still round-trip.
fn take_blocks(
  rest : Map[String, Json],
  key : String,
) -> Array[@blocks.LayoutBlock]? {
  @jsonx.take_obj(rest, key, j => @blocks.parse_blocks(j) catch { _ => None })
}

///|
/// A `plain_text` or `mrkdwn` object, as a view's title, submit and close are.
fn take_text(rest : Map[String, Json], key : String) -> @blocks.TextObject? {
  @jsonx.take_obj(rest, key, @blocks.TextObject::from_json)
}
