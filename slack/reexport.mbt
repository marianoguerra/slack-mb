// Type aliases, so a consumer can name this library's types without importing
// five packages to write one signature.
//
// Only types and traits: MoonBit does not re-export enum CONSTRUCTORS, so
// `@slack.LayoutBlock` names the type while building one still needs
// `marianoguerra/slack/blocks` in scope. That asymmetry is why the README's
// examples import the packages directly rather than going through here.

///|
pub using @api {
  type ApiResponse,
  type ResponseMetadata,
  type Severity,
  type HttpRequest,
  type HttpResponse,
  type ParamValue,
  type Params,
  type BoolStyle,
  type SlackError,
  trait Transport,
}

///|
pub using @client {type Client, type Paginator}

///|
pub using @blocks {
  type LayoutBlock,
  type BlockElement,
  type TextObject,
  type TextKind,
  type RichTextItem,
  type RichTextBlockElement,
  type UnknownPolicy,
  type BlockParseError,
}

///|
pub using @methods {type RateLimitTier}

///|
/// The high-level client, which answers the types below instead of an
/// envelope. `@typed.Api::of(client)` is how a caller reaches it.
pub using @typed {type Api, type Page, type Posted, type TypedError}

///|
/// The domain model. Unlike the Block Kit types above, these are plain structs
/// with no constructors to lose, so naming one here is the whole of what a
/// consumer needs -- `@slack.User` reads a `users.info` response without
/// importing anything else.
pub using @model {
  type User,
  type Profile,
  type Channel,
  type ChannelText,
  type Message,
  type Edited,
  type Reaction,
  type BotProfile,
  type Team,
  type Usergroup,
  type View,
  type File,
}
