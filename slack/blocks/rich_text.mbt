// Rich text: the structured form of what a person typed in the composer.
//
// https://docs.slack.dev/reference/block-kit/blocks/rich-text-block
//
// This is the only part of Block Kit that is a tree rather than a list, and it
// is by far the most common thing in real message payloads -- Slack rewrites
// every ordinary message into one. Two levels: a `rich_text` block holds
// *sections* (a paragraph, a list, a quote, a code block), and each section
// holds *items* (a run of text, a mention, an emoji, a link).
//
// Both levels get their own `Unknown` variant. A single flat model would have
// to guess which level an unrecognised type belonged to, and the two report
// differently in a strict parse.

///|
/// Character styling on a run of text.
///
/// `highlight`, `client_highlight` and `unlink` only appear on mentions -- they
/// are how Slack marks a mention of you, specifically -- but they live here
/// rather than in a second struct because Slack sends them in the same `style`
/// object.
pub(all) struct RichTextStyle {
  bold : Bool?
  italic : Bool?
  strike : Bool?
  code : Bool?
  highlight : Bool?
  client_highlight : Bool?
  unlink : Bool?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn RichTextStyle::from_json(j : Json) -> RichTextStyle? {
  guard j is Object(o) else { return None }
  let rest = fields_of(o)
  Some({
    bold: take_bool(rest, "bold"),
    italic: take_bool(rest, "italic"),
    strike: take_bool(rest, "strike"),
    code: take_bool(rest, "code"),
    highlight: take_bool(rest, "highlight"),
    client_highlight: take_bool(rest, "client_highlight"),
    unlink: take_bool(rest, "unlink"),
    extra: rest,
  })
}

///|
pub fn RichTextStyle::to_json(self : Self) -> Json {
  let o : Map[String, Json] = Map([])
  put_bool(o, "bold", self.bold)
  put_bool(o, "italic", self.italic)
  put_bool(o, "strike", self.strike)
  put_bool(o, "code", self.code)
  put_bool(o, "highlight", self.highlight)
  put_bool(o, "client_highlight", self.client_highlight)
  put_bool(o, "unlink", self.unlink)
  merge_extra(o, self.extra)
}

///|
/// One run inside a rich-text section.
pub(all) enum RichTextItem {
  /// A run of literal text.
  Text(text~ : String?, style~ : RichTextStyle?, extra~ : Map[String, Json])
  /// A link. `unsafe` marks one Slack will not auto-linkify.
  Link(
    url~ : String?,
    text~ : String?,
    /// Spelled `unsafe_` because `unsafe` is a reserved word. Slack sends
    /// `unsafe`; it marks a link the client will not auto-linkify.
    unsafe_~ : Bool?,
    style~ : RichTextStyle?,
    extra~ : Map[String, Json]
  )
  /// `name` is the shortcode without colons. `unicode` is the code point, which
  /// Slack sends for standard emoji and omits for custom ones; `skin_tone` is
  /// what java-slack-sdk's `testRichTextSkinToneEmoji` exists for.
  Emoji(
    name~ : String?,
    unicode~ : String?,
    skin_tone~ : Int?,
    style~ : RichTextStyle?,
    extra~ : Map[String, Json]
  )
  User(user_id~ : String?, style~ : RichTextStyle?, extra~ : Map[String, Json])
  UserGroup(
    usergroup_id~ : String?,
    style~ : RichTextStyle?,
    extra~ : Map[String, Json]
  )
  Channel(
    channel_id~ : String?,
    style~ : RichTextStyle?,
    extra~ : Map[String, Json]
  )
  Team(team_id~ : String?, style~ : RichTextStyle?, extra~ : Map[String, Json])
  /// `@here`, `@channel`, `@everyone`.
  Broadcast(
    range~ : String?,
    style~ : RichTextStyle?,
    extra~ : Map[String, Json]
  )
  /// A colour swatch, from java-slack-sdk's `rich_text_color_code` test.
  Color(value~ : String?, style~ : RichTextStyle?, extra~ : Map[String, Json])
  /// A rendered timestamp. `format` is Slack's date-format string and
  /// `fallback` is what a client that cannot render it should show.
  Date(
    timestamp~ : Int?,
    format~ : String?,
    url~ : String?,
    fallback~ : String?,
    style~ : RichTextStyle?,
    extra~ : Map[String, Json]
  )
  Unknown(type_~ : String, raw~ : Json)
} derive(Eq, Debug)

///|
pub fn RichTextItem::type_name(self : Self) -> String {
  match self {
    Text(..) => "text"
    Link(..) => "link"
    Emoji(..) => "emoji"
    User(..) => "user"
    UserGroup(..) => "usergroup"
    Channel(..) => "channel"
    Team(..) => "team"
    Broadcast(..) => "broadcast"
    Color(..) => "color"
    Date(..) => "date"
    Unknown(type_=t, ..) => t
  }
}

///|
/// Always succeeds: an unrecognised item becomes `Unknown`.
pub fn RichTextItem::from_json(j : Json) -> RichTextItem {
  let tag = type_tag_of(j)
  guard j is Object(o) else { return Unknown(type_=tag, raw=j) }
  let rest = fields_of(o)
  rest.remove("type")
  let style = take_obj(rest, "style", RichTextStyle::from_json)
  match tag {
    "text" => Text(text=take_str(rest, "text"), style~, extra=rest)
    "link" =>
      Link(
        url=take_str(rest, "url"),
        text=take_str(rest, "text"),
        unsafe_=take_bool(rest, "unsafe"),
        style~,
        extra=rest,
      )
    "emoji" =>
      Emoji(
        name=take_str(rest, "name"),
        unicode=take_str(rest, "unicode"),
        skin_tone=take_int(rest, "skin_tone"),
        style~,
        extra=rest,
      )
    "user" => User(user_id=take_str(rest, "user_id"), style~, extra=rest)
    "usergroup" =>
      UserGroup(usergroup_id=take_str(rest, "usergroup_id"), style~, extra=rest)
    "channel" =>
      Channel(channel_id=take_str(rest, "channel_id"), style~, extra=rest)
    "team" => Team(team_id=take_str(rest, "team_id"), style~, extra=rest)
    "broadcast" => Broadcast(range=take_str(rest, "range"), style~, extra=rest)
    "color" => Color(value=take_str(rest, "value"), style~, extra=rest)
    "date" =>
      Date(
        timestamp=take_int(rest, "timestamp"),
        format=take_str(rest, "format"),
        url=take_str(rest, "url"),
        fallback=take_str(rest, "fallback"),
        style~,
        extra=rest,
      )
    _ => Unknown(type_=tag, raw=j)
  }
}

///|
pub fn RichTextItem::to_json(self : Self) -> Json {
  if self is Unknown(raw~, ..) {
    return raw
  }
  let o = out_of(self.type_name())
  let (style, extra) = match self {
    Text(text~, style~, extra~) => {
      put_str(o, "text", text)
      (style, extra)
    }
    Link(url~, text~, unsafe_~, style~, extra~) => {
      put_str(o, "url", url)
      put_str(o, "text", text)
      put_bool(o, "unsafe", unsafe_)
      (style, extra)
    }
    Emoji(name~, unicode~, skin_tone~, style~, extra~) => {
      put_str(o, "name", name)
      put_str(o, "unicode", unicode)
      put_int(o, "skin_tone", skin_tone)
      (style, extra)
    }
    User(user_id~, style~, extra~) => {
      put_str(o, "user_id", user_id)
      (style, extra)
    }
    UserGroup(usergroup_id~, style~, extra~) => {
      put_str(o, "usergroup_id", usergroup_id)
      (style, extra)
    }
    Channel(channel_id~, style~, extra~) => {
      put_str(o, "channel_id", channel_id)
      (style, extra)
    }
    Team(team_id~, style~, extra~) => {
      put_str(o, "team_id", team_id)
      (style, extra)
    }
    Broadcast(range~, style~, extra~) => {
      put_str(o, "range", range)
      (style, extra)
    }
    Color(value~, style~, extra~) => {
      put_str(o, "value", value)
      (style, extra)
    }
    Date(timestamp~, format~, url~, fallback~, style~, extra~) => {
      put_int(o, "timestamp", timestamp)
      put_str(o, "format", format)
      put_str(o, "url", url)
      put_str(o, "fallback", fallback)
      (style, extra)
    }
    Unknown(..) => (None, Map([]))
  }
  put_obj(o, "style", style, RichTextStyle::to_json)
  merge_extra(o, extra)
}

///|
/// One section of a rich-text block: a paragraph, a list, a quote or a code
/// block.
pub(all) enum RichTextBlockElement {
  /// A paragraph.
  Section(elements~ : Array[RichTextItem], extra~ : Map[String, Json])
  /// A bulleted or ordered list. Its `elements` are *sections*, one per item,
  /// which is what makes rich text a tree.
  List(
    style~ : String?,
    indent~ : Int?,
    offset~ : Int?,
    border~ : Int?,
    elements~ : Array[RichTextBlockElement],
    extra~ : Map[String, Json]
  )
  /// A code block.
  Preformatted(
    border~ : Int?,
    elements~ : Array[RichTextItem],
    extra~ : Map[String, Json]
  )
  Quote(
    border~ : Int?,
    elements~ : Array[RichTextItem],
    extra~ : Map[String, Json]
  )
  Unknown(type_~ : String, raw~ : Json)
} derive(Eq, Debug)

///|
pub fn RichTextBlockElement::type_name(self : Self) -> String {
  match self {
    Section(..) => "rich_text_section"
    List(..) => "rich_text_list"
    Preformatted(..) => "rich_text_preformatted"
    Quote(..) => "rich_text_quote"
    Unknown(type_=t, ..) => t
  }
}

///|
fn items_of(rest : Map[String, Json]) -> Array[RichTextItem] {
  match rest.get("elements") {
    Some(Array(items)) => {
      rest.remove("elements")
      items.map(RichTextItem::from_json)
    }
    // No `elements`, or one that is not an array: leave the key in `rest` so it
    // survives the round trip, and report an empty section.
    _ => []
  }
}

///|
pub fn RichTextBlockElement::from_json(j : Json) -> RichTextBlockElement {
  let tag = type_tag_of(j)
  guard j is Object(o) else { return Unknown(type_=tag, raw=j) }
  let rest = fields_of(o)
  rest.remove("type")
  match tag {
    "rich_text_section" => Section(elements=items_of(rest), extra=rest)
    "rich_text_preformatted" =>
      Preformatted(
        border=take_int(rest, "border"),
        elements=items_of(rest),
        extra=rest,
      )
    "rich_text_quote" =>
      Quote(
        border=take_int(rest, "border"),
        elements=items_of(rest),
        extra=rest,
      )
    "rich_text_list" => {
      let elements = match rest.get("elements") {
        Some(Array(items)) => {
          rest.remove("elements")
          items.map(RichTextBlockElement::from_json)
        }
        _ => []
      }
      List(
        style=take_str(rest, "style"),
        indent=take_int(rest, "indent"),
        offset=take_int(rest, "offset"),
        border=take_int(rest, "border"),
        elements~,
        extra=rest,
      )
    }
    _ => Unknown(type_=tag, raw=j)
  }
}

///|
pub fn RichTextBlockElement::to_json(self : Self) -> Json {
  if self is Unknown(raw~, ..) {
    return raw
  }
  let o = out_of(self.type_name())
  match self {
    Section(elements~, extra~) => {
      o["elements"] = Json::array(elements.map(RichTextItem::to_json))
      merge_extra(o, extra)
    }
    Preformatted(border~, elements~, extra~) => {
      put_int(o, "border", border)
      o["elements"] = Json::array(elements.map(RichTextItem::to_json))
      merge_extra(o, extra)
    }
    Quote(border~, elements~, extra~) => {
      put_int(o, "border", border)
      o["elements"] = Json::array(elements.map(RichTextItem::to_json))
      merge_extra(o, extra)
    }
    List(style~, indent~, offset~, border~, elements~, extra~) => {
      put_str(o, "style", style)
      put_int(o, "indent", indent)
      put_int(o, "offset", offset)
      put_int(o, "border", border)
      o["elements"] = Json::array(elements.map(RichTextBlockElement::to_json))
      merge_extra(o, extra)
    }
    Unknown(raw~, ..) => raw
  }
}

///|
pub fn RichTextItem::validate(self : Self) -> Unit raise BlockParseError {
  if self is Unknown(type_=t, ..) {
    raise UnknownRichTextElement(t)
  }
}

///|
pub fn RichTextBlockElement::validate(
  self : Self,
) -> Unit raise BlockParseError {
  match self {
    Unknown(type_=t, ..) => raise UnknownRichTextElement(t)
    Section(elements~, ..)
    | Preformatted(elements~, ..)
    | Quote(elements~, ..) =>
      for item in elements {
        item.validate()
      }
    List(elements~, ..) =>
      for section in elements {
        section.validate()
      }
  }
}
