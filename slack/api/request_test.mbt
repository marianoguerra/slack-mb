// Ported from node-slack-sdk's `WebClient.test.ts` constructor and
// authorization cases (lines 67-83, 701, 1221-1249).

///|
test "the base URL gains a trailing slash so method names concatenate" {
  assert_eq(
    @api.normalize_api_url("https://slack.com/api"),
    "https://slack.com/api/",
  )
  assert_eq(
    @api.normalize_api_url("https://slack.com/api/"),
    "https://slack.com/api/",
  )
  assert_eq(
    @api.normalize_api_url("https://example.com"),
    "https://example.com/",
  )
  assert_eq(
    @api.normalize_api_url("https://example.com/slack/api"),
    "https://example.com/slack/api/",
  )
  assert_eq(@api.default_api_url, "https://slack.com/api/")
}

///|
/// Without the fixup a caller who passes `.../slack/api` posts to
/// `.../slack/apichat.postMessage` and gets a 404 naming a method they never
/// called. node-slack-sdk's constructor normalises for exactly this reason.
test "the request URL is the base plus the method name" {
  let r = @api.build_request(
    "https://slack.com/api",
    "chat.postMessage",
    @api.Params::new(),
  )
  assert_eq(r.url, "https://slack.com/api/chat.postMessage")
  assert_eq(r.http_method, "POST")
}

///|
/// The token goes in the header and NOT in the body. A form body ends up in
/// proxy access logs and crash dumps; an `Authorization` header is redacted by
/// convention nearly everywhere. node-slack-sdk asserts the same absence.
test "the token is an Authorization header and never reaches the body" {
  let p = @api.Params::new()
  p.put_str("channel", Some("C123"))
  p.put_str("text", Some("hi"))
  let r = @api.build_request(
    @api.default_api_url,
    "chat.postMessage",
    p,
    token="xoxb-not-a-real-token",
  )
  assert_eq(
    r.headers.get("authorization"),
    Some("Bearer xoxb-not-a-real-token"),
  )
  assert_eq(r.body_text(), "channel=C123&text=hi")
  assert_false(r.body_text().contains("xoxb"))
}

///|
test "a request without a token has no Authorization header" {
  let r = @api.build_request(
    @api.default_api_url,
    "api.test",
    @api.Params::new(),
  )
  assert_eq(r.headers.get("authorization"), None)
}

///|
test "the standard headers are set" {
  let r = @api.build_request(
    @api.default_api_url,
    "api.test",
    @api.Params::new(),
  )
  assert_eq(
    r.headers.get("content-type"),
    Some("application/x-www-form-urlencoded"),
  )
  assert_eq(r.headers.get("accept"), Some("application/json"))
  assert_true(r.headers.get("user-agent") is Some(_))
  assert_true(@api.user_agent.contains("marianoguerra/slack"))
}

///|
/// Header names are lowercased on the way in, so a caller's `Content-Type`
/// replaces ours instead of sitting beside it as a duplicate header.
test "extra headers are folded to lowercase" {
  let extra : Map[String, String] = Map([])
  extra["X-Custom"] = "1"
  extra["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
  let r = @api.build_request(
    @api.default_api_url,
    "api.test",
    @api.Params::new(),
    extra_headers=extra,
  )
  assert_eq(r.headers.get("x-custom"), Some("1"))
  assert_eq(
    r.headers.get("content-type"),
    Some("application/x-www-form-urlencoded; charset=utf-8"),
  )
}

///|
/// An extra header cannot clobber the token: a caller who reuses a header map
/// containing a stale `Authorization` would otherwise silently authenticate as
/// somebody else.
test "extra headers cannot override the token" {
  let extra : Map[String, String] = Map([])
  extra["Authorization"] = "Bearer stale-token"
  let r = @api.build_request(
    @api.default_api_url,
    "api.test",
    @api.Params::new(),
    token="xoxb-current",
    extra_headers=extra,
  )
  assert_eq(r.headers.get("authorization"), Some("Bearer xoxb-current"))
}

///|
/// Content-Length must be the UTF-8 byte count, not the UTF-16 string length.
/// A body with one accented character otherwise declares fewer bytes than it
/// sends and the connection fails with a body-length error -- the exact trap
/// documented in marianoguerra/mcp's HTTP transport.
test "content-length is the UTF-8 byte count" {
  let p = @api.Params::new()
  p.put_str("text", Some("São Paulo"))
  let r = @api.build_request(@api.default_api_url, "chat.postMessage", p)
  // text=S%C3%A3o%20Paulo -- 5 + 18 characters, all ASCII after encoding.
  assert_eq(r.body_text(), "text=S%C3%A3o%20Paulo")
  assert_eq(r.content_length(), r.body_text().length())
  assert_eq(
    r.headers.get("content-length"),
    Some(r.content_length().to_string()),
  )
  // And the invariant that matters: the declared length is the byte count.
  assert_eq(r.content_length(), r.body.length())
}

///|
/// The whole request is `Eq`, so a test can assert on one as a value rather
/// than picking it apart field by field.
test "requests compare by value" {
  let a = @api.build_request(
    @api.default_api_url,
    "api.test",
    @api.Params::new(),
  )
  let b = @api.build_request(
    @api.default_api_url,
    "api.test",
    @api.Params::new(),
  )
  assert_eq(a, b)
  let c = @api.build_request(
    @api.default_api_url,
    "auth.test",
    @api.Params::new(),
  )
  assert_not_eq(a, c)
}

///|
/// A custom base URL is what an enterprise proxy or a local mock server needs;
/// it must not smuggle the method name into the wrong path segment.
test "a custom base URL is honoured" {
  let r = @api.build_request(
    "http://localhost:8080/mock",
    "conversations.list",
    @api.Params::new(),
  )
  assert_eq(r.url, "http://localhost:8080/mock/conversations.list")
}
