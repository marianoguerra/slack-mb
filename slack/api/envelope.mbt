// The response envelope every Slack Web API method shares.
//
// The shape is `{"ok": true, ...}` or `{"ok": false, "error": "..."}`, always
// with HTTP 200. A non-200 from `slack.com/api` means infrastructure, not a
// refusal -- which is why `ok` and the status code are two separate questions
// throughout this library.

///|
/// The `response_metadata` object, plus the three things Slack puts in headers
/// rather than in the body.
///
/// Merging the headers in here follows node-slack-sdk: a caller who has to
/// reach back into the raw response to find out which scopes their token was
/// missing will simply not bother, and the whole point of `needed`/`provided`
/// and `scopes` is to make that diagnosable.
pub(all) struct ResponseMetadata {
  /// The cursor for the next page. Absent OR empty means "no more pages" --
  /// Slack sends `""` at the end, and treating that as a cursor is an infinite
  /// loop. See `Paginator` in @client.
  next_cursor : String?
  warnings : Array[String]
  /// Free-form diagnostics, each prefixed `[ERROR]` or `[WARN]`. This is where
  /// "unsupported type: sections [json-pointer:/blocks/0/type]" arrives -- on
  /// an `"ok": true` response. See `diagnostics`.
  messages : Array[String]
  /// From the `x-oauth-scopes` header: what the token actually has.
  scopes : Array[String]
  /// From `x-accepted-oauth-scopes`: what this method would accept.
  accepted_scopes : Array[String]
  /// From `retry-after`. Present on a 200 as well as a 429, following
  /// node-slack-sdk -- Slack sometimes advises a backoff before it starts
  /// enforcing one, and a client that only looks at 429s throws that away.
  retry_after : Int?
  /// Any other key inside `response_metadata`.
  extra : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn ResponseMetadata::empty() -> ResponseMetadata {
  {
    next_cursor: None,
    warnings: [],
    messages: [],
    scopes: [],
    accepted_scopes: [],
    retry_after: None,
    extra: Map([]),
  }
}

///|
/// How seriously Slack meant a `response_metadata.messages` entry.
pub(all) enum Severity {
  Err
  Warn
} derive(Eq, Debug)

///|
/// Prints as `ERROR` / `WARN` -- the prefixes Slack itself uses in
/// `response_metadata.messages`, so a line logged from here reads the same way
/// as the line Slack sent.
pub impl Show for Severity with fn output(self, logger) {
  logger.write_string(
    match self {
      Err => "ERROR"
      Warn => "WARN"
    },
  )
}

///|
/// Split `messages` into `(severity, text)` pairs.
///
/// Returned rather than logged. This library has no logger -- node-slack-sdk's
/// equivalent writes to one and a caller who wants to fail the request on an
/// `[ERROR]` has to intercept logging to find out. An entry with no recognised
/// prefix is a `Warn`, which is the safer default for something Slack chose to
/// tell you about.
pub fn ResponseMetadata::diagnostics(self : Self) -> Array[(Severity, String)] {
  let out = []
  for m in self.messages {
    if m.has_prefix("[ERROR]") {
      out.push((Severity::Err, m[7:].trim().to_owned()))
    } else if m.has_prefix("[WARN]") {
      out.push((Severity::Warn, m[6:].trim().to_owned()))
    } else {
      out.push((Severity::Warn, m))
    }
  }
  out
}

///|
/// One decoded Slack response.
pub(all) struct ApiResponse {
  ok : Bool
  error : String?
  /// The top-level `warning` field, which is a different thing from
  /// `response_metadata.warnings` and is what java-slack-sdk surfaces.
  warning : String?
  /// On `missing_scope`: the scope this method wanted.
  needed : String?
  /// On `missing_scope`: the scopes the token had.
  provided : String?
  response_metadata : ResponseMetadata
  /// The whole decoded body.
  ///
  /// Every field above is a convenience view of this, and every typed accessor
  /// this library has not written yet is one `raw` lookup away. That is the
  /// deal that keeps 260-odd methods reachable without 260 response types.
  raw : Json
} derive(Eq, Debug)

///|
/// Read a field out of the raw body.
pub fn ApiResponse::get(self : Self, key : String) -> Json? {
  guard self.raw is Object(o) else { return None }
  o.get(key)
}

///|
/// Read a string field out of the raw body, `None` if absent or not a string.
pub fn ApiResponse::get_str(self : Self, key : String) -> String? {
  match self.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// Decode a response body, merging in the headers Slack answers with.
///
/// Never raises. A body that is not JSON becomes `{ok: false, error: <the raw
/// text>}` -- node-slack-sdk's behaviour, and the right one: a proxy's HTML
/// error page or a captive portal's login screen is far more useful surfaced as
/// the error than swallowed into "malformed response".
pub fn ApiResponse::of_http(resp : HttpResponse) -> ApiResponse {
  let body = @json.parse(resp.body) catch {
    _ =>
      Json::object({
        "ok": Json::boolean(false),
        "error": Json::string(resp.body),
      })
  }
  let base = ApiResponse::of_json(body)
  let meta = base.response_metadata
  if resp.header("x-oauth-scopes") is Some(v) {
    meta.scopes.append(split_scopes(v))
  }
  if resp.header("x-accepted-oauth-scopes") is Some(v) {
    meta.accepted_scopes.append(split_scopes(v))
  }
  let retry_after = match resp.header("retry-after") {
    Some(v) => parse_retry_after(v)
    None => meta.retry_after
  }
  { ..base, response_metadata: { ..meta, retry_after, } }
}

///|
/// Decode an already-parsed body. Split out from `of_http` because the corpus
/// tests and the paginator both work from JSON with no HTTP around it.
pub fn ApiResponse::of_json(body : Json) -> ApiResponse {
  guard body is Object(o) else {
    // A bare array or string where an object was promised. Not JSON we can act
    // on, so it is reported the same way a non-JSON body is.
    return {
      ok: false,
      error: Some(body.stringify()),
      warning: None,
      needed: None,
      provided: None,
      response_metadata: ResponseMetadata::empty(),
      raw: body,
    }
  }
  {
    ok: match o.get("ok") {
      Some(True) => true
      _ => false
    },
    error: str_of(o, "error"),
    warning: str_of(o, "warning"),
    needed: str_of(o, "needed"),
    provided: str_of(o, "provided"),
    response_metadata: match o.get("response_metadata") {
      Some(Object(m)) => metadata_of(m)
      // node-slack-sdk synthesises `{}` when the field is absent, so that a
      // caller can always read `response_metadata.next_cursor` without a guard.
      _ => ResponseMetadata::empty()
    },
    raw: body,
  }
}

///|
let metadata_known_fields : Array[String] = [
  "next_cursor", "warnings", "messages",
]

///|
fn metadata_of(m : Map[String, Json]) -> ResponseMetadata {
  let extra : Map[String, Json] = Map([])
  for key, value in m {
    if !metadata_known_fields.contains(key) {
      extra[key] = value
    }
  }
  {
    next_cursor: str_of(m, "next_cursor"),
    warnings: str_array_of(m, "warnings"),
    messages: str_array_of(m, "messages"),
    scopes: [],
    accepted_scopes: [],
    retry_after: None,
    extra,
  }
}

///|
fn str_of(o : Map[String, Json], key : String) -> String? {
  match o.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn str_array_of(o : Map[String, Json], key : String) -> Array[String] {
  let out = []
  if o.get(key) is Some(Array(items)) {
    for item in items {
      if item is String(s) {
        out.push(s)
      }
    }
  }
  out
}

///|
/// Split an `x-oauth-scopes`-style header on commas, ignoring surrounding
/// space.
///
/// Exposed because the rule (`/\s*,\s*/` after a trim, per node-slack-sdk) is
/// exactly the kind of thing a caller re-derives slightly wrong and then
/// compares against a scope name with a stray space in it.
pub fn split_scopes(header : String) -> Array[String] {
  let out = []
  for part in header.trim().split(",") {
    let s = part.trim().to_owned()
    if !s.is_empty() {
      out.push(s)
    }
  }
  out
}

///|
/// Parse a `Retry-After` header holding a delay in seconds.
///
/// Prefix-greedy and lenient, matching node-slack-sdk's `Number.parseInt`:
/// `"120"` and `"120s"` are both 120, and anything that does not start with a
/// digit is `None` rather than zero. Zero would mean "retry immediately",
/// which is the worst possible reading of a header you failed to understand.
///
/// Slack always sends seconds here. The HTTP-date form the RFC also allows is
/// deliberately not supported: parsing it would need a clock, and this package
/// does not have one.
pub fn parse_retry_after(header : String) -> Int? {
  let s = header.trim()
  let mut i = 0
  let mut value = 0
  let mut digits = 0
  while i < s.length() {
    let c = s[i].to_int()
    if c < '0'.to_int() || c > '9'.to_int() {
      break
    }
    value = value * 10 + (c - '0'.to_int())
    digits += 1
    i += 1
  }
  if digits == 0 {
    None
  } else {
    Some(value)
  }
}
