// The wrapper, the two result shapes, and the extraction step every method
// shares.
//
// Extraction is per method and never generic, and the corpus is why. `channel`
// is an object on `conversations.info` and a bare STRING on
// `chat.postMessage`; `user` is an object on `users.info` and a string on
// `auth.test`; `members` is a list of users on `users.list` and a list of ids
// on `conversations.members`. Only the method knows which, so there is no
// `ApiResponse::user()` here and there should not be one -- every method below
// names its own key.

///|
/// A `Client`, and the extraction step that turns its answers into @model
/// values.
///
/// Holds the client rather than replacing it: `Api::client` is always there,
/// and mixing the two levels in one function is the expected way to use this.
pub struct Api {
  client : @client.Client
}

///|
/// Wrap an existing client.
///
/// The usual entry point, because a `Client` is where the transport, the token
/// and the base URL are already configured.
pub fn Api::of(client : @client.Client) -> Api {
  { client, }
}

///|
/// Build the client and wrap it in one step, with `Client::new`'s arguments.
pub fn Api::new(
  transport : &@api.Transport,
  token : String,
  base_url? : String,
  bool_style? : @api.BoolStyle,
  extra_headers? : Map[String, String],
  team_id? : String,
) -> Api {
  {
    client: @client.Client::new(
      transport,
      token,
      base_url?,
      bool_style?,
      extra_headers?,
      team_id?,
    ),
  }
}

///|
/// The low-level client, for everything this package does not wrap.
///
/// Not an escape hatch so much as the other half of the API: `Client::call`
/// reaches every one of Slack's 326 methods, and `ApiResponse.raw` reaches
/// every field of every response.
pub fn Api::client(self : Api) -> @client.Client {
  self.client
}

///|
/// One page of a cursor-paginated call.
///
/// Carries the whole response as well as the items, because the interesting
/// fields of a page are not all items -- `has_more` on
/// `conversations.history`, the warnings on a partial `users.list`.
pub(all) struct Page[T] {
  items : Array[T]
  /// The cursor for the next page, or `None` on the last one.
  ///
  /// Slack signals the end with an EMPTY `next_cursor` rather than by omitting
  /// it, which is the single easiest way to write an infinite loop over the
  /// last page. `@client.Paginator` already knows that; this normalises the
  /// empty string to `None` so a hand-rolled loop cannot get it wrong either.
  cursor : String?
  response : @api.ApiResponse
}

///|
/// Whether another page exists.
pub fn[T] Page::has_more(self : Page[T]) -> Bool {
  self.cursor is Some(_)
}

///|
/// What `chat.postMessage` and `chat.update` answer.
///
/// Not a `Channel`: the `channel` here is an id, which is the clearest case in
/// the whole API for why extraction cannot be generic.
pub(all) struct Posted {
  channel : String
  ts : String
  /// The message as stored, which is not always the message as sent -- Slack
  /// resolves links and mentions on the way in.
  message : @model.Message?
} derive(Eq, @debug.Debug)

///|
/// Pull a modelled payload out of a response, or say which method and key
/// disagreed with what this version models.
fn[T] entity(
  response : @api.ApiResponse,
  api_method : String,
  key : String,
  parse : (Json) -> T?,
) -> T raise TypedError {
  guard response.get(key) is Some(value) else {
    raise ResponseShapeError(api_method~, key~)
  }
  guard parse(value) is Some(parsed) else {
    raise ResponseShapeError(api_method~, key~)
  }
  parsed
}

///|
/// The same, for a key holding a list.
///
/// An ABSENT key is an error and an empty array is not: a filtered
/// `conversations.list` whose last page matched nothing is a normal answer, a
/// `conversations.list` with no `channels` at all is not one this version
/// understands. One bad element fails the whole call rather than being skipped
/// -- silently returning four of five channels is the kind of bug that is
/// found in production, months later.
fn[T] entities(
  response : @api.ApiResponse,
  api_method : String,
  key : String,
  parse : (Json) -> T?,
) -> Array[T] raise TypedError {
  guard response.get(key) is Some(Array(items)) else {
    raise ResponseShapeError(api_method~, key~)
  }
  let out = []
  for item in items {
    guard parse(item) is Some(parsed) else {
      raise ResponseShapeError(api_method~, key~)
    }
    out.push(parsed)
  }
  out
}

///|
/// The same again, as a page.
fn[T] page(
  response : @api.ApiResponse,
  api_method : String,
  key : String,
  parse : (Json) -> T?,
) -> Page[T] raise TypedError {
  let items = entities(response, api_method, key, parse)
  let cursor = match response.response_metadata.next_cursor {
    Some("") | None => None
    Some(c) => Some(c)
  }
  { items, cursor, response }
}

///|
/// Map a parser over what a `_all` helper collected.
///
/// `Client`'s `_all` methods answer `Array[Json]` because they walk pages and
/// concatenate the items; the key was already applied there, so all that is
/// left is the parse.
fn[T] all(
  items : Array[Json],
  api_method : String,
  key : String,
  parse : (Json) -> T?,
) -> Array[T] raise TypedError {
  let out = []
  for item in items {
    guard parse(item) is Some(parsed) else {
      raise ResponseShapeError(api_method~, key~)
    }
    out.push(parsed)
  }
  out
}

///|
/// An id, for the keys that hold one rather than an object.
fn id_of(json : Json) -> String? {
  match json {
    String(s) => Some(s)
    _ => None
  }
}
