// Ported from node-slack-sdk's `errors.ts` and java-slack-sdk's
// `SlackApiException`.
//
// Error codes and message text are API. A team migrating from the Node SDK has
// log queries, alert rules and runbooks keyed on these exact strings, and
// changing them silently would break monitoring rather than code -- the kind of
// break nobody notices until an incident.

///|
fn platform_error(body : String) -> @api.SlackError {
  let json = @json.parse(body) catch {
    _ => abort("bad JSON in test data: \{body}")
  }
  @api.SlackError::PlatformError(result=@api.ApiResponse::of_json(json))
}

///|
/// node-slack-sdk's `ErrorCode` enum, verbatim.
test "error codes match node-slack-sdk" {
  assert_eq(
    @api.SlackError::RequestError("x").code(),
    "slack_webapi_request_error",
  )
  assert_eq(
    @api.SlackError::HttpError(status=500, headers=Map([]), body="").code(),
    "slack_webapi_http_error",
  )
  assert_eq(
    platform_error("{\"ok\":false,\"error\":\"x\"}").code(),
    "slack_webapi_platform_error",
  )
  assert_eq(
    @api.SlackError::RateLimitedError(retry_after=5).code(),
    "slack_webapi_rate_limited_error",
  )
  assert_eq(
    @api.SlackError::FileUploadInvalidArgumentsError("x").code(),
    "slack_webapi_file_upload_invalid_args_error",
  )
  assert_eq(
    @api.SlackError::FileUploadReadFileDataError("x").code(),
    "slack_webapi_file_upload_read_file_data_error",
  )
}

///|
/// node-slack-sdk's message templates, verbatim.
test "error messages match node-slack-sdk" {
  assert_eq(
    @api.SlackError::RequestError("socket hang up").describe_error(),
    "A request error occurred: socket hang up",
  )
  assert_eq(
    @api.SlackError::HttpError(status=500, headers=Map([]), body="").describe_error(),
    "An HTTP protocol error occurred: statusCode = 500",
  )
  assert_eq(
    platform_error("{\"ok\":false,\"error\":\"channel_not_found\"}").describe_error(),
    "An API error occurred: channel_not_found",
  )
  assert_eq(
    @api.SlackError::RateLimitedError(retry_after=5).describe_error(),
    "A rate-limit has been reached, you may retry this request in 5 seconds",
  )
}

///|
/// `Show` is the message, so string interpolation of an error in a log line
/// says something useful rather than printing a constructor.
test "Show is the message" {
  let e = @api.SlackError::RateLimitedError(retry_after=30)
  assert_eq(
    "\{e}",
    "A rate-limit has been reached, you may retry this request in 30 seconds",
  )
}

///|
/// java-slack-sdk's phrasing, which is the only one that shows `needed` and
/// `provided` -- on a `missing_scope`, those two fields ARE the error.
test "the java phrasing surfaces needed and provided" {
  let e = platform_error(
    (
      #|{"ok":false,"error":"missing_scope","needed":"chat:write","provided":"identify"}
    ),
  )
  assert_eq(
    e.describe_error_java(),
    "status: 200, error: missing_scope, needed: chat:write, provided: identify, warning: ",
  )
}

///|
/// java-slack-sdk's "no response body" form, for a failure with nothing to say.
test "an empty HTTP error body says so" {
  assert_eq(
    @api.SlackError::HttpError(status=503, headers=Map([]), body="").describe_error_java(),
    "status: 503, no response body",
  )
  assert_eq(
    @api.SlackError::HttpError(status=502, headers=Map([]), body="<html>").describe_error_java(),
    "status: 502, body: <html>",
  )
}

///|
/// A `PlatformError` carries the whole response, not just the error string,
/// because `response_metadata.messages` is usually where the actual answer is
/// -- "invalid_blocks" tells you nothing, the message names the block.
test "a platform error keeps the diagnostics that explain it" {
  let e = platform_error(
    (
      #|{"ok":false,"error":"invalid_blocks","response_metadata":{"messages":["[ERROR] unsupported type: sections [json-pointer:/blocks/0/type]"]}}
    ),
  )
  guard e is PlatformError(result~) else { fail("expected a platform error") }
  let diags = result.response_metadata.diagnostics()
  assert_eq(diags.length(), 1)
  assert_eq(diags[0].0, @api.Severity::Err)
  assert_true(diags[0].1.contains("/blocks/0/type"))
}

///|
/// The narrowing helper exists because a suberror's *type* name is not a
/// pattern, so a caller outside this package cannot match the variants at all.
test "to_slack_error passes SlackErrors through and wraps everything else" {
  let original = @api.SlackError::RateLimitedError(retry_after=7)
  guard @api.to_slack_error(original) is RateLimitedError(retry_after~) else {
    fail("expected the error to pass through unchanged")
  }
  assert_eq(retry_after, 7)
  // Something from another package becomes a RequestError rather than being
  // lost: the transport is where foreign errors come from.
  let foreign = try @json.parse("{oops") catch {
    e => e
  } noraise {
    _ => abort("expected a parse failure")
  }
  guard @api.to_slack_error(foreign) is RequestError(_) else {
    fail("expected a foreign error to be wrapped")
  }
}
