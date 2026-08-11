// The native HTTP transport.
//
//   moon add marianoguerra/slack-http
//
//   let client = @client.Client::new(@transport.HttpTransport::new(), token)
//
// Its own module rather than a package of `marianoguerra/slack`, because an
// import is module-wide: putting it there would hand moonbitlang/async to
// everyone who only wants Block Kit on wasm-gc. The whole point of the
// `@api.Transport` trait is that this is a choice -- a consumer whose host
// already has an HTTP client implements the trait over that in a dozen lines
// and never depends on this module at all.
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
