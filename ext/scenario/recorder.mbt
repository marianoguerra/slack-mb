// Recording a run, so a later one can be compared against it.
//
// A wrapper rather than a hook inside the scenario, so that recording stays a
// transport concern and `run` stays a plain consumer of a `Client`: the same
// `RecordingTransport` wraps @transport for a real recording and
// @mock.MockTransport for the mock's, and neither knows.

///|
/// One request and what came back.
pub struct Exchange {
  api_method : String
  /// The decoded form body -- via `@api.decode_form`, which exists for the
  /// mock and earns its keep a second time here.
  form : Array[(String, String)]
  status : Int
  body : Json
}

///|
pub fn Exchange::api_method(self : Self) -> String {
  self.api_method
}

///|
pub fn Exchange::status(self : Self) -> Int {
  self.status
}

///|
pub fn Exchange::body(self : Self) -> Json {
  self.body
}

///|
pub fn Exchange::form(self : Self) -> Array[(String, String)] {
  self.form
}

///|
/// A `Transport` that remembers every exchange and forwards it.
pub struct RecordingTransport {
  inner : &@api.Transport
  exchanges : Array[Exchange]
}

///|
pub fn RecordingTransport::new(inner : &@api.Transport) -> RecordingTransport {
  { inner, exchanges: [] }
}

///|
pub fn RecordingTransport::exchanges(self : Self) -> Array[Exchange] {
  self.exchanges
}

///|
/// The methods called, in order. The cheapest of the three comparisons in the
/// replay diff, and the one that localises the other two when it fails.
pub fn RecordingTransport::methods(self : Self) -> Array[String] {
  self.exchanges.map(e => e.api_method)
}

///|
pub impl @api.Transport for RecordingTransport with fn send(self, request) {
  let response = self.inner.send(request)
  let body = @json.parse(response.body) catch {
    // A non-JSON body is recorded as the string it was, rather than dropped:
    // a captive portal's login page is exactly the kind of thing worth having
    // in a recording.
    _ => Json::string(response.body)
  }
  self.exchanges.push({
    api_method: method_of_url(request.url),
    form: @api.decode_form(request.body_text()),
    status: response.status,
    body,
  })
  response
}

///|
pub impl @api.Transport for RecordingTransport with fn describe(self) {
  "recording " + self.inner.describe()
}

///|
fn method_of_url(url : String) -> String {
  match url.rev_find("/") {
    Some(i) => url[i + 1:].to_owned()
    None => url
  }
}

///|
/// The whole recording, scrubbed, ready to be written to disk or compared.
///
/// Scrubbed by construction rather than on the way out: a recording of a real
/// workspace holds real channel names and real user ids, and a file in this
/// repository must not.
pub fn RecordingTransport::to_json(self : Self, scrub? : Bool = true) -> Json {
  let out : Array[Json] = []
  for exchange in self.exchanges {
    let form : Array[Json] = exchange.form.map(pair => {
      Json::array([
        Json::string(pair.0),
        Json::string(if scrub { scrub_text(pair.1) } else { pair.1 }),
      ])
    })
    out.push(
      Json::object({
        "method": Json::string(exchange.api_method),
        "form": Json::array(form),
        "status": Json::number(
          exchange.status.to_double(),
          repr=exchange.status.to_string(),
        ),
        "body": if scrub {
          scrub_json(exchange.body)
        } else {
          exchange.body
        },
      }),
    )
  }
  Json::object({ "exchanges": Json::array(out) })
}

///|
/// Read a recording back.
pub fn exchanges_of_json(recording : Json) -> Array[Exchange] {
  let out : Array[Exchange] = []
  guard recording is Object(root) &&
    root.get("exchanges") is Some(Array(entries)) else {
    return out
  }
  for entry in entries {
    guard entry is Object(fields) else { continue }
    guard fields.get("method") is Some(String(api_method)) else { continue }
    let form : Array[(String, String)] = []
    if fields.get("form") is Some(Array(pairs)) {
      for pair in pairs {
        if pair is Array(kv) &&
          kv.length() == 2 &&
          kv[0] is String(k) &&
          kv[1] is String(v) {
          form.push((k, v))
        }
      }
    }
    let status = match fields.get("status") {
      Some(Number(n, ..)) => n.to_int()
      _ => 200
    }
    out.push({
      api_method,
      form,
      status,
      body: fields.get("body").unwrap_or(Json::null()),
    })
  }
  out
}
