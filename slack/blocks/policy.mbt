// What happens when Slack sends something this version does not model.
//
// Parsing is TOTAL: `parse_blocks` never fails, and anything unrecognised
// becomes an `Unknown*` variant that carries the original JSON. Strictness is a
// separate walk over the result, so there is exactly one parser rather than a
// lenient one and a strict one that can drift apart.
//
// That split is also what makes the round-trip property testable: a strict
// parser would refuse the very payloads the corpus is full of, so the property
// could only ever be checked on the lenient path.

///|
/// What to do with a `"type"` this version does not model.
///
/// Slack ships new block types faster than any SDK adopts them, and a bot that
/// breaks because a coworker used a block released last Tuesday is a worse
/// outcome than one that renders it as an opaque payload. So the default is
/// lenient, and strict is opt-in for the cases where refusing is the point: a
/// linter, a test, a validating endpoint.
///
/// java-slack-sdk offers the same choice as
/// `createSnakeCaseWithoutUnknownPropertyDetection(true|false)`, and its
/// BlockKitTest tests every unknown-type payload twice, once per policy. So
/// does unknown_test.mbt here.
pub(all) enum UnknownPolicy {
  Lenient
  Strict
} derive(Eq, Debug)

///|
/// Why a strict parse refused a payload.
///
/// The message text is java-slack-sdk's, verbatim, so its BlockKitTest
/// assertions port literally and so that an operator who has seen one SDK's
/// message recognises the other's.
pub(all) suberror BlockParseError {
  UnsupportedLayoutBlock(String)
  UnknownBlockElement(String)
  UnknownContextBlockElement(String)
  UnknownTextObject(String)
  UnknownRichTextElement(String)
} derive(Eq, Debug)

///|
pub impl Show for BlockParseError with fn output(self, logger) {
  logger.write_string(self.describe_error())
}

///|
pub fn BlockParseError::describe_error(self : Self) -> String {
  match self {
    UnsupportedLayoutBlock(t) => "Unsupported layout block type: \{t}"
    UnknownBlockElement(t) => "Unknown block element type: \{t}"
    UnknownContextBlockElement(t) => "Unknown context block element type: \{t}"
    UnknownTextObject(t) => "Unknown text object type: \{t}"
    UnknownRichTextElement(t) => "Unknown rich text element type: \{t}"
  }
}

///|
/// The `type` field of a JSON value, for error messages and dispatch.
///
/// `""` when there is none -- which is not only a missing-field case: Slack's
/// scrubbed fixtures contain literal `"type": ""`, so the empty string is real
/// data and not a sentinel.
fn type_tag_of(j : Json) -> String {
  match j {
    Object(o) =>
      match o.get("type") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}
