// Layout blocks: the top level of a message, a modal or an App Home tab.
//
// https://docs.slack.dev/reference/block-kit/blocks

///|
pub(all) struct SectionBlock {
  block_id : String?
  text : TextObject?
  /// Up to ten short texts, rendered in two columns.
  fields : Array[TextObject]?
  accessory : BlockElement?
  /// Show the section's text in full rather than truncating it.
  expand : Bool?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct DividerBlock {
  block_id : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct ImageBlock {
  block_id : String?
  /// One of `image_url` or `slack_file`.
  image_url : String?
  slack_file : SlackFileObject?
  alt_text : String?
  title : TextObject?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct ActionsBlock {
  block_id : String?
  elements : Array[BlockElement]?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// Small context lines under a message: a mix of images and text objects, which
/// is why its elements are `BlockElement` and include the `Text` variant.
pub(all) struct ContextBlock {
  block_id : String?
  elements : Array[BlockElement]?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct InputBlock {
  block_id : String?
  label : TextObject?
  element : BlockElement?
  hint : TextObject?
  optional : Bool?
  /// Send an interaction as the user types, rather than only on submit.
  dispatch_action : Bool?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct HeaderBlock {
  block_id : String?
  text : TextObject?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct FileBlock {
  block_id : String?
  external_id : String?
  /// Always `remote` today.
  source : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct VideoBlock {
  block_id : String?
  video_url : String?
  thumbnail_url : String?
  alt_text : String?
  title : TextObject?
  title_url : String?
  author_name : String?
  provider_name : String?
  provider_icon_url : String?
  description : TextObject?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// Markdown as a single string, rather than as a text object.
///
/// Added for AI apps, which produce markdown and should not have to convert it
/// to Slack's `mrkdwn` dialect. java-slack-sdk's `parseMarkdownBlock` test is
/// the whole of its coverage.
pub(all) struct MarkdownBlock {
  block_id : String?
  text : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct RichTextBlock {
  block_id : String?
  elements : Array[RichTextBlockElement]?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// A Slack call, from the Calls API.
pub(all) struct CallBlock {
  block_id : String?
  call_id : String?
  /// The call's own payload, whose shape belongs to the Calls API rather than
  /// to Block Kit.
  call : Json?
  api_decoration_available : Bool?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// One block in a message, modal or App Home tab.
pub(all) enum LayoutBlock {
  Section(SectionBlock)
  Divider(DividerBlock)
  Image(ImageBlock)
  Actions(ActionsBlock)
  Context(ContextBlock)
  Input(InputBlock)
  Header(HeaderBlock)
  File(FileBlock)
  Video(VideoBlock)
  Markdown(MarkdownBlock)
  RichText(RichTextBlock)
  Call(CallBlock)
  Alert(AlertBlock)
  Card(CardBlock)
  Carousel(CarouselBlock)
  ContextActions(ContextActionsBlock)
  Table(TableBlock)
  TaskCard(TaskCardBlock)
  ShareShortcut(ShareShortcutBlock)
  /// Anything this version does not model, kept verbatim so it round-trips and
  /// so `validate` can name it under `Strict`.
  Unknown(type_~ : String, raw~ : Json)
} derive(Eq, Debug)

///|
pub fn LayoutBlock::type_name(self : Self) -> String {
  match self {
    Section(_) => "section"
    Divider(_) => "divider"
    Image(_) => "image"
    Actions(_) => "actions"
    Context(_) => "context"
    Input(_) => "input"
    Header(_) => "header"
    File(_) => "file"
    Video(_) => "video"
    Markdown(_) => "markdown"
    RichText(_) => "rich_text"
    Call(_) => "call"
    Alert(_) => "alert"
    Card(_) => "card"
    Carousel(_) => "carousel"
    ContextActions(_) => "context_actions"
    Table(_) => "table"
    TaskCard(_) => "task_card"
    ShareShortcut(_) => "share_shortcut"
    Unknown(type_=t, ..) => t
  }
}

///|
pub fn LayoutBlock::block_id(self : Self) -> String? {
  match self {
    Section(b) => b.block_id
    Divider(b) => b.block_id
    Image(b) => b.block_id
    Actions(b) => b.block_id
    Context(b) => b.block_id
    Input(b) => b.block_id
    Header(b) => b.block_id
    File(b) => b.block_id
    Video(b) => b.block_id
    Markdown(b) => b.block_id
    RichText(b) => b.block_id
    Call(b) => b.block_id
    Alert(b) => b.block_id
    Card(b) => b.block_id
    Carousel(b) => b.block_id
    ContextActions(b) => b.block_id
    Table(b) => b.block_id
    TaskCard(b) => b.block_id
    ShareShortcut(b) => b.block_id
    Unknown(raw~, ..) =>
      match raw {
        Object(o) =>
          match o.get("block_id") {
            Some(String(s)) => Some(s)
            _ => None
          }
        _ => None
      }
  }
}

///|
fn elements_of(rest : Map[String, Json]) -> Array[BlockElement]? {
  match rest.get("elements") {
    Some(Array(items)) => {
      rest.remove("elements")
      Some(items.map(BlockElement::from_json))
    }
    _ => None
  }
}

///|
/// Always succeeds: an unrecognised block becomes `Unknown`.
///
/// Total on purpose. Strictness is `validate`, run afterwards, so that there is
/// one parser rather than a lenient one and a strict one that can drift.
pub fn LayoutBlock::from_json(j : Json) -> LayoutBlock {
  let tag = type_tag_of(j)
  guard j is Object(o) else { return Unknown(type_=tag, raw=j) }
  let rest = fields_of(o)
  rest.remove("type")
  let block_id = take_str(rest, "block_id")
  match tag {
    "section" =>
      Section({
        block_id,
        text: take_obj(rest, "text", TextObject::from_json),
        fields: take_arr(rest, "fields", TextObject::from_json),
        accessory: take_element(rest, "accessory"),
        expand: take_bool(rest, "expand"),
        extra: rest,
      })
    "divider" => Divider({ block_id, extra: rest })
    "image" =>
      Image({
        block_id,
        image_url: take_str(rest, "image_url"),
        slack_file: take_obj(rest, "slack_file", SlackFileObject::from_json),
        alt_text: take_str(rest, "alt_text"),
        title: take_obj(rest, "title", TextObject::from_json),
        extra: rest,
      })
    "actions" => Actions({ block_id, elements: elements_of(rest), extra: rest })
    "context" => Context({ block_id, elements: elements_of(rest), extra: rest })
    "input" =>
      Input({
        block_id,
        label: take_obj(rest, "label", TextObject::from_json),
        element: take_element(rest, "element"),
        hint: take_obj(rest, "hint", TextObject::from_json),
        optional: take_bool(rest, "optional"),
        dispatch_action: take_bool(rest, "dispatch_action"),
        extra: rest,
      })
    "header" =>
      Header({
        block_id,
        text: take_obj(rest, "text", TextObject::from_json),
        extra: rest,
      })
    "file" =>
      File({
        block_id,
        external_id: take_str(rest, "external_id"),
        source: take_str(rest, "source"),
        extra: rest,
      })
    "video" =>
      Video({
        block_id,
        video_url: take_str(rest, "video_url"),
        thumbnail_url: take_str(rest, "thumbnail_url"),
        alt_text: take_str(rest, "alt_text"),
        title: take_obj(rest, "title", TextObject::from_json),
        title_url: take_str(rest, "title_url"),
        author_name: take_str(rest, "author_name"),
        provider_name: take_str(rest, "provider_name"),
        provider_icon_url: take_str(rest, "provider_icon_url"),
        description: take_obj(rest, "description", TextObject::from_json),
        extra: rest,
      })
    "markdown" =>
      Markdown({ block_id, text: take_str(rest, "text"), extra: rest })
    "rich_text" => {
      let elements = match rest.get("elements") {
        Some(Array(items)) => {
          rest.remove("elements")
          Some(items.map(RichTextBlockElement::from_json))
        }
        _ => None
      }
      RichText({ block_id, elements, extra: rest })
    }
    "call" =>
      Call({
        block_id,
        call_id: take_str(rest, "call_id"),
        call: take_json(rest, "call"),
        api_decoration_available: take_bool(rest, "api_decoration_available"),
        extra: rest,
      })
    "alert" =>
      Alert({
        block_id,
        text: take_obj(rest, "text", TextObject::from_json),
        level: take_str(rest, "level"),
        extra: rest,
      })
    "card" =>
      Card({
        block_id,
        hero_image: take_element(rest, "hero_image"),
        icon: take_element(rest, "icon"),
        slack_icon: take_json(rest, "slack_icon"),
        title: take_obj(rest, "title", TextObject::from_json),
        subtitle: take_obj(rest, "subtitle", TextObject::from_json),
        body: take_obj(rest, "body", TextObject::from_json),
        subtext: take_obj(rest, "subtext", TextObject::from_json),
        actions: match rest.get("actions") {
          Some(Array(items)) => {
            rest.remove("actions")
            Some(items.map(BlockElement::from_json))
          }
          _ => None
        },
        extra: rest,
      })
    "carousel" =>
      Carousel({
        block_id,
        elements: match rest.get("elements") {
          Some(Array(items)) => {
            rest.remove("elements")
            Some(items.map(LayoutBlock::from_json))
          }
          _ => None
        },
        extra: rest,
      })
    "context_actions" =>
      ContextActions({ block_id, elements: elements_of(rest), extra: rest })
    "table" =>
      Table({
        block_id,
        column_settings: take_json(rest, "column_settings"),
        rows: take_json(rest, "rows"),
        extra: rest,
      })
    "task_card" =>
      TaskCard({
        block_id,
        task_id: take_str(rest, "task_id"),
        title: take_str(rest, "title"),
        status: take_str(rest, "status"),
        output: take_json(rest, "output"),
        sources: take_json(rest, "sources"),
        extra: rest,
      })
    "share_shortcut" =>
      ShareShortcut({
        block_id,
        function_trigger_id: take_str(rest, "function_trigger_id"),
        app_id: take_str(rest, "app_id"),
        is_workflow_app: take_bool(rest, "is_workflow_app"),
        sales_home_workflow_app_type: take_int(
          rest, "sales_home_workflow_app_type",
        ),
        app_collaborators: take_str_arr(rest, "app_collaborators"),
        button_label: take_str(rest, "button_label"),
        title: take_str(rest, "title"),
        description: take_str(rest, "description"),
        bot_user_id: take_str(rest, "bot_user_id"),
        url: take_str(rest, "url"),
        owning_team_id: take_str(rest, "owning_team_id"),
        workflow_id: take_str(rest, "workflow_id"),
        developer_trace_id: take_str(rest, "developer_trace_id"),
        trigger_type: take_str(rest, "trigger_type"),
        trigger_subtype: take_str(rest, "trigger_subtype"),
        share_url: take_str(rest, "share_url"),
        extra: rest,
      })
    _ => Unknown(type_=tag, raw=j)
  }
}

///|
/// Take an element slot. Unlike `take_obj` this always succeeds when the key
/// holds anything at all, because `BlockElement::from_json` is total -- an
/// unrecognised element becomes `Unknown` rather than staying in `extra`, which
/// is what lets `validate` report it.
fn take_element(rest : Map[String, Json], key : String) -> BlockElement? {
  match rest.get(key) {
    Some(v) => {
      rest.remove(key)
      Some(BlockElement::from_json(v))
    }
    None => None
  }
}

///|
pub fn LayoutBlock::to_json(self : Self) -> Json {
  if self is Unknown(raw~, ..) {
    return raw
  }
  let o = out_of(self.type_name())
  put_str(o, "block_id", self.block_id())
  match self {
    Section(b) => {
      put_obj(o, "text", b.text, TextObject::to_json)
      put_arr(o, "fields", b.fields, TextObject::to_json)
      put_obj(o, "accessory", b.accessory, BlockElement::to_json)
      put_bool(o, "expand", b.expand)
      merge_extra(o, b.extra)
    }
    Divider(b) => merge_extra(o, b.extra)
    Image(b) => {
      put_str(o, "image_url", b.image_url)
      put_obj(o, "slack_file", b.slack_file, SlackFileObject::to_json)
      put_str(o, "alt_text", b.alt_text)
      put_obj(o, "title", b.title, TextObject::to_json)
      merge_extra(o, b.extra)
    }
    Actions(b) => {
      put_arr(o, "elements", b.elements, BlockElement::to_json)
      merge_extra(o, b.extra)
    }
    Context(b) => {
      put_arr(o, "elements", b.elements, BlockElement::to_json)
      merge_extra(o, b.extra)
    }
    Input(b) => {
      put_obj(o, "label", b.label, TextObject::to_json)
      put_obj(o, "element", b.element, BlockElement::to_json)
      put_obj(o, "hint", b.hint, TextObject::to_json)
      put_bool(o, "optional", b.optional)
      put_bool(o, "dispatch_action", b.dispatch_action)
      merge_extra(o, b.extra)
    }
    Header(b) => {
      put_obj(o, "text", b.text, TextObject::to_json)
      merge_extra(o, b.extra)
    }
    File(b) => {
      put_str(o, "external_id", b.external_id)
      put_str(o, "source", b.source)
      merge_extra(o, b.extra)
    }
    Video(b) => {
      put_str(o, "video_url", b.video_url)
      put_str(o, "thumbnail_url", b.thumbnail_url)
      put_str(o, "alt_text", b.alt_text)
      put_obj(o, "title", b.title, TextObject::to_json)
      put_str(o, "title_url", b.title_url)
      put_str(o, "author_name", b.author_name)
      put_str(o, "provider_name", b.provider_name)
      put_str(o, "provider_icon_url", b.provider_icon_url)
      put_obj(o, "description", b.description, TextObject::to_json)
      merge_extra(o, b.extra)
    }
    Markdown(b) => {
      put_str(o, "text", b.text)
      merge_extra(o, b.extra)
    }
    RichText(b) => {
      put_arr(o, "elements", b.elements, RichTextBlockElement::to_json)
      merge_extra(o, b.extra)
    }
    Call(b) => {
      put_str(o, "call_id", b.call_id)
      put_json(o, "call", b.call)
      put_bool(o, "api_decoration_available", b.api_decoration_available)
      merge_extra(o, b.extra)
    }
    Alert(b) => {
      put_obj(o, "text", b.text, TextObject::to_json)
      put_str(o, "level", b.level)
      merge_extra(o, b.extra)
    }
    Card(b) => {
      put_obj(o, "hero_image", b.hero_image, BlockElement::to_json)
      put_obj(o, "icon", b.icon, BlockElement::to_json)
      put_json(o, "slack_icon", b.slack_icon)
      put_obj(o, "title", b.title, TextObject::to_json)
      put_obj(o, "subtitle", b.subtitle, TextObject::to_json)
      put_obj(o, "body", b.body, TextObject::to_json)
      put_obj(o, "subtext", b.subtext, TextObject::to_json)
      put_arr(o, "actions", b.actions, BlockElement::to_json)
      merge_extra(o, b.extra)
    }
    Carousel(b) => {
      put_arr(o, "elements", b.elements, LayoutBlock::to_json)
      merge_extra(o, b.extra)
    }
    ContextActions(b) => {
      put_arr(o, "elements", b.elements, BlockElement::to_json)
      merge_extra(o, b.extra)
    }
    Table(b) => {
      put_json(o, "column_settings", b.column_settings)
      put_json(o, "rows", b.rows)
      merge_extra(o, b.extra)
    }
    TaskCard(b) => {
      put_str(o, "task_id", b.task_id)
      put_str(o, "title", b.title)
      put_str(o, "status", b.status)
      put_json(o, "output", b.output)
      put_json(o, "sources", b.sources)
      merge_extra(o, b.extra)
    }
    ShareShortcut(b) => {
      put_str(o, "function_trigger_id", b.function_trigger_id)
      put_str(o, "app_id", b.app_id)
      put_bool(o, "is_workflow_app", b.is_workflow_app)
      put_int(o, "sales_home_workflow_app_type", b.sales_home_workflow_app_type)
      put_str_arr(o, "app_collaborators", b.app_collaborators)
      put_str(o, "button_label", b.button_label)
      put_str(o, "title", b.title)
      put_str(o, "description", b.description)
      put_str(o, "bot_user_id", b.bot_user_id)
      put_str(o, "url", b.url)
      put_str(o, "owning_team_id", b.owning_team_id)
      put_str(o, "workflow_id", b.workflow_id)
      put_str(o, "developer_trace_id", b.developer_trace_id)
      put_str(o, "trigger_type", b.trigger_type)
      put_str(o, "trigger_subtype", b.trigger_subtype)
      put_str(o, "share_url", b.share_url)
      merge_extra(o, b.extra)
    }
    Unknown(raw~, ..) => raw
  }
}

///|
/// Raise on the first unmodelled thing anywhere inside this block.
///
/// Outside in, so an unknown block reports as an unknown block even when it
/// also contains an unknown element -- which is what java-slack-sdk does, and
/// what its `parse_fail_on_unknown_blocks` test asserts.
pub fn LayoutBlock::validate(self : Self) -> Unit raise BlockParseError {
  match self {
    Unknown(type_=t, ..) => raise UnsupportedLayoutBlock(t)
    Section(b) => {
      validate_text_opt(b.text)
      if b.fields is Some(fields) {
        for field in fields {
          field.validate()
        }
      }
      if b.accessory is Some(e) {
        e.validate()
      }
    }
    Divider(_) => ()
    Image(b) => validate_text_opt(b.title)
    Actions(b) => validate_elements(b.elements, in_context=false)
    Context(b) => validate_elements(b.elements, in_context=true)
    Input(b) => {
      validate_text_opt(b.label)
      validate_text_opt(b.hint)
      if b.element is Some(e) {
        e.validate()
      }
    }
    Header(b) => validate_text_opt(b.text)
    File(_) => ()
    Video(b) => {
      validate_text_opt(b.title)
      validate_text_opt(b.description)
    }
    Markdown(_) => ()
    RichText(b) =>
      if b.elements is Some(elements) {
        for element in elements {
          element.validate()
        }
      }
    Call(_) => ()
    Alert(b) => validate_text_opt(b.text)
    Card(b) => {
      for t in [b.title, b.subtitle, b.body, b.subtext] {
        validate_text_opt(t)
      }
      for e in [b.hero_image, b.icon] {
        if e is Some(element) {
          element.validate()
        }
      }
      validate_elements(b.actions, in_context=false)
    }
    Carousel(b) =>
      if b.elements is Some(cards) {
        for card in cards {
          card.validate()
        }
      }
    ContextActions(b) => validate_elements(b.elements, in_context=true)
    Table(_) => ()
    TaskCard(_) => ()
    ShareShortcut(_) => ()
  }
}

///|
fn validate_elements(
  elements : Array[BlockElement]?,
  in_context~ : Bool,
) -> Unit raise BlockParseError {
  if elements is Some(list) {
    for element in list {
      element.validate(in_context~)
    }
  }
}

///|
/// An inline alert. Modals only.
///
/// https://docs.slack.dev/reference/block-kit/blocks/alert-block
pub(all) struct AlertBlock {
  block_id : String?
  text : TextObject?
  /// `default`, `info`, `warning`, `error` or `success`.
  level : String?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// A compact structured summary, on its own or inside a carousel.
///
/// https://docs.slack.dev/reference/block-kit/blocks/card-block
pub(all) struct CardBlock {
  block_id : String?
  hero_image : BlockElement?
  icon : BlockElement?
  /// A built-in Slack icon, mutually exclusive with `icon`. Raw JSON: its
  /// shape is a small enumeration Slack has not finished publishing.
  slack_icon : Json?
  title : TextObject?
  subtitle : TextObject?
  body : TextObject?
  subtext : TextObject?
  actions : Array[BlockElement]?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// A horizontally scrollable row of cards.
pub(all) struct CarouselBlock {
  block_id : String?
  /// Cards. Typed as `LayoutBlock` rather than `CardBlock` so that a carousel
  /// carrying something newer still round-trips as `Unknown` instead of
  /// failing to parse.
  elements : Array[LayoutBlock]?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// Actions attached to the context of a message rather than to its body.
pub(all) struct ContextActionsBlock {
  block_id : String?
  elements : Array[BlockElement]?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// A table.
///
/// `rows` and `column_settings` stay raw: a cell is either a `raw_text` or a
/// `rich_text`, the shape is not in the Block Kit reference, and inventing a
/// model from one fixture would be guessing. They round-trip exactly.
pub(all) struct TableBlock {
  block_id : String?
  column_settings : Json?
  rows : Json?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// Progress on a long-running task, for AI apps.
pub(all) struct TaskCardBlock {
  block_id : String?
  task_id : String?
  /// A bare string here, not a text object -- unlike every other title in
  /// Block Kit.
  title : String?
  status : String?
  /// A `rich_text` block. Raw, so the task card and the rich-text model cannot
  /// drift apart.
  output : Json?
  sources : Json?
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
/// The block Slack uses to offer a workflow for sharing.
///
/// Not in the Block Kit reference -- it is internal -- but it is 88 of the
/// blocks in the vendored corpus, so it is modelled from java-slack-sdk's
/// `ShareShortcutBlock` rather than left to `Unknown`.
pub(all) struct ShareShortcutBlock {
  block_id : String?
  function_trigger_id : String?
  app_id : String?
  is_workflow_app : Bool?
  sales_home_workflow_app_type : Int?
  app_collaborators : Array[String]?
  button_label : String?
  title : String?
  description : String?
  bot_user_id : String?
  url : String?
  owning_team_id : String?
  workflow_id : String?
  developer_trace_id : String?
  trigger_type : String?
  trigger_subtype : String?
  share_url : String?
  extra : Map[String, Json]
} derive(Eq, Debug)
