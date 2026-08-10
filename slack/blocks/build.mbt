// Builders.
//
// The parsed model is deliberately permissive -- every field optional, unknown
// keys preserved -- because that is what reading Slack's own payloads requires.
// Building is the opposite problem: a caller wants the shortest spelling of the
// common case and no way to express nonsense. Hence a builder per element TYPE
// even though several types share a struct: `users_select` and `channels_select`
// are one `SelectElement`, but no builder will let you give a `users_select` an
// `initial_channel`.

///|
pub fn section(
  text? : TextObject,
  fields? : Array[TextObject],
  accessory? : BlockElement,
  block_id? : String,
  expand? : Bool,
) -> LayoutBlock {
  Section({ block_id, text, fields, accessory, expand, extra: Map([]) })
}

///|
/// A section holding one `mrkdwn` string -- by far the most common block.
pub fn section_text(text : String, block_id? : String) -> LayoutBlock {
  section(text=TextObject::mrkdwn(text), block_id?)
}

///|
pub fn divider(block_id? : String) -> LayoutBlock {
  Divider({ block_id, extra: Map([]) })
}

///|
pub fn header(text : String, block_id? : String) -> LayoutBlock {
  Header({ block_id, text: Some(TextObject::plain(text)), extra: Map([]) })
}

///|
/// `alt_text` is not optional here even though the parser tolerates its
/// absence: an image with no alternative text is unreadable to anyone using a
/// screen reader, and Slack rejects it anyway.
pub fn image(
  image_url : String,
  alt_text : String,
  title? : TextObject,
  block_id? : String,
) -> LayoutBlock {
  Image({
    block_id,
    image_url: Some(image_url),
    slack_file: None,
    alt_text: Some(alt_text),
    title,
    extra: Map([]),
  })
}

///|
pub fn actions(
  elements : Array[BlockElement],
  block_id? : String,
) -> LayoutBlock {
  Actions({ block_id, elements: Some(elements), extra: Map([]) })
}

///|
pub fn context(
  elements : Array[BlockElement],
  block_id? : String,
) -> LayoutBlock {
  Context({ block_id, elements: Some(elements), extra: Map([]) })
}

///|
pub fn input(
  label : TextObject,
  element : BlockElement,
  hint? : TextObject,
  optional? : Bool,
  dispatch_action? : Bool,
  block_id? : String,
) -> LayoutBlock {
  Input({
    block_id,
    label: Some(label),
    element: Some(element),
    hint,
    optional,
    dispatch_action,
    extra: Map([]),
  })
}

///|
pub fn markdown(text : String, block_id? : String) -> LayoutBlock {
  Markdown({ block_id, text: Some(text), extra: Map([]) })
}

///|
pub fn rich_text(
  elements : Array[RichTextBlockElement],
  block_id? : String,
) -> LayoutBlock {
  RichText({ block_id, elements: Some(elements), extra: Map([]) })
}

///|
pub fn button(
  text : String,
  action_id? : String,
  value? : String,
  url? : String,
  style? : String,
  confirm? : ConfirmationDialogObject,
  accessibility_label? : String,
) -> BlockElement {
  Button({
    text: Some(TextObject::plain(text)),
    action_id,
    url,
    value,
    style,
    confirm,
    accessibility_label,
    extra: Map([]),
  })
}

///|
pub fn image_element(image_url : String, alt_text : String) -> BlockElement {
  Image({
    image_url: Some(image_url),
    slack_file: None,
    alt_text: Some(alt_text),
    extra: Map([]),
  })
}

///|
/// A plain-text run inside a context block.
pub fn context_text(text : String) -> BlockElement {
  Text(TextObject::mrkdwn(text))
}

///|
pub fn static_select(
  options : Array[OptionObject],
  action_id? : String,
  placeholder? : TextObject,
  initial_option? : OptionObject,
  confirm? : ConfirmationDialogObject,
) -> BlockElement {
  Select({
    ..SelectElement::blank(Static),
    action_id,
    placeholder,
    options: Some(options),
    initial_option,
    confirm,
  })
}

///|
pub fn multi_static_select(
  options : Array[OptionObject],
  action_id? : String,
  placeholder? : TextObject,
  initial_options? : Array[OptionObject],
  max_selected_items? : Int,
) -> BlockElement {
  Select({
    ..SelectElement::blank(MultiStatic),
    action_id,
    placeholder,
    options: Some(options),
    initial_options,
    max_selected_items,
  })
}

///|
pub fn users_select(
  action_id? : String,
  placeholder? : TextObject,
  initial_user? : String,
) -> BlockElement {
  Select({ ..SelectElement::blank(Users), action_id, placeholder, initial_user })
}

///|
pub fn multi_users_select(
  action_id? : String,
  placeholder? : TextObject,
  initial_users? : Array[String],
  max_selected_items? : Int,
) -> BlockElement {
  Select({
    ..SelectElement::blank(MultiUsers),
    action_id,
    placeholder,
    initial_users,
    max_selected_items,
  })
}

///|
pub fn channels_select(
  action_id? : String,
  placeholder? : TextObject,
  initial_channel? : String,
  response_url_enabled? : Bool,
) -> BlockElement {
  Select({
    ..SelectElement::blank(Channels),
    action_id,
    placeholder,
    initial_channel,
    response_url_enabled,
  })
}

///|
pub fn conversations_select(
  action_id? : String,
  placeholder? : TextObject,
  initial_conversation? : String,
  default_to_current_conversation? : Bool,
  filter? : ConversationFilterObject,
  response_url_enabled? : Bool,
) -> BlockElement {
  Select({
    ..SelectElement::blank(Conversations),
    action_id,
    placeholder,
    initial_conversation,
    default_to_current_conversation,
    filter,
    response_url_enabled,
  })
}

///|
pub fn multi_conversations_select(
  action_id? : String,
  placeholder? : TextObject,
  initial_conversations? : Array[String],
  default_to_current_conversation? : Bool,
  filter? : ConversationFilterObject,
  max_selected_items? : Int,
) -> BlockElement {
  Select({
    ..SelectElement::blank(MultiConversations),
    action_id,
    placeholder,
    initial_conversations,
    default_to_current_conversation,
    filter,
    max_selected_items,
  })
}

///|
pub fn external_select(
  action_id? : String,
  placeholder? : TextObject,
  min_query_length? : Int,
  initial_option? : OptionObject,
) -> BlockElement {
  Select({
    ..SelectElement::blank(External),
    action_id,
    placeholder,
    min_query_length,
    initial_option,
  })
}

///|
pub fn radio_buttons(
  options : Array[OptionObject],
  action_id? : String,
  initial_option? : OptionObject,
) -> BlockElement {
  Options({
    kind: RadioButtons,
    action_id,
    options: Some(options),
    initial_option,
    initial_options: None,
    confirm: None,
    focus_on_load: None,
    extra: Map([]),
  })
}

///|
pub fn checkboxes(
  options : Array[OptionObject],
  action_id? : String,
  initial_options? : Array[OptionObject],
) -> BlockElement {
  Options({
    kind: Checkboxes,
    action_id,
    options: Some(options),
    initial_option: None,
    initial_options,
    confirm: None,
    focus_on_load: None,
    extra: Map([]),
  })
}

///|
pub fn overflow(
  options : Array[OptionObject],
  action_id? : String,
  confirm? : ConfirmationDialogObject,
) -> BlockElement {
  Options({
    kind: Overflow,
    action_id,
    options: Some(options),
    initial_option: None,
    initial_options: None,
    confirm,
    focus_on_load: None,
    extra: Map([]),
  })
}

///|
fn picker(kind : PickerKind) -> PickerElement {
  {
    kind,
    action_id: None,
    placeholder: None,
    confirm: None,
    focus_on_load: None,
    initial_date: None,
    initial_time: None,
    initial_date_time: None,
    timezone: None,
    extra: Map([]),
  }
}

///|
pub fn datepicker(
  action_id? : String,
  placeholder? : TextObject,
  initial_date? : String,
) -> BlockElement {
  Picker({ ..picker(Date), action_id, placeholder, initial_date })
}

///|
pub fn timepicker(
  action_id? : String,
  placeholder? : TextObject,
  initial_time? : String,
  timezone? : String,
) -> BlockElement {
  Picker({ ..picker(Time), action_id, placeholder, initial_time, timezone })
}

///|
/// No placeholder: `datetimepicker` does not take one, which is the only reason
/// Slack keeps it a separate type from `datepicker`.
pub fn datetimepicker(
  action_id? : String,
  initial_date_time? : Int,
) -> BlockElement {
  Picker({ ..picker(DateTime), action_id, initial_date_time })
}

///|
pub fn plain_text_input(
  action_id? : String,
  placeholder? : TextObject,
  initial_value? : String,
  multiline? : Bool,
  min_length? : Int,
  max_length? : Int,
) -> BlockElement {
  PlainTextInput({
    action_id,
    placeholder,
    initial_value,
    multiline,
    min_length,
    max_length,
    dispatch_action_config: None,
    focus_on_load: None,
    extra: Map([]),
  })
}

///|
/// A rich-text paragraph.
pub fn rich_text_section(
  elements : Array[RichTextItem],
) -> RichTextBlockElement {
  Section(elements~, extra=Map([]))
}

///|
pub fn rich_text_text(text : String, style? : RichTextStyle) -> RichTextItem {
  Text(text=Some(text), style~, extra=Map([]))
}

///|
pub fn rich_text_link(
  url : String,
  text? : String,
  style? : RichTextStyle,
) -> RichTextItem {
  Link(url=Some(url), text~, unsafe_=None, style~, extra=Map([]))
}

///|
pub fn rich_text_user(user_id : String) -> RichTextItem {
  User(user_id=Some(user_id), style=None, extra=Map([]))
}

///|
pub fn rich_text_emoji(name : String, unicode? : String) -> RichTextItem {
  Emoji(name=Some(name), unicode~, skin_tone=None, style=None, extra=Map([]))
}

///|
pub fn rich_text_style(
  bold? : Bool,
  italic? : Bool,
  strike? : Bool,
  code? : Bool,
) -> RichTextStyle {
  {
    bold,
    italic,
    strike,
    code,
    highlight: None,
    client_highlight: None,
    unlink: None,
    extra: Map([]),
  }
}

///|
pub fn confirm(
  title? : String,
  text? : String,
  confirm_label? : String,
  deny_label? : String,
  style? : String,
) -> ConfirmationDialogObject {
  {
    title: title.map(t => TextObject::plain(t)),
    text: text.map(t => TextObject::mrkdwn(t)),
    confirm: confirm_label.map(t => TextObject::plain(t)),
    deny: deny_label.map(t => TextObject::plain(t)),
    style,
    extra: Map([]),
  }
}
