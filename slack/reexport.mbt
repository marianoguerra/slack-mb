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
