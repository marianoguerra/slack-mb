// Ported from node-slack-sdk's `WebClient.buildResult` behaviour and the
// `WebClient.test.ts` cases that assert on it.
//
// Everything here is a pure function of a status, a header map and a body
// string, which is why the whole of node's response handling ports without a
// server: `nock` was only ever supplying those three things.

///|
fn http(
  status : Int,
  body : String,
  headers? : Array[(String, String)] = [],
) -> @api.HttpResponse {
  let h : Map[String, String] = Map([])
  for entry in headers {
    h[entry.0] = entry.1
  }
  { status, headers: h, body }
}

///|
test "a plain success" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":true,"channel":"C123","ts":"1503435956.000247"}
      ),
    ),
  )
  assert_true(r.ok)
  assert_eq(r.error, None)
  assert_eq(r.get_str("channel"), Some("C123"))
  assert_eq(r.get_str("ts"), Some("1503435956.000247"))
}

///|
test "an ok:false response carries error, needed and provided" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":false,"error":"missing_scope","needed":"chat:write","provided":"identify,commands"}
      ),
    ),
  )
  assert_false(r.ok)
  assert_eq(r.error, Some("missing_scope"))
  assert_eq(r.needed, Some("chat:write"))
  assert_eq(r.provided, Some("identify,commands"))
}

///|
/// java-slack-sdk surfaces a top-level `warning`; node surfaces
/// `response_metadata.warnings`. They are different fields and Slack sends
/// both, so both are kept.
test "the top-level warning is distinct from response_metadata.warnings" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":true,"warning":"missing_charset","response_metadata":{"warnings":["missing_charset"]}}
      ),
    ),
  )
  assert_eq(r.warning, Some("missing_charset"))
  assert_eq(r.response_metadata.warnings, ["missing_charset"])
}

///|
/// node-slack-sdk: "should work even if the body is not a JSON data". A proxy
/// error page or a captive portal login screen becomes the error text rather
/// than being swallowed -- which is the difference between a five-minute
/// diagnosis and an hour of packet capture.
test "a non-JSON body becomes ok:false with the raw text as the error" {
  let r = @api.ApiResponse::of_http(http(200, "something wrong!"))
  assert_false(r.ok)
  assert_eq(r.error, Some("something wrong!"))
  assert_eq(
    @api.SlackError::PlatformError(result=r).describe_error(),
    "An API error occurred: something wrong!",
  )
}

///|
test "an empty body is not a crash" {
  let r = @api.ApiResponse::of_http(http(200, ""))
  assert_false(r.ok)
  assert_eq(r.error, Some(""))
}

///|
/// JSON that parses but is not an object -- an array, a bare string -- is not
/// something a caller can act on, so it is reported like a non-JSON body.
test "valid JSON that is not an object is still a failure" {
  let r = @api.ApiResponse::of_http(http(200, "[1,2,3]"))
  assert_false(r.ok)
  assert_eq(r.error, Some("[1,2,3]"))
}

///|
/// `ok` is `true` only when it is literally `true`. Slack has never sent
/// `"ok":"true"`, but a proxy that rewrites JSON has.
test "ok is only true when it is the boolean true" {
  for body in ["{\"ok\":true}", "{\"ok\":true,\"x\":1}"] {
    assert_true(@api.ApiResponse::of_http(http(200, body)).ok, msg=body)
  }
  for
    body in [
      "{\"ok\":false}", "{\"ok\":\"true\"}", "{\"ok\":1}", "{\"ok\":null}", "{}",
    ] {
    assert_false(@api.ApiResponse::of_http(http(200, body)).ok, msg=body)
  }
}

///|
/// node-slack-sdk synthesises an empty `response_metadata` when the field is
/// absent, so that reading `next_cursor` never needs a guard.
test "response_metadata is always present" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":true}
      ),
    ),
  )
  assert_eq(r.response_metadata.next_cursor, None)
  assert_eq(r.response_metadata.warnings, [])
  assert_eq(r.response_metadata.messages, [])
}

///|
test "next_cursor is read from response_metadata" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":true,"response_metadata":{"next_cursor":"dGVhbTpDMDYxRkE1UEI="}}
      ),
    ),
  )
  assert_eq(r.response_metadata.next_cursor, Some("dGVhbTpDMDYxRkE1UEI="))
}

///|
/// node-slack-sdk: "should send warnings to logs from both
/// response_metadata.warnings & response_metadata.messages". The fixture is
/// node's, verbatim -- two warnings, one `[ERROR]` message and one `[WARN]`.
test "diagnostics split messages by their prefix" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":true,"response_metadata":{"warnings":["testWarning1","testWarning2"],
        #|"messages":["[ERROR] unsupported type: sections [json-pointer:/blocks/0/type]",
        #|"[WARN] A Content-Type HTTP header was presented but did not declare a charset, such as a 'utf-8'"]}}
      ),
    ),
  )
  assert_eq(r.response_metadata.warnings, ["testWarning1", "testWarning2"])
  let diags = r.response_metadata.diagnostics()
  assert_eq(diags.length(), 2)
  assert_eq(diags[0].0, @api.Severity::Err)
  assert_eq(
    diags[0].1,
    "unsupported type: sections [json-pointer:/blocks/0/type]",
  )
  assert_eq(diags[1].0, @api.Severity::Warn)
  assert_true(diags[1].1.has_prefix("A Content-Type HTTP header"))
}

///|
/// An unprefixed message is a warning: Slack chose to tell you about it, and
/// silently discarding it would be worse than over-reporting.
test "an unprefixed message is treated as a warning" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":true,"response_metadata":{"messages":["something happened"]}}
      ),
    ),
  )
  let diags = r.response_metadata.diagnostics()
  assert_eq(diags, [(@api.Severity::Warn, "something happened")])
}

///|
/// node-slack-sdk: "with OAuth scopes in the response headers". The split is
/// `/\s*,\s*/` after a trim, so a header formatted by hand still parses.
test "x-oauth-scopes is split on commas, ignoring space" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":true}
      ),
      headers=[
        ("x-oauth-scopes", "files:read, chat:write:bot"),
        ("x-accepted-oauth-scopes", "files:read"),
      ],
    ),
  )
  assert_eq(r.response_metadata.scopes, ["files:read", "chat:write:bot"])
  assert_eq(r.response_metadata.accepted_scopes, ["files:read"])
}

///|
test "scope splitting tolerates stray whitespace and empty headers" {
  assert_eq(@api.split_scopes("a,b"), ["a", "b"])
  assert_eq(@api.split_scopes("a , b"), ["a", "b"])
  assert_eq(@api.split_scopes("  a,b  "), ["a", "b"])
  assert_eq(@api.split_scopes("a"), ["a"])
  assert_eq(@api.split_scopes(""), [])
  assert_eq(@api.split_scopes("   "), [])
  // A trailing comma yields no phantom empty scope.
  assert_eq(@api.split_scopes("a,b,"), ["a", "b"])
}

///|
/// node-slack-sdk attaches `retryAfter` regardless of status, and its test
/// asserts it on a 200: Slack advises a backoff before it starts enforcing one,
/// and a client that only reads 429s throws that warning away.
test "retry-after is read even from a 200" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":true}
      ),
      headers=[("retry-after", "100")],
    ),
  )
  assert_eq(r.response_metadata.retry_after, Some(100))
}

///|
/// `Number.parseInt` semantics, including the part that matters: an
/// unparseable header is `None`, never `0`. Zero would mean "retry
/// immediately", the worst possible reading of a header you failed to
/// understand.
test "retry-after parsing follows parseInt" {
  assert_eq(@api.parse_retry_after("30"), Some(30))
  assert_eq(@api.parse_retry_after("  30  "), Some(30))
  assert_eq(@api.parse_retry_after("120s"), Some(120))
  assert_eq(@api.parse_retry_after("0"), Some(0))
  assert_eq(@api.parse_retry_after("notanumber"), None)
  assert_eq(@api.parse_retry_after(""), None)
  assert_eq(@api.parse_retry_after("-5"), None)
  assert_eq(@api.parse_retry_after("Wed, 21 Oct 2015 07:28:00 GMT"), None)
}

///|
/// Unknown keys inside `response_metadata` are kept rather than dropped: Slack
/// adds fields there faster than any SDK adopts them, and a caller who needs
/// one should not have to wait for a release.
test "unknown response_metadata keys survive in extra" {
  let r = @api.ApiResponse::of_http(
    http(
      200,
      (
        #|{"ok":true,"response_metadata":{"next_cursor":"c1","future_field":{"a":1}}}
      ),
    ),
  )
  assert_eq(r.response_metadata.next_cursor, Some("c1"))
  assert_eq(r.response_metadata.extra.get("future_field"), Some({ "a": 1 }))
  assert_eq(r.response_metadata.extra.get("next_cursor"), None)
}

///|
/// The `raw` field is the escape hatch that makes 260 un-modelled methods
/// usable: whatever this library has not typed yet is one lookup away.
test "raw keeps the whole body" {
  let body =
    #|{"ok":true,"team":{"id":"T123","name":"Example","icon":{"image_34":"https://a.slack-edge.com/x.png"}}}
  let r = @api.ApiResponse::of_http(http(200, body))
  guard r.get("team") is Some(Object(team)) else {
    fail("expected a team object")
  }
  assert_eq(team.get("name"), Some(Json::string("Example")))
  assert_eq(r.raw, @json.parse(body))
}

///|
/// `of_json` is the same decoder without the HTTP layer, so the corpus tests
/// and the paginator can use it on JSON they already have.
test "of_json agrees with of_http on the body" {
  let body =
    #|{"ok":true,"response_metadata":{"next_cursor":"x"}}
  let from_json = @api.ApiResponse::of_json(@json.parse(body))
  let from_http = @api.ApiResponse::of_http(http(200, body))
  assert_eq(from_json.ok, from_http.ok)
  assert_eq(
    from_json.response_metadata.next_cursor,
    from_http.response_metadata.next_cursor,
  )
}
