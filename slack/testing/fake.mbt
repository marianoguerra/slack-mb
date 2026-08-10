// A scripted transport, for testing a Slack app without a Slack.
//
// marianoguerra/mcp deliberately has no mock transport: it keeps its logic pure
// and fakes the byte source instead. This module follows that rule as far as it
// goes -- the form encoder, the response envelope, the paginator and all of
// Block Kit are pure and tested with no transport at all -- and this package
// exists for the last mile, which is `Client::call` itself.
//
// It is published rather than hidden in the test tree because a consumer
// testing THEIR Slack app needs exactly this and would otherwise write it
// again, slightly worse.

///|
/// Answers a scripted list of responses in order, and remembers every request.
///
/// Running out of scripted responses is an abort rather than an error: it means
/// the test asked for a call it did not plan for, and reporting that as an HTTP
/// failure would send the code under test down its error path and hide the
/// actual mistake.
pub struct FakeTransport {
  responses : Array[@api.HttpResponse]
  /// Every request sent, in order. The whole point: assert on what went out,
  /// not only on what came back.
  sent : Array[@api.HttpRequest]
  mut index : Int
  description : String
}

///|
pub fn FakeTransport::new(
  responses : Array[@api.HttpResponse],
  description? : String = "fake transport",
) -> FakeTransport {
  { responses, sent: [], index: 0, description }
}

///|
/// A transport that answers each body with HTTP 200.
///
/// The common case by far, because Slack answers almost everything with 200 --
/// including its refusals.
pub fn FakeTransport::ok(bodies : Array[String]) -> FakeTransport {
  FakeTransport::new(bodies.map(body => json_response(body)))
}

///|
/// A 200 response carrying a JSON body.
pub fn json_response(
  body : String,
  headers? : Array[(String, String)] = [],
) -> @api.HttpResponse {
  response(200, body, headers~)
}

///|
/// A response with any status. Header names are lowercased, as a real transport
/// is required to do.
pub fn response(
  status : Int,
  body : String,
  headers? : Array[(String, String)] = [],
) -> @api.HttpResponse {
  let h : Map[String, String] = Map([])
  for entry in headers {
    h[entry.0.to_lower()] = entry.1
  }
  { status, headers: h, body }
}

///|
/// A 429 with a `Retry-After`.
pub fn rate_limited(retry_after : Int) -> @api.HttpResponse {
  response(
    429,
    (
      #|{"ok":false,"error":"ratelimited"}
    ),
    headers=[("retry-after", retry_after.to_string())],
  )
}

///|
/// One page of a cursor-paginated response.
///
/// `next_cursor` of `None` ends the walk, and so does `Some("")` -- which is
/// what Slack actually sends on the last page, and the case a paginator gets
/// wrong by looping forever.
pub fn page(
  key : String,
  items : Array[Json],
  next_cursor? : String,
) -> @api.HttpResponse {
  let body : Map[String, Json] = Map([])
  body["ok"] = Json::boolean(true)
  body[key] = Json::array(items)
  let meta : Map[String, Json] = Map([])
  if next_cursor is Some(cursor) {
    meta["next_cursor"] = Json::string(cursor)
  }
  body["response_metadata"] = Json::object(meta)
  json_response(Json::object(body).stringify())
}

///|
/// How many requests have been sent.
pub fn FakeTransport::sent_count(self : Self) -> Int {
  self.sent.length()
}

///|
/// The nth request sent, counting from zero.
pub fn FakeTransport::request(self : Self, n : Int) -> @api.HttpRequest {
  if n < 0 || n >= self.sent.length() {
    abort(
      "the fake transport was asked for request \{n} but only \{self.sent.length()} were sent",
    )
  }
  self.sent[n]
}

///|
pub fn FakeTransport::last_request(self : Self) -> @api.HttpRequest? {
  if self.sent.is_empty() {
    None
  } else {
    Some(self.sent[self.sent.length() - 1])
  }
}

///|
/// The method name of the nth request, taken from its URL. Saves every test
/// from doing the same suffix split.
pub fn FakeTransport::method_of(self : Self, n : Int) -> String {
  let url = self.request(n).url
  match url.rev_find("/") {
    Some(i) => url[i + 1:].to_owned()
    None => url
  }
}

///|
/// The form body of the nth request, decoded back to text.
pub fn FakeTransport::body_of(self : Self, n : Int) -> String {
  self.request(n).body_text()
}

///|
pub impl @api.Transport for FakeTransport with fn send(self, request) {
  self.sent.push(request)
  if self.index >= self.responses.length() {
    abort(
      "\{self.description}: request \{self.index + 1} (\{request.url}) has no scripted response; only \{self.responses.length()} were provided",
    )
  }
  let response = self.responses[self.index]
  self.index += 1
  response
}

///|
pub impl @api.Transport for FakeTransport with fn describe(self) {
  self.description
}
