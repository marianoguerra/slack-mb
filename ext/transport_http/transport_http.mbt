// The native HTTP transport.
//
// The only package in this repo that touches a socket, and the only one that is
// not portable -- which is exactly why it is the only thing in it. A
// `moon check --target wasm` that skips this package loses no coverage, and a
// consumer who cannot accept moonbitlang/async depends on marianoguerra/slack
// alone and writes their own `@api.Transport` over whatever their host offers.
// The trait exists for that.
//
// There are no unit tests here, deliberately. Everything this file does that
// could be checked without a server -- building the request, reading the
// envelope, deciding what a status means -- already is, in @api and @client.
// What is left is `@http.post`, and testing that would be testing
// moonbitlang/async. `ext/cmd/main` is how it gets exercised for real.

///|
pub struct HttpTransport {
  /// Only for error messages. A transport that cannot say where it was pointed
  /// makes a connection failure much harder to place.
  description : String
}

///|
pub fn HttpTransport::new(
  description? : String = "https://slack.com/api",
) -> HttpTransport {
  { description, }
}

///|
pub impl @api.Transport for HttpTransport with fn send(self, request) {
  // `Content-Length` is dropped rather than forwarded: moonbitlang/async
  // computes it from the body it is handed, and sending both risks two
  // conflicting headers on the wire. @api still computes it -- it is the UTF-8
  // byte count, and a caller inspecting a request wants to see it -- but the
  // one that reaches the socket is the transport's.
  let headers : Map[String, String] = Map([])
  for name, value in request.headers {
    if name != "content-length" {
      headers[name] = value
    }
  }
  let (response, body) = @http.post(request.url, request.body, headers~) catch {
    e => raise @api.RequestError("\{self.description}: \{describe_io_error(e)}")
  }
  // Header names are lowercased here, once, because @api's envelope reader
  // relies on it -- Slack's own casing is not stable across edges.
  let out : Map[String, String] = Map([])
  for name, value in response.headers {
    out[name.to_lower()] = value
  }
  // Lossy on purpose: a mis-encoded byte in an error page is not a reason to
  // lose the page. Slack's own responses are always valid UTF-8; the bodies
  // that are not come from proxies, and those are the ones worth reading.
  {
    status: response.code,
    headers: out,
    body: @utf8.decode_lossy(body.binary()),
  }
}

///|
pub impl @api.Transport for HttpTransport with fn describe(self) {
  self.description
}

///|
/// moonbitlang/async's I/O errors do not all implement `Show`, so this is the
/// narrowing that keeps a connection failure readable instead of printing a
/// constructor name.
fn describe_io_error(e : Error) -> String {
  e.to_string()
}
