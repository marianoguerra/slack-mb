// Text objects: the leaves of Block Kit.
//
// https://docs.slack.dev/reference/block-kit/composition-objects/text-object

///|
/// Which kind of text object this is.
///
/// `Other` exists so that an unrecognised text type is representable rather
/// than silently dropped. java-slack-sdk raises on one immediately; here it is
/// parsed, kept, and raised on by `validate` under `Strict` -- which round-trips
/// and still refuses when refusing is what you asked for.
pub(all) enum TextKind {
  PlainText
  Mrkdwn
  Other(String)
} derive(Eq, Debug)

///|
pub fn TextKind::type_name(self : Self) -> String {
  match self {
    PlainText => "plain_text"
    Mrkdwn => "mrkdwn"
    Other(t) => t
  }
}

///|
pub fn TextKind::of_name(name : String) -> TextKind {
  match name {
    "plain_text" => PlainText
    "mrkdwn" => Mrkdwn
    other => Other(other)
  }
}

///|
/// A `plain_text` or `mrkdwn` text object.
///
/// One struct with a kind rather than two variants: the two differ only in
/// which of `emoji` and `verbatim` is meaningful, the schema accepts either
/// wherever text is allowed, and code that handles "some text" would otherwise
/// have to match twice everywhere.
pub(all) struct TextObject {
  kind : TextKind
  text : String
  /// `plain_text` only: render `:emoji:` shortcodes as emoji.
  emoji : Bool?
  /// `mrkdwn` only: skip Slack's automatic link, channel and user detection.
  verbatim : Bool?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn TextObject::plain(text : String, emoji? : Bool) -> TextObject {
  { kind: PlainText, text, emoji, verbatim: None, extra: Map([]) }
}

///|
pub fn TextObject::mrkdwn(text : String, verbatim? : Bool) -> TextObject {
  { kind: Mrkdwn, text, emoji: None, verbatim, extra: Map([]) }
}

///|
pub fn TextObject::type_name(self : Self) -> String {
  self.kind.type_name()
}

///|
/// `None` when this is not a text object at all: not an object, or with no
/// `type` or no `text` string.
///
/// An unknown `type` is NOT a reason to refuse -- that is what `Other` is for.
/// An empty `type` or an empty `text` is not a reason either: Slack's own
/// scrubbed fixtures contain both, and a parser that refused them could not
/// read the corpus it is validated against.
pub fn TextObject::from_json(j : Json) -> TextObject? {
  guard j is Object(o) else { return None }
  let rest = fields_of(o)
  guard take_str(rest, "type") is Some(type_name) else { return None }
  guard take_str(rest, "text") is Some(text) else { return None }
  Some({
    kind: TextKind::of_name(type_name),
    text,
    emoji: take_bool(rest, "emoji"),
    verbatim: take_bool(rest, "verbatim"),
    extra: rest,
  })
}

///|
pub fn TextObject::to_json(self : Self) -> Json {
  let o = out_of(self.type_name())
  o["text"] = Json::string(self.text)
  put_bool(o, "emoji", self.emoji)
  put_bool(o, "verbatim", self.verbatim)
  merge_extra(o, self.extra)
}

///|
/// Raise if this text object's type is one Slack does not define.
pub fn TextObject::validate(self : Self) -> Unit raise BlockParseError {
  if self.kind is Other(t) {
    raise UnknownTextObject(t)
  }
}
