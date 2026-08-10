// Every failure this library produces.
//
// The `code()` strings are node-slack-sdk's `ErrorCode` values verbatim and
// `describe_error()` reproduces its message text, so a team migrating off the
// Node SDK keeps its log greps, its alert rules and its runbooks. The
// java-slack-sdk phrasing is available too, because it is the only one that
// surfaces `needed`/`provided` -- see `describe_error_java`.

///|
pub(all) suberror SlackError {
  /// The transport could not complete the exchange at all: DNS, TLS, a dropped
  /// connection. Nothing was learned about the request's validity.
  RequestError(String)
  /// A status Slack only uses for infrastructure failures.
  ///
  /// Slack's own refusals arrive as HTTP 200 with `{"ok": false}` and surface
  /// as `PlatformError`. A 5xx here means the request never reached the API.
  HttpError(status~ : Int, headers~ : Map[String, String], body~ : String)
  /// `{"ok": false, "error": "..."}`. A completed exchange carrying a refusal,
  /// which is a different thing from a failed exchange -- and the reason this
  /// carries the whole `ApiResponse`: `needed`, `provided` and
  /// `response_metadata.messages` are usually where the actual answer is.
  PlatformError(result~ : ApiResponse)
  /// HTTP 429 whose `Retry-After` parsed.
  RateLimitedError(retry_after~ : Int)
  FileUploadInvalidArgumentsError(String)
  FileUploadReadFileDataError(String)
} derive(Debug)

///|
/// node-slack-sdk's `ErrorCode`, verbatim.
pub fn SlackError::code(self : Self) -> String {
  match self {
    RequestError(_) => "slack_webapi_request_error"
    HttpError(..) => "slack_webapi_http_error"
    PlatformError(..) => "slack_webapi_platform_error"
    RateLimitedError(..) => "slack_webapi_rate_limited_error"
    FileUploadInvalidArgumentsError(_) =>
      "slack_webapi_file_upload_invalid_args_error"
    FileUploadReadFileDataError(_) =>
      "slack_webapi_file_upload_read_file_data_error"
  }
}

///|
pub impl Show for SlackError with fn output(self, logger) {
  logger.write_string(self.describe_error())
}

///|
/// node-slack-sdk's message text, verbatim.
pub fn SlackError::describe_error(self : Self) -> String {
  match self {
    RequestError(m) => "A request error occurred: \{m}"
    HttpError(status~, ..) =>
      "An HTTP protocol error occurred: statusCode = \{status}"
    PlatformError(result~) =>
      "An API error occurred: \{result.error.unwrap_or("")}"
    RateLimitedError(retry_after~) =>
      "A rate-limit has been reached, you may retry this request in \{retry_after} seconds"
    FileUploadInvalidArgumentsError(m) => m
    FileUploadReadFileDataError(m) => m
  }
}

///|
/// java-slack-sdk's `SlackApiException` phrasing.
///
/// Offered alongside the node one because the two ecosystems' operators
/// recognise different shapes, and because this is the only form that shows
/// `needed` and `provided` -- which, on a `missing_scope`, is the entire
/// content of the error.
pub fn SlackError::describe_error_java(self : Self) -> String {
  match self {
    PlatformError(result~) => {
      let error = result.error.unwrap_or("")
      let needed = result.needed.unwrap_or("")
      let provided = result.provided.unwrap_or("")
      let warning = result.warning.unwrap_or("")
      "status: 200, error: \{error}, needed: \{needed}, provided: \{provided}, warning: \{warning}"
    }
    HttpError(status~, body~, ..) =>
      if body.is_empty() {
        "status: \{status}, no response body"
      } else {
        "status: \{status}, body: \{body}"
      }
    _ => self.describe_error()
  }
}

///|
/// Narrow an arbitrary `Error` to a `SlackError`.
///
/// Variant patterns are the only way to match an error value -- the suberror
/// *type* name is not a pattern -- and they are only in scope inside this
/// package. Hence the helper, rather than every caller re-listing six variants.
/// The same shape as marianoguerra/mcp's `to_transport_error`.
pub fn to_slack_error(e : Error) -> SlackError {
  match e {
    RequestError(_) as t => t
    HttpError(..) as t => t
    PlatformError(..) as t => t
    RateLimitedError(..) as t => t
    FileUploadInvalidArgumentsError(_) as t => t
    FileUploadReadFileDataError(_) as t => t
    _ => RequestError(e.to_string())
  }
}
