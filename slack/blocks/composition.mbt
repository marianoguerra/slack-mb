// Composition objects: the small shared shapes that appear inside elements.
//
// https://docs.slack.dev/reference/block-kit/composition-objects

///|
/// One choice in a select, radio group, checkbox group or overflow menu.
pub(all) struct OptionObject {
  text : TextObject
  /// Required by Slack, absent in some scrubbed fixtures -- hence optional
  /// here, so that reading such a fixture does not lose the rest of the option.
  value : String?
  description : TextObject?
  /// Overflow menus only.
  url : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn OptionObject::new(
  text : TextObject,
  value? : String,
  description? : TextObject,
  url? : String,
) -> OptionObject {
  { text, value, description, url, extra: Map([]) }
}

///|
/// A plain-text option, the shape nine callers in ten want.
pub fn OptionObject::plain(text : String, value : String) -> OptionObject {
  OptionObject::new(TextObject::plain(text), value~)
}

///|
pub fn OptionObject::from_json(j : Json) -> OptionObject? {
  guard j is Object(o) else { return None }
  let rest = fields_of(o)
  guard take_obj(rest, "text", TextObject::from_json) is Some(text) else {
    return None
  }
  Some({
    text,
    value: take_str(rest, "value"),
    description: take_obj(rest, "description", TextObject::from_json),
    url: take_str(rest, "url"),
    extra: rest,
  })
}

///|
pub fn OptionObject::to_json(self : Self) -> Json {
  let o : Map[String, Json] = Map([])
  o["text"] = self.text.to_json()
  put_str(o, "value", self.value)
  put_obj(o, "description", self.description, TextObject::to_json)
  put_str(o, "url", self.url)
  merge_extra(o, self.extra)
}

///|
pub fn OptionObject::validate(self : Self) -> Unit raise BlockParseError {
  self.text.validate()
  if self.description is Some(d) {
    d.validate()
  }
}

///|
/// A labelled group of options, for the select menus that support grouping.
pub(all) struct OptionGroupObject {
  label : TextObject
  options : Array[OptionObject]
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn OptionGroupObject::new(
  label : TextObject,
  options : Array[OptionObject],
) -> OptionGroupObject {
  { label, options, extra: Map([]) }
}

///|
pub fn OptionGroupObject::from_json(j : Json) -> OptionGroupObject? {
  guard j is Object(o) else { return None }
  let rest = fields_of(o)
  guard take_obj(rest, "label", TextObject::from_json) is Some(label) else {
    return None
  }
  guard take_arr(rest, "options", OptionObject::from_json) is Some(options) else {
    return None
  }
  Some({ label, options, extra: rest })
}

///|
pub fn OptionGroupObject::to_json(self : Self) -> Json {
  let o : Map[String, Json] = Map([])
  o["label"] = self.label.to_json()
  o["options"] = Json::array(self.options.map(OptionObject::to_json))
  merge_extra(o, self.extra)
}

///|
pub fn OptionGroupObject::validate(self : Self) -> Unit raise BlockParseError {
  self.label.validate()
  for option in self.options {
    option.validate()
  }
}

///|
/// The "are you sure?" dialog an element can show before acting.
pub(all) struct ConfirmationDialogObject {
  title : TextObject?
  text : TextObject?
  confirm : TextObject?
  deny : TextObject?
  /// `primary` or `danger`. java-slack-sdk's `confirm_style` test exists
  /// because this was added late and older clients ignore it.
  style : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn ConfirmationDialogObject::from_json(
  j : Json,
) -> ConfirmationDialogObject? {
  guard j is Object(o) else { return None }
  let rest = fields_of(o)
  Some({
    title: take_obj(rest, "title", TextObject::from_json),
    text: take_obj(rest, "text", TextObject::from_json),
    confirm: take_obj(rest, "confirm", TextObject::from_json),
    deny: take_obj(rest, "deny", TextObject::from_json),
    style: take_str(rest, "style"),
    extra: rest,
  })
}

///|
pub fn ConfirmationDialogObject::to_json(self : Self) -> Json {
  let o : Map[String, Json] = Map([])
  put_obj(o, "title", self.title, TextObject::to_json)
  put_obj(o, "text", self.text, TextObject::to_json)
  put_obj(o, "confirm", self.confirm, TextObject::to_json)
  put_obj(o, "deny", self.deny, TextObject::to_json)
  put_str(o, "style", self.style)
  merge_extra(o, self.extra)
}

///|
pub fn ConfirmationDialogObject::validate(
  self : Self,
) -> Unit raise BlockParseError {
  for t in [self.title, self.text, self.confirm, self.deny] {
    if t is Some(text) {
      text.validate()
    }
  }
}

///|
/// Which conversations a conversation select will offer.
///
/// slack-morphism's `test_conversation_filter_none_omitted` pins the part that
/// matters: an absent filter must not serialise as `"filter": {}`, because
/// Slack reads an empty filter as "offer nothing".
pub(all) struct ConversationFilterObject {
  /// Any of `im`, `mpim`, `private`, `public`. Spelled `include_` because
  /// `include` is a reserved word; the wire name is `include`.
  include_ : Array[String]?
  exclude_external_shared_channels : Bool?
  exclude_bot_users : Bool?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn ConversationFilterObject::new(
  include_? : Array[String],
  exclude_external_shared_channels? : Bool,
  exclude_bot_users? : Bool,
) -> ConversationFilterObject {
  {
    include_,
    exclude_external_shared_channels,
    exclude_bot_users,
    extra: Map([]),
  }
}

///|
pub fn ConversationFilterObject::from_json(
  j : Json,
) -> ConversationFilterObject? {
  guard j is Object(o) else { return None }
  let rest = fields_of(o)
  Some({
    include_: take_str_arr(rest, "include"),
    exclude_external_shared_channels: take_bool(
      rest, "exclude_external_shared_channels",
    ),
    exclude_bot_users: take_bool(rest, "exclude_bot_users"),
    extra: rest,
  })
}

///|
pub fn ConversationFilterObject::to_json(self : Self) -> Json {
  let o : Map[String, Json] = Map([])
  put_str_arr(o, "include", self.include_)
  put_bool(
    o,
    "exclude_external_shared_channels",
    self.exclude_external_shared_channels,
  )
  put_bool(o, "exclude_bot_users", self.exclude_bot_users)
  merge_extra(o, self.extra)
}

///|
/// When a plain-text input should fire its action.
pub(all) struct DispatchActionConfigObject {
  /// `on_enter_pressed`, `on_character_entered`.
  trigger_actions_on : Array[String]?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn DispatchActionConfigObject::from_json(
  j : Json,
) -> DispatchActionConfigObject? {
  guard j is Object(o) else { return None }
  let rest = fields_of(o)
  Some({
    trigger_actions_on: take_str_arr(rest, "trigger_actions_on"),
    extra: rest,
  })
}

///|
pub fn DispatchActionConfigObject::to_json(self : Self) -> Json {
  let o : Map[String, Json] = Map([])
  put_str_arr(o, "trigger_actions_on", self.trigger_actions_on)
  merge_extra(o, self.extra)
}

///|
/// A reference to a file already hosted by Slack, as an alternative to an
/// `image_url`.
pub(all) struct SlackFileObject {
  id : String?
  url : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn SlackFileObject::from_json(j : Json) -> SlackFileObject? {
  guard j is Object(o) else { return None }
  let rest = fields_of(o)
  Some({ id: take_str(rest, "id"), url: take_str(rest, "url"), extra: rest })
}

///|
pub fn SlackFileObject::to_json(self : Self) -> Json {
  let o : Map[String, Json] = Map([])
  put_str(o, "id", self.id)
  put_str(o, "url", self.url)
  merge_extra(o, self.extra)
}
