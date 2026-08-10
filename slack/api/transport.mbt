// The seam between this library and the network.
//
// Modelled on marianoguerra/mcp's `Transport`: the trait lives in the
// dependency-free package so a js or wasm host can implement it over `fetch`,
// while marianoguerra/slack-ext/transport_http implements it over
// moonbitlang/async for native. Everything above this line is a pure function
// of bytes, which is why almost every reference SDK test ports here without a
// server.

///|
/// One outbound call, already reduced to bytes.
///
/// A struct rather than a `(method, params)` pair, because the token has been
/// lifted into a header by this point and the body has been serialised exactly
/// once. A transport that could still see the params would be free to
/// re-serialise them differently from whatever signed or measured them.
pub(all) struct HttpRequest {
  /// Absolute. `https://slack.com/api/chat.postMessage`.
  url : String
  /// `POST` for every Web API method. A field, not a constant, so the same
  /// transport can carry the `files.getUploadURLExternal` upload dance without
  /// a second trait. Spelled `http_method` because `method` is a reserved word
  /// -- and because in this library "method" already means `chat.postMessage`.
  http_method : String
  headers : Map[String, String]
  /// The already-percent-encoded form body.
  ///
  /// `Bytes` and not `String` for two reasons. `Content-Length` must be the
  /// UTF-8 byte count -- MoonBit strings are UTF-16, so a body containing one
  /// accented character would otherwise declare fewer bytes than it sends and
  /// the connection fails with a body-length error. And `files.upload` needs to
  /// carry binary someday; making that a `Bytes` now costs one line and avoids
  /// a breaking change to this trait later.
  body : Bytes
} derive(Eq, Debug)

///|
/// The body as text. For assertions and for debug logging -- never for
/// computing a length.
pub fn HttpRequest::body_text(self : Self) -> String {
  @utf8.decode_lossy(self.body[:])
}

///|
/// The UTF-8 byte count, which is what `Content-Length` must carry.
pub fn HttpRequest::content_length(self : Self) -> Int {
  self.body.length()
}

///|
pub(all) struct HttpResponse {
  status : Int
  /// Header names MUST be lowercased by the transport.
  ///
  /// Slack's own casing is not stable (`Retry-After` against `retry-after`,
  /// depending on which edge answered), and folding once at the boundary beats
  /// a case-insensitive lookup at every site that reads a header.
  headers : Map[String, String]
  body : String
} derive(Eq, Debug)

///|
pub fn HttpResponse::header(self : Self, name : String) -> String? {
  self.headers.get(name)
}

///|
/// A thing that can send a Slack request and return what came back.
///
/// Deliberately dumb: no retries, no rate limiting, no JSON. Those are decided
/// above, where they can be tested without a socket. A transport's whole job is
/// bytes out, bytes in -- and reporting the status rather than interpreting it,
/// because a Slack error arrives as HTTP 200.
pub(open) trait Transport {
  async fn send(Self, HttpRequest) -> HttpResponse
  /// Human-readable target, for error messages.
  fn describe(Self) -> String
}
