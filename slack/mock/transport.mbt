// The two lines that make a `Workspace` usable as a `Client`'s transport.
//
// Everything above this file is synchronous and testable here; this is the only
// part that is not, and it is deliberately too small to have a bug in.

///|
/// A `Transport` that answers from a `Workspace`.
///
/// The mirror of `@testing.FakeTransport`: that one answers a scripted list and
/// remembers the requests, this one answers from state that the requests
/// change. Both are published for the same reason -- a consumer testing THEIR
/// Slack app needs exactly this, and would otherwise write it again, slightly
/// worse.
///
/// Which of the two to reach for: `FakeTransport` when the test is about one
/// call and the response is the fixture (a 500, a malformed body, a specific
/// `ok: false`); `MockTransport` when the test is about a sequence, and the
/// second call has to see what the first one did.
pub struct MockTransport {
  workspace : Workspace
  /// Every request sent, in order. The same assertion surface `FakeTransport`
  /// gives, so a test can move between the two without rewriting its
  /// assertions.
  sent : Array[@api.HttpRequest]
  description : String
}

///|
pub fn MockTransport::new(
  workspace : Workspace,
  description? : String = "mock slack",
) -> MockTransport {
  { workspace, sent: [], description }
}

///|
/// A transport over this workspace. The short way to write
/// `MockTransport::new(ws)`, and the one that reads well at a `Client::new`
/// call site.
pub fn Workspace::transport(self : Self) -> MockTransport {
  MockTransport::new(self)
}

///|
pub fn MockTransport::workspace(self : Self) -> Workspace {
  self.workspace
}

///|
pub fn MockTransport::sent_count(self : Self) -> Int {
  self.sent.length()
}

///|
/// The nth request sent, counting from zero.
///
/// Aborts out of range rather than returning an option, exactly as
/// `FakeTransport::request` does: asking for a request that was never sent is a
/// mistake in the test, and an option would let it be quietly ignored.
pub fn MockTransport::request(self : Self, n : Int) -> @api.HttpRequest {
  if n < 0 || n >= self.sent.length() {
    abort(
      "the mock transport was asked for request \{n} but only \{self.sent.length()} were sent",
    )
  }
  self.sent[n]
}

///|
pub fn MockTransport::last_request(self : Self) -> @api.HttpRequest? {
  if self.sent.is_empty() {
    None
  } else {
    Some(self.sent[self.sent.length() - 1])
  }
}

///|
/// The method name of the nth request, taken from its URL.
pub fn MockTransport::method_of(self : Self, n : Int) -> String {
  method_of_url(self.request(n).url)
}

///|
/// The form body of the nth request, decoded back to text.
pub fn MockTransport::body_of(self : Self, n : Int) -> String {
  self.request(n).body_text()
}

///|
pub impl @api.Transport for MockTransport with fn send(self, request) {
  self.sent.push(request)
  check_library_invariants(request)
  self.workspace.handle(request)
}

///|
pub impl @api.Transport for MockTransport with fn describe(self) {
  self.description
}

///|
/// Assert the things this LIBRARY promises about every request it builds.
///
/// Aborts rather than answering an error, because a failure here is never the
/// caller's bug: `build_request` sets all three, and if one of them is wrong
/// then every real request is wrong too and the mock is the only thing in the
/// test suite positioned to notice. Answering `invalid_auth` instead would send
/// the code under test down its error path and hide it.
fn check_library_invariants(request : @api.HttpRequest) -> Unit {
  if request.http_method != "POST" {
    abort(
      "mock slack: every Web API method is a POST, but \{request.url} arrived as \{request.http_method}",
    )
  }
  let content_type = request.headers.get("content-type").unwrap_or("(absent)")
  if content_type != "application/x-www-form-urlencoded" {
    abort(
      "mock slack: \{request.url} did not arrive as a form body; content-type was \{content_type}",
    )
  }
  // The token is a header, never a form field. node-slack-sdk has a test
  // asserting this for the same reason: a form body ends up in proxy logs and
  // crash dumps, an Authorization header is redacted by convention nearly
  // everywhere.
  if request.body_text().contains("token=") {
    abort("mock slack: \{request.url} put a token in the form body")
  }
}
