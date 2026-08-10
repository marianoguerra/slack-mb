// The client.
//
// It composes @api (bytes in, bytes out), @blocks (the message model) and
// @methods (the name and tier table), and it holds a `&Transport` rather than a
// socket -- so a browser host supplies `fetch`, a native host supplies
// marianoguerra/slack-ext/transport_http, and a test supplies
// @testing.FakeTransport.
//
// What it deliberately does NOT do is throttle or retry. Both need to sleep,
// sleeping needs an async runtime, and depending on one would make this package
// native-only -- which would put Block Kit and signature verification out of
// reach of a wasm-hosted app for the sake of two features a caller can drive
// themselves. `@ratectl` computes the delay; the caller waits it.

///|
pub struct Client {
  transport : &@api.Transport
  token : String
  base_url : String
  /// `TrueFalse` (node-slack-sdk) unless a caller has a reason.
  bool_style : @api.BoolStyle
  /// Merged into every request. A caller's `User-Agent` addition goes here.
  extra_headers : Map[String, String]
  /// Sent as `team_id` on every call, for an org-wide app that must say which
  /// workspace it means.
  team_id : String?
}

///|
pub fn Client::new(
  transport : &@api.Transport,
  token : String,
  base_url? : String = @api.default_api_url,
  bool_style? : @api.BoolStyle = TrueFalse,
  extra_headers? : Map[String, String] = Map([]),
  team_id? : String,
) -> Client {
  { transport, token, base_url, bool_style, extra_headers, team_id }
}

///|
/// Call any Web API method.
///
/// The escape hatch that keeps all 326 methods reachable: the typed builders
/// below cover the families most apps use, and everything else is this.
///
/// Raises rather than returning `ok: false` as a value. A refusal from Slack is
/// an error in every sense that matters to a caller -- they asked for something
/// and did not get it -- and making it a return value means every call site
/// either checks or silently proceeds on a message that was never posted.
/// `PlatformError` carries the whole response for the cases that want it.
pub async fn Client::call(
  self : Self,
  api_method : String,
  params : @api.Params,
) -> @api.ApiResponse raise @api.SlackError {
  let with_team = if self.team_id is Some(id) {
    let merged = @api.Params::new()
    for entry in params.entries {
      merged.put(entry.0, entry.1)
    }
    if !params.entries.iter().any(e => e.0 == "team_id") {
      merged.put_str("team_id", Some(id))
    }
    merged
  } else {
    params
  }
  let request = @api.build_request(
    self.base_url,
    api_method,
    with_team,
    token=self.token,
    extra_headers=self.extra_headers,
    bool_style=self.bool_style,
  )
  let response = self.transport.send(request) catch {
    e => raise @api.to_slack_error(e)
  }
  self.interpret(response)
}

///|
/// Turn one HTTP response into a result or an error.
///
/// Separate from `call` and synchronous, so the status-handling rules are
/// testable without a transport at all.
pub fn Client::interpret(
  self : Self,
  response : @api.HttpResponse,
) -> @api.ApiResponse raise @api.SlackError {
  ignore(self)
  interpret_response(response)
}

///|
/// The rules, as a free function.
///
/// Slack answers a refusal with HTTP 200 and `{"ok": false}`, so the status
/// code and `ok` are two different questions: 429 and 5xx are infrastructure,
/// `ok: false` is Slack declining.
pub fn interpret_response(
  response : @api.HttpResponse,
) -> @api.ApiResponse raise @api.SlackError {
  if response.status == 429 {
    // A 429 with no parseable `Retry-After` still has to produce a number, or
    // the caller has nothing to wait. 60 seconds is what slack-rs uses, and it
    // is the safe direction to be wrong in.
    let retry_after = match response.header("retry-after") {
      Some(header) => @api.parse_retry_after(header).unwrap_or(60)
      None => 60
    }
    raise @api.RateLimitedError(retry_after~)
  }
  if response.status < 200 || response.status >= 300 {
    raise @api.HttpError(
      status=response.status,
      headers=response.headers,
      body=response.body,
    )
  }
  let result = @api.ApiResponse::of_http(response)
  if !result.ok {
    raise @api.PlatformError(result~)
  }
  result
}

///|
/// Walk every page of a paginated method.
///
/// `on_page` is called with each page and returns `false` to stop early --
/// node-slack-sdk's `shouldStop`, inverted so that the common case is
/// `_ => true`. Returns the number of pages fetched.
///
/// A callback rather than an iterator because MoonBit's async iteration would
/// force this whole package to depend on a runtime; the callback costs one
/// closure and keeps @client buildable on wasm.
pub async fn Client::paginate(
  self : Self,
  api_method : String,
  params : @api.Params,
  on_page : (@api.ApiResponse) -> Bool,
  page_size? : Int = default_page_size,
  cursor? : String,
  max_pages? : Int,
) -> Int raise @api.SlackError {
  let paginator = Paginator::new(page_size~, cursor?)
  while paginator.next() is Some(page_params) {
    let response = self.call(api_method, merge_params(params, page_params))
    paginator.accept(response)
    if !on_page(response) {
      paginator.stop()
      break
    }
    if max_pages is Some(limit) && paginator.pages() >= limit {
      paginator.stop()
      break
    }
  }
  paginator.pages()
}

///|
/// Walk every page and concatenate the items under `key`.
///
/// `key` is the collection's name in the response -- `channels` for
/// `conversations.list`, `members` for `users.list`, `messages` for
/// `conversations.history`. Slack has no single name for it, so it cannot be
/// inferred.
pub async fn Client::paginate_collect(
  self : Self,
  api_method : String,
  params : @api.Params,
  key : String,
  page_size? : Int = default_page_size,
  max_pages? : Int,
) -> Array[Json] raise @api.SlackError {
  let out = []
  self.paginate(
    api_method,
    params,
    response => {
      for item in page_items(response, key) {
        out.push(item)
      }
      true
    },
    page_size~,
    max_pages?,
  )
  |> ignore
  out
}
