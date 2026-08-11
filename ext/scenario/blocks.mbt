// The message the scenario posts.

///|
/// The message this harness posts.
///
/// Deliberately varied: a header, a section with fields, a context line, an
/// actions row with two buttons and a divider. Between them they exercise
/// plain_text, mrkdwn, nested elements and the `style` field -- and they are
/// what gets read back and round-tripped.
pub fn test_blocks() -> Array[@blocks.LayoutBlock] {
  [
    @blocks.header("slack-mb integration test"),
    @blocks.section(
      text=@blocks.TextObject::mrkdwn("Posted by the MoonBit client."),
      fields=[
        @blocks.TextObject::mrkdwn("*Encoder*\nchecked against Slack"),
        @blocks.TextObject::mrkdwn("*Blocks*\nround-tripped"),
      ],
    ),
    @blocks.divider(),
    @blocks.actions([
      @blocks.button(
        "Primary",
        action_id="probe_primary",
        style="primary",
        value="1",
      ),
      @blocks.button(
        "Danger",
        action_id="probe_danger",
        style="danger",
        value="2",
      ),
    ]),
    @blocks.context([
      @blocks.context_text("This message deletes itself. :wave:"),
    ]),
  ]
}
