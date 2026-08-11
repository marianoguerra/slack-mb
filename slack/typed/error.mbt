// What a typed call can fail with.
//
// Two cases, and they are not the same kind of thing. `Slack` is every failure
// @client already had -- a refusal, a 429, a dropped socket -- passed through
// untouched. `ResponseShapeError` is this layer's own: Slack answered `ok:
// true` and the payload was not the shape @model claims.
//
// A separate type rather than a seventh `@api.SlackError` variant on purpose.
// That taxonomy's `code()` strings are node-slack-sdk's `ErrorCode` values
// verbatim and its messages are node's message text, so that a team migrating
// off the Node SDK keeps its log greps and its alert rules. There is no node
// counterpart to borrow for this, and inventing one would make @api's claim to
// be a faithful port false for the sake of a case that should never happen.

///|
/// A typed call's failure.
pub(all) suberror TypedError {
  /// Everything the low-level client could already fail with, unchanged.
  Slack(@api.SlackError)
  /// `ok: true`, and then a payload this version cannot read: the key absent,
  /// or holding something the entity refused.
  ///
  /// It should never happen against Slack -- removing `user` from
  /// `users.info` would break every SDK at once. It happens against a
  /// proxy that rewrites responses, a stub someone wrote by hand, or a
  /// `@model` that has fallen behind. Naming the method and the key is the
  /// whole of what makes that diagnosable.
  ResponseShapeError(api_method~ : String, key~ : String)
} derive(Debug)

///|
pub impl Show for TypedError with fn output(self, logger) {
  logger.write_string(self.describe_error())
}

///|
/// node-slack-sdk's `ErrorCode` for the wrapped case, and this package's own
/// for the case node has no name for.
pub fn TypedError::code(self : Self) -> String {
  match self {
    Slack(e) => e.code()
    ResponseShapeError(..) => "slack_response_shape_error"
  }
}

///|
pub fn TypedError::describe_error(self : Self) -> String {
  match self {
    Slack(e) => e.describe_error()
    ResponseShapeError(api_method~, key~) =>
      "\{api_method} answered ok, but '\{key}' was missing or not the shape this version models"
  }
}

///|
/// The wrapped `SlackError`, for the cases that actually happen.
///
/// `ResponseShapeError` is the rare one and the wrapping puts it in the way of
/// the common ones, so this is the shortcut: `if e.slack() is Some(err)` gets
/// back to a rate limit or a `missing_scope` in one step.
pub fn TypedError::slack(self : Self) -> @api.SlackError? {
  match self {
    Slack(e) => Some(e)
    ResponseShapeError(..) => None
  }
}

///|
/// Narrow an arbitrary `Error` to a `TypedError`.
///
/// Variant patterns are the only way to match an error value and they are only
/// in scope in the package that declares them, so a caller outside this one
/// cannot take a `TypedError` apart from an `Error` without this. The same
/// shape as `@api.to_slack_error`, which it delegates to.
pub fn to_typed_error(e : Error) -> TypedError {
  match e {
    Slack(_) as t => t
    ResponseShapeError(..) as t => t
    other => Slack(@api.to_slack_error(other))
  }
}
