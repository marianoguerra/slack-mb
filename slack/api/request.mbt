// Building the outbound request.

///|
pub let default_api_url : String = "https://slack.com/api/"

///|
/// The library's own User-Agent contribution.
///
/// java-slack-sdk sends `Java-Slack-SDK; slack-api-client/<ver>; ...` and
/// node-slack-sdk sends `@slack:web-api/<ver> node/<ver> darwin/<ver>`; both
/// name the SDK first and then the runtime. There is no runtime to name here
/// that is true on all four backends, so this is the SDK part alone and a
/// caller who wants to add `myapp/1.2.3` passes it as an extra header.
pub let user_agent : String = "MoonBit-Slack-SDK; marianoguerra/slack/0.2.0"

///|
/// Ensure the base URL ends in `/`, so that `base + method` is a URL.
///
/// node-slack-sdk's constructor does exactly this, and node's own tests cover
/// it: without the fixup, a caller who passes `https://example.com/slack/api`
/// silently posts to `https://example.com/slack/apichat.postMessage` and gets a
/// 404 that names a method they never called.
pub fn normalize_api_url(url : String) -> String {
  if url.has_suffix("/") {
    url
  } else {
    url + "/"
  }
}

///|
/// Assemble one Web API request.
///
/// The token becomes `Authorization: Bearer` and is never written into the
/// body. That is not a style choice: a form body ends up in proxy access logs,
/// crash dumps and error trackers, whereas an `Authorization` header is
/// redacted by convention nearly everywhere. node-slack-sdk has a test
/// asserting the token is absent from the body for exactly this reason.
pub fn build_request(
  base_url : String,
  api_method : String,
  params : Params,
  token? : String,
  extra_headers? : Map[String, String] = Map([]),
  bool_style? : BoolStyle = TrueFalse,
) -> HttpRequest {
  let body = @utf8.encode(encode_form(params, bool_style~))
  let headers : Map[String, String] = Map([])
  headers["content-type"] = "application/x-www-form-urlencoded"
  headers["accept"] = "application/json"
  headers["user-agent"] = user_agent
  // Set before the token, so a caller cannot accidentally clobber the
  // Authorization header with a stale one from a header map they reused.
  for name, value in extra_headers {
    headers[name.to_lower()] = value
  }
  if token is Some(t) {
    headers["authorization"] = "Bearer \{t}"
  }
  headers["content-length"] = body.length().to_string()
  {
    url: normalize_api_url(base_url) + api_method,
    http_method: "POST",
    headers,
    body,
  }
}
