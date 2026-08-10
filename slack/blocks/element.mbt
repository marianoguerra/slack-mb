// Block elements: the interactive parts.
//
// https://docs.slack.dev/reference/block-kit/block-elements
//
// The ten select menus share one struct and the three pickers share another,
// keyed by a `kind`. Slack documents them separately, but their JSON differs
// only in which `initial_*` field appears -- and java-slack-sdk's own fixture
// corpus merges every observed shape of every element into one object anyway,
// so a struct per type would spend a thousand lines to model a distinction the
// data does not make. The builders below are per type, which is where the
// distinction is actually useful: `BlockElement::users_select` cannot be given
// an `initial_channel`.

///|
/// Which select menu this is.
pub(all) enum SelectKind {
  Static
  MultiStatic
  External
  MultiExternal
  Users
  MultiUsers
  Conversations
  MultiConversations
  Channels
  MultiChannels
} derive(Eq, Debug)

///|
pub fn SelectKind::type_name(self : Self) -> String {
  match self {
    Static => "static_select"
    MultiStatic => "multi_static_select"
    External => "external_select"
    MultiExternal => "multi_external_select"
    Users => "users_select"
    MultiUsers => "multi_users_select"
    Conversations => "conversations_select"
    MultiConversations => "multi_conversations_select"
    Channels => "channels_select"
    MultiChannels => "multi_channels_select"
  }
}

///|
pub fn SelectKind::of_name(name : String) -> SelectKind? {
  match name {
    "static_select" => Some(Static)
    "multi_static_select" => Some(MultiStatic)
    "external_select" => Some(External)
    "multi_external_select" => Some(MultiExternal)
    "users_select" => Some(Users)
    "multi_users_select" => Some(MultiUsers)
    "conversations_select" => Some(Conversations)
    "multi_conversations_select" => Some(MultiConversations)
    "channels_select" => Some(Channels)
    "multi_channels_select" => Some(MultiChannels)
    _ => None
  }
}

///|
/// Any of the ten select menus.
pub(all) struct SelectElement {
  kind : SelectKind
  action_id : String?
  placeholder : TextObject?
  confirm : ConfirmationDialogObject?
  focus_on_load : Bool?
  /// `static_select` and `multi_static_select`.
  options : Array[OptionObject]?
  option_groups : Array[OptionGroupObject]?
  initial_option : OptionObject?
  initial_options : Array[OptionObject]?
  initial_user : String?
  initial_users : Array[String]?
  initial_conversation : String?
  initial_conversations : Array[String]?
  initial_channel : String?
  initial_channels : Array[String]?
  /// `external_select`, `multi_external_select`.
  min_query_length : Int?
  /// The `multi_*` menus.
  max_selected_items : Int?
  /// Conversation menus: preselect whatever conversation the user is in.
  default_to_current_conversation : Bool?
  /// Conversation and channel menus in a message: Slack sends the selection to
  /// a response URL.
  response_url_enabled : Bool?
  filter : ConversationFilterObject?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
fn SelectElement::blank(kind : SelectKind) -> SelectElement {
  {
    kind,
    action_id: None,
    placeholder: None,
    confirm: None,
    focus_on_load: None,
    options: None,
    option_groups: None,
    initial_option: None,
    initial_options: None,
    initial_user: None,
    initial_users: None,
    initial_conversation: None,
    initial_conversations: None,
    initial_channel: None,
    initial_channels: None,
    min_query_length: None,
    max_selected_items: None,
    default_to_current_conversation: None,
    response_url_enabled: None,
    filter: None,
    extra: Map([]),
  }
}

///|
fn SelectElement::of_fields(
  kind : SelectKind,
  rest : Map[String, Json],
) -> SelectElement {
  {
    kind,
    action_id: take_str(rest, "action_id"),
    placeholder: take_obj(rest, "placeholder", TextObject::from_json),
    confirm: take_obj(rest, "confirm", ConfirmationDialogObject::from_json),
    focus_on_load: take_bool(rest, "focus_on_load"),
    options: take_arr(rest, "options", OptionObject::from_json),
    option_groups: take_arr(rest, "option_groups", OptionGroupObject::from_json),
    initial_option: take_obj(rest, "initial_option", OptionObject::from_json),
    initial_options: take_arr(rest, "initial_options", OptionObject::from_json),
    initial_user: take_str(rest, "initial_user"),
    initial_users: take_str_arr(rest, "initial_users"),
    initial_conversation: take_str(rest, "initial_conversation"),
    initial_conversations: take_str_arr(rest, "initial_conversations"),
    initial_channel: take_str(rest, "initial_channel"),
    initial_channels: take_str_arr(rest, "initial_channels"),
    min_query_length: take_int(rest, "min_query_length"),
    max_selected_items: take_int(rest, "max_selected_items"),
    default_to_current_conversation: take_bool(
      rest, "default_to_current_conversation",
    ),
    response_url_enabled: take_bool(rest, "response_url_enabled"),
    filter: take_obj(rest, "filter", ConversationFilterObject::from_json),
    extra: rest,
  }
}

///|
pub fn SelectElement::to_json(self : Self) -> Json {
  let o = out_of(self.kind.type_name())
  put_str(o, "action_id", self.action_id)
  put_obj(o, "placeholder", self.placeholder, TextObject::to_json)
  put_obj(o, "confirm", self.confirm, ConfirmationDialogObject::to_json)
  put_bool(o, "focus_on_load", self.focus_on_load)
  put_arr(o, "options", self.options, OptionObject::to_json)
  put_arr(o, "option_groups", self.option_groups, OptionGroupObject::to_json)
  put_obj(o, "initial_option", self.initial_option, OptionObject::to_json)
  put_arr(o, "initial_options", self.initial_options, OptionObject::to_json)
  put_str(o, "initial_user", self.initial_user)
  put_str_arr(o, "initial_users", self.initial_users)
  put_str(o, "initial_conversation", self.initial_conversation)
  put_str_arr(o, "initial_conversations", self.initial_conversations)
  put_str(o, "initial_channel", self.initial_channel)
  put_str_arr(o, "initial_channels", self.initial_channels)
  put_int(o, "min_query_length", self.min_query_length)
  put_int(o, "max_selected_items", self.max_selected_items)
  put_bool(
    o,
    "default_to_current_conversation",
    self.default_to_current_conversation,
  )
  put_bool(o, "response_url_enabled", self.response_url_enabled)
  put_obj(o, "filter", self.filter, ConversationFilterObject::to_json)
  merge_extra(o, self.extra)
}

///|
/// A button.
pub(all) struct ButtonElement {
  text : TextObject?
  action_id : String?
  /// A button with a `url` opens it; one without posts an interaction.
  url : String?
  value : String?
  /// `primary` or `danger`.
  style : String?
  confirm : ConfirmationDialogObject?
  /// Read by screen readers instead of the button's text.
  accessibility_label : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn ButtonElement::to_json(self : Self) -> Json {
  let o = out_of("button")
  put_obj(o, "text", self.text, TextObject::to_json)
  put_str(o, "action_id", self.action_id)
  put_str(o, "url", self.url)
  put_str(o, "value", self.value)
  put_str(o, "style", self.style)
  put_obj(o, "confirm", self.confirm, ConfirmationDialogObject::to_json)
  put_str(o, "accessibility_label", self.accessibility_label)
  merge_extra(o, self.extra)
}

///|
/// A button that runs a workflow directly, without a round trip to an app.
pub(all) struct WorkflowButtonElement {
  text : TextObject?
  action_id : String?
  style : String?
  accessibility_label : String?
  /// The workflow and its trigger. Kept as raw JSON: the shape is a nested
  /// trigger object with customisable inputs whose keys are defined by the
  /// workflow itself, so there is nothing general to model.
  workflow : Json?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn WorkflowButtonElement::to_json(self : Self) -> Json {
  let o = out_of("workflow_button")
  put_obj(o, "text", self.text, TextObject::to_json)
  put_str(o, "action_id", self.action_id)
  put_str(o, "style", self.style)
  put_str(o, "accessibility_label", self.accessibility_label)
  put_json(o, "workflow", self.workflow)
  merge_extra(o, self.extra)
}

///|
/// An image, as an element rather than as a whole block.
pub(all) struct ImageElement {
  /// One of `image_url` or `slack_file` is required by Slack; both are optional
  /// here so a scrubbed fixture with neither still parses.
  image_url : String?
  slack_file : SlackFileObject?
  alt_text : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn ImageElement::to_json(self : Self) -> Json {
  let o = out_of("image")
  put_str(o, "image_url", self.image_url)
  put_obj(o, "slack_file", self.slack_file, SlackFileObject::to_json)
  put_str(o, "alt_text", self.alt_text)
  merge_extra(o, self.extra)
}

///|
/// Which option-list element this is.
pub(all) enum OptionsKind {
  RadioButtons
  Checkboxes
  Overflow
} derive(Eq, Debug)

///|
pub fn OptionsKind::type_name(self : Self) -> String {
  match self {
    RadioButtons => "radio_buttons"
    Checkboxes => "checkboxes"
    Overflow => "overflow"
  }
}

///|
pub fn OptionsKind::of_name(name : String) -> OptionsKind? {
  match name {
    "radio_buttons" => Some(RadioButtons)
    "checkboxes" => Some(Checkboxes)
    "overflow" => Some(Overflow)
    _ => None
  }
}

///|
/// Radio buttons, checkboxes and overflow menus: an inline list of options.
///
/// One struct because they differ only in whether one option or several may be
/// initially selected -- and an overflow menu, which is a menu rather than an
/// input, has neither.
pub(all) struct OptionsElement {
  kind : OptionsKind
  action_id : String?
  options : Array[OptionObject]?
  /// Radio buttons.
  initial_option : OptionObject?
  /// Checkboxes.
  initial_options : Array[OptionObject]?
  confirm : ConfirmationDialogObject?
  focus_on_load : Bool?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn OptionsElement::to_json(self : Self) -> Json {
  let o = out_of(self.kind.type_name())
  put_str(o, "action_id", self.action_id)
  put_arr(o, "options", self.options, OptionObject::to_json)
  put_obj(o, "initial_option", self.initial_option, OptionObject::to_json)
  put_arr(o, "initial_options", self.initial_options, OptionObject::to_json)
  put_obj(o, "confirm", self.confirm, ConfirmationDialogObject::to_json)
  put_bool(o, "focus_on_load", self.focus_on_load)
  merge_extra(o, self.extra)
}

///|
/// Which date or time picker this is.
pub(all) enum PickerKind {
  Date
  Time
  DateTime
} derive(Eq, Debug)

///|
pub fn PickerKind::type_name(self : Self) -> String {
  match self {
    Date => "datepicker"
    Time => "timepicker"
    DateTime => "datetimepicker"
  }
}

///|
pub fn PickerKind::of_name(name : String) -> PickerKind? {
  match name {
    "datepicker" => Some(Date)
    "timepicker" => Some(Time)
    "datetimepicker" => Some(DateTime)
    _ => None
  }
}

///|
pub(all) struct PickerElement {
  kind : PickerKind
  action_id : String?
  placeholder : TextObject?
  confirm : ConfirmationDialogObject?
  focus_on_load : Bool?
  /// `YYYY-MM-DD`.
  initial_date : String?
  /// `HH:mm`, 24-hour.
  initial_time : String?
  /// Epoch seconds. `datetimepicker` has no placeholder, which is why Slack
  /// keeps it a separate type.
  initial_date_time : Int?
  /// A tz database name, for `timepicker`.
  timezone : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn PickerElement::to_json(self : Self) -> Json {
  let o = out_of(self.kind.type_name())
  put_str(o, "action_id", self.action_id)
  put_obj(o, "placeholder", self.placeholder, TextObject::to_json)
  put_obj(o, "confirm", self.confirm, ConfirmationDialogObject::to_json)
  put_bool(o, "focus_on_load", self.focus_on_load)
  put_str(o, "initial_date", self.initial_date)
  put_str(o, "initial_time", self.initial_time)
  put_int(o, "initial_date_time", self.initial_date_time)
  put_str(o, "timezone", self.timezone)
  merge_extra(o, self.extra)
}

///|
/// A free-text input.
pub(all) struct PlainTextInputElement {
  action_id : String?
  placeholder : TextObject?
  initial_value : String?
  multiline : Bool?
  min_length : Int?
  max_length : Int?
  dispatch_action_config : DispatchActionConfigObject?
  focus_on_load : Bool?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn PlainTextInputElement::to_json(self : Self) -> Json {
  let o = out_of("plain_text_input")
  put_str(o, "action_id", self.action_id)
  put_obj(o, "placeholder", self.placeholder, TextObject::to_json)
  put_str(o, "initial_value", self.initial_value)
  put_bool(o, "multiline", self.multiline)
  put_int(o, "min_length", self.min_length)
  put_int(o, "max_length", self.max_length)
  put_obj(
    o,
    "dispatch_action_config",
    self.dispatch_action_config,
    DispatchActionConfigObject::to_json,
  )
  put_bool(o, "focus_on_load", self.focus_on_load)
  merge_extra(o, self.extra)
}

///|
/// A rich-text input: the composer, embedded in a modal.
pub(all) struct RichTextInputElement {
  action_id : String?
  placeholder : TextObject?
  /// A `rich_text` block. Kept as raw JSON so that the input's value and the
  /// block model cannot drift apart.
  initial_value : Json?
  dispatch_action_config : DispatchActionConfigObject?
  focus_on_load : Bool?
  min_lines : Int?
  max_lines : Int?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn RichTextInputElement::to_json(self : Self) -> Json {
  let o = out_of("rich_text_input")
  put_str(o, "action_id", self.action_id)
  put_obj(o, "placeholder", self.placeholder, TextObject::to_json)
  put_json(o, "initial_value", self.initial_value)
  put_obj(
    o,
    "dispatch_action_config",
    self.dispatch_action_config,
    DispatchActionConfigObject::to_json,
  )
  put_bool(o, "focus_on_load", self.focus_on_load)
  put_int(o, "min_lines", self.min_lines)
  put_int(o, "max_lines", self.max_lines)
  merge_extra(o, self.extra)
}

///|
/// Anything that can sit in an `accessory`, an `element` or an `elements` list.
pub(all) enum BlockElement {
  Button(ButtonElement)
  WorkflowButton(WorkflowButtonElement)
  Image(ImageElement)
  Select(SelectElement)
  Picker(PickerElement)
  Options(OptionsElement)
  PlainTextInput(PlainTextInputElement)
  RichTextInput(RichTextInputElement)
  /// A text object appearing where an element is expected. Context blocks
  /// accept these directly, which is why they are elements rather than a
  /// special case of the context block.
  Text(TextObject)
  /// Anything this version does not model, kept verbatim so it round-trips and
  /// so `validate` can name it under `Strict`.
  Unknown(type_~ : String, raw~ : Json)
} derive(Eq, Debug)

///|
/// Always succeeds: an unrecognised element becomes `Unknown`.
pub fn BlockElement::from_json(j : Json) -> BlockElement {
  let tag = type_tag_of(j)
  guard j is Object(o) else { return Unknown(type_=tag, raw=j) }
  if tag == "plain_text" || tag == "mrkdwn" {
    if TextObject::from_json(j) is Some(t) {
      return Text(t)
    }
  }
  let rest = fields_of(o)
  rest.remove("type")
  if SelectKind::of_name(tag) is Some(kind) {
    return Select(SelectElement::of_fields(kind, rest))
  }
  if OptionsKind::of_name(tag) is Some(kind) {
    return Options({
      kind,
      action_id: take_str(rest, "action_id"),
      options: take_arr(rest, "options", OptionObject::from_json),
      initial_option: take_obj(rest, "initial_option", OptionObject::from_json),
      initial_options: take_arr(
        rest,
        "initial_options",
        OptionObject::from_json,
      ),
      confirm: take_obj(rest, "confirm", ConfirmationDialogObject::from_json),
      focus_on_load: take_bool(rest, "focus_on_load"),
      extra: rest,
    })
  }
  if PickerKind::of_name(tag) is Some(kind) {
    return Picker({
      kind,
      action_id: take_str(rest, "action_id"),
      placeholder: take_obj(rest, "placeholder", TextObject::from_json),
      confirm: take_obj(rest, "confirm", ConfirmationDialogObject::from_json),
      focus_on_load: take_bool(rest, "focus_on_load"),
      initial_date: take_str(rest, "initial_date"),
      initial_time: take_str(rest, "initial_time"),
      initial_date_time: take_int(rest, "initial_date_time"),
      timezone: take_str(rest, "timezone"),
      extra: rest,
    })
  }
  match tag {
    "button" =>
      Button({
        text: take_obj(rest, "text", TextObject::from_json),
        action_id: take_str(rest, "action_id"),
        url: take_str(rest, "url"),
        value: take_str(rest, "value"),
        style: take_str(rest, "style"),
        confirm: take_obj(rest, "confirm", ConfirmationDialogObject::from_json),
        accessibility_label: take_str(rest, "accessibility_label"),
        extra: rest,
      })
    "workflow_button" =>
      WorkflowButton({
        text: take_obj(rest, "text", TextObject::from_json),
        action_id: take_str(rest, "action_id"),
        style: take_str(rest, "style"),
        accessibility_label: take_str(rest, "accessibility_label"),
        workflow: take_json(rest, "workflow"),
        extra: rest,
      })
    "image" =>
      Image({
        image_url: take_str(rest, "image_url"),
        slack_file: take_obj(rest, "slack_file", SlackFileObject::from_json),
        alt_text: take_str(rest, "alt_text"),
        extra: rest,
      })
    "plain_text_input" =>
      PlainTextInput({
        action_id: take_str(rest, "action_id"),
        placeholder: take_obj(rest, "placeholder", TextObject::from_json),
        initial_value: take_str(rest, "initial_value"),
        multiline: take_bool(rest, "multiline"),
        min_length: take_int(rest, "min_length"),
        max_length: take_int(rest, "max_length"),
        dispatch_action_config: take_obj(
          rest,
          "dispatch_action_config",
          DispatchActionConfigObject::from_json,
        ),
        focus_on_load: take_bool(rest, "focus_on_load"),
        extra: rest,
      })
    "rich_text_input" =>
      RichTextInput({
        action_id: take_str(rest, "action_id"),
        placeholder: take_obj(rest, "placeholder", TextObject::from_json),
        initial_value: take_json(rest, "initial_value"),
        dispatch_action_config: take_obj(
          rest,
          "dispatch_action_config",
          DispatchActionConfigObject::from_json,
        ),
        focus_on_load: take_bool(rest, "focus_on_load"),
        min_lines: take_int(rest, "min_lines"),
        max_lines: take_int(rest, "max_lines"),
        extra: rest,
      })
    _ => Unknown(type_=tag, raw=j)
  }
}

///|
pub fn BlockElement::to_json(self : Self) -> Json {
  match self {
    Button(e) => e.to_json()
    WorkflowButton(e) => e.to_json()
    Image(e) => e.to_json()
    Select(e) => e.to_json()
    Picker(e) => e.to_json()
    Options(e) => e.to_json()
    PlainTextInput(e) => e.to_json()
    RichTextInput(e) => e.to_json()
    Text(t) => t.to_json()
    Unknown(raw~, ..) => raw
  }
}

///|
pub fn BlockElement::type_name(self : Self) -> String {
  match self {
    Button(_) => "button"
    WorkflowButton(_) => "workflow_button"
    Image(_) => "image"
    Select(e) => e.kind.type_name()
    Picker(e) => e.kind.type_name()
    Options(e) => e.kind.type_name()
    PlainTextInput(_) => "plain_text_input"
    RichTextInput(_) => "rich_text_input"
    Text(t) => t.type_name()
    Unknown(type_=t, ..) => t
  }
}

///|
/// Raise on anything unmodelled inside this element.
///
/// `in_context` picks the message java-slack-sdk would produce: an unknown
/// element inside a context block reports differently from one in an
/// `element` slot, and its BlockKitTest asserts on both strings.
pub fn BlockElement::validate(
  self : Self,
  in_context? : Bool = false,
) -> Unit raise BlockParseError {
  match self {
    Unknown(type_=t, ..) =>
      if in_context {
        raise UnknownContextBlockElement(t)
      } else {
        raise UnknownBlockElement(t)
      }
    Text(t) => t.validate()
    Button(e) => {
      validate_text_opt(e.text)
      validate_confirm(e.confirm)
    }
    WorkflowButton(e) => validate_text_opt(e.text)
    Image(_) => ()
    Select(e) => {
      validate_text_opt(e.placeholder)
      validate_confirm(e.confirm)
      validate_options(e.options)
      validate_options(e.initial_options)
      validate_option_opt(e.initial_option)
      if e.option_groups is Some(groups) {
        for group in groups {
          group.validate()
        }
      }
    }
    Picker(e) => {
      validate_text_opt(e.placeholder)
      validate_confirm(e.confirm)
    }
    Options(e) => {
      validate_confirm(e.confirm)
      validate_options(e.options)
      validate_options(e.initial_options)
      validate_option_opt(e.initial_option)
    }
    PlainTextInput(e) => validate_text_opt(e.placeholder)
    RichTextInput(e) => validate_text_opt(e.placeholder)
  }
}

///|
fn validate_text_opt(t : TextObject?) -> Unit raise BlockParseError {
  if t is Some(text) {
    text.validate()
  }
}

///|
fn validate_confirm(
  c : ConfirmationDialogObject?,
) -> Unit raise BlockParseError {
  if c is Some(dialog) {
    dialog.validate()
  }
}

///|
fn validate_option_opt(o : OptionObject?) -> Unit raise BlockParseError {
  if o is Some(option) {
    option.validate()
  }
}

///|
fn validate_options(
  options : Array[OptionObject]?,
) -> Unit raise BlockParseError {
  if options is Some(list) {
    for option in list {
      option.validate()
    }
  }
}
