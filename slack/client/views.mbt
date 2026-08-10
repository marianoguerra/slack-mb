// Typed calls: views.*, reactions.*, files.*, pins.*, bookmarks.*
//
// The interaction families. `views.*` is what a modal is; `reactions.*` and
// `pins.*` are the small ones every bot ends up needing; `files.*` is here for
// the metadata calls only -- uploading is a three-request dance with a binary
// body and is an explicit non-goal for now (see the README).

///|
/// https://docs.slack.dev/reference/methods/views.open
///
/// `trigger_id` expires three seconds after the interaction that produced it.
/// A modal that "sometimes fails to open" is almost always this.
pub async fn Client::views_open(
  self : Self,
  trigger_id~ : String,
  view~ : Json,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("trigger_id", Some(trigger_id))
  p.put_json("view", Some(view))
  self.call(@methods.views_open, p)
}

///|
/// https://docs.slack.dev/reference/methods/views.push
pub async fn Client::views_push(
  self : Self,
  trigger_id~ : String,
  view~ : Json,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("trigger_id", Some(trigger_id))
  p.put_json("view", Some(view))
  self.call(@methods.views_push, p)
}

///|
/// https://docs.slack.dev/reference/methods/views.update
///
/// Identify the view by `view_id` or by `external_id`, not both. `hash` guards
/// against a lost update when two handlers race.
pub async fn Client::views_update(
  self : Self,
  view~ : Json,
  view_id? : String,
  external_id? : String,
  hash? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_json("view", Some(view))
  p.put_str("view_id", view_id)
  p.put_str("external_id", external_id)
  p.put_str("hash", hash)
  self.call(@methods.views_update, p)
}

///|
/// https://docs.slack.dev/reference/methods/views.publish
///
/// The App Home tab. `hash` is the same lost-update guard as on `views.update`.
pub async fn Client::views_publish(
  self : Self,
  user_id~ : String,
  view~ : Json,
  hash? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("user_id", Some(user_id))
  p.put_json("view", Some(view))
  p.put_str("hash", hash)
  self.call(@methods.views_publish, p)
}

///|
/// Build a `view` payload from typed blocks.
///
/// Views are not blocks and not `LayoutBlock`s, but the only part of one a
/// caller usually cares about is its block list -- so this assembles the rest.
pub fn view(
  type_ : String,
  blocks : Array[@blocks.LayoutBlock],
  title? : String,
  submit? : String,
  close? : String,
  callback_id? : String,
  private_metadata? : String,
  external_id? : String,
  clear_on_close? : Bool,
  notify_on_close? : Bool,
) -> Json {
  let o : Map[String, Json] = Map([])
  o["type"] = Json::string(type_)
  o["blocks"] = @blocks.blocks_to_json(blocks)
  if title is Some(t) {
    o["title"] = @blocks.TextObject::plain(t).to_json()
  }
  if submit is Some(t) {
    o["submit"] = @blocks.TextObject::plain(t).to_json()
  }
  if close is Some(t) {
    o["close"] = @blocks.TextObject::plain(t).to_json()
  }
  if callback_id is Some(v) {
    o["callback_id"] = Json::string(v)
  }
  if private_metadata is Some(v) {
    o["private_metadata"] = Json::string(v)
  }
  if external_id is Some(v) {
    o["external_id"] = Json::string(v)
  }
  if clear_on_close is Some(v) {
    o["clear_on_close"] = Json::boolean(v)
  }
  if notify_on_close is Some(v) {
    o["notify_on_close"] = Json::boolean(v)
  }
  Json::object(o)
}

///|
/// A modal view. `title` and `submit` are what Slack requires of one.
pub fn modal(
  title : String,
  blocks : Array[@blocks.LayoutBlock],
  submit? : String,
  close? : String,
  callback_id? : String,
  private_metadata? : String,
) -> Json {
  view(
    "modal",
    blocks,
    title~,
    submit?,
    close?,
    callback_id?,
    private_metadata?,
  )
}

///|
/// An App Home tab view.
pub fn home_view(
  blocks : Array[@blocks.LayoutBlock],
  callback_id? : String,
  private_metadata? : String,
) -> Json {
  view("home", blocks, callback_id?, private_metadata?)
}

///|
/// https://docs.slack.dev/reference/methods/reactions.add
///
/// `name` is the shortcode WITHOUT colons: `thumbsup`, not `:thumbsup:`.
pub async fn Client::reactions_add(
  self : Self,
  channel~ : String,
  timestamp~ : String,
  name~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("timestamp", Some(timestamp))
  p.put_str("name", Some(name))
  self.call(@methods.reactions_add, p)
}

///|
/// https://docs.slack.dev/reference/methods/reactions.remove
pub async fn Client::reactions_remove(
  self : Self,
  name~ : String,
  channel? : String,
  timestamp? : String,
  file? : String,
  file_comment? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("name", Some(name))
  p.put_str("channel", channel)
  p.put_str("timestamp", timestamp)
  p.put_str("file", file)
  p.put_str("file_comment", file_comment)
  self.call(@methods.reactions_remove, p)
}

///|
/// https://docs.slack.dev/reference/methods/reactions.get
pub async fn Client::reactions_get(
  self : Self,
  channel? : String,
  timestamp? : String,
  file? : String,
  file_comment? : String,
  full? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", channel)
  p.put_str("timestamp", timestamp)
  p.put_str("file", file)
  p.put_str("file_comment", file_comment)
  p.put_bool("full", full)
  self.call(@methods.reactions_get, p)
}

///|
/// https://docs.slack.dev/reference/methods/reactions.list
pub async fn Client::reactions_list(
  self : Self,
  user? : String,
  cursor? : String,
  limit? : Int,
  full? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("user", user)
  p.put_str("cursor", cursor)
  p.put_int("limit", limit)
  p.put_bool("full", full)
  self.call(@methods.reactions_list, p)
}

///|
/// https://docs.slack.dev/reference/methods/files.info
pub async fn Client::files_info(
  self : Self,
  file~ : String,
  cursor? : String,
  limit? : Int,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("file", Some(file))
  p.put_str("cursor", cursor)
  p.put_int("limit", limit)
  self.call(@methods.files_info, p)
}

///|
/// https://docs.slack.dev/reference/methods/files.list
pub async fn Client::files_list(
  self : Self,
  channel? : String,
  user? : String,
  types? : Array[String],
  ts_from? : String,
  ts_to? : String,
  count? : Int,
  page? : Int,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", channel)
  p.put_str("user", user)
  p.put_csv("types", types)
  p.put_str("ts_from", ts_from)
  p.put_str("ts_to", ts_to)
  p.put_int("count", count)
  p.put_int("page", page)
  self.call(@methods.files_list, p)
}

///|
/// https://docs.slack.dev/reference/methods/files.delete
pub async fn Client::files_delete(
  self : Self,
  file~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("file", Some(file))
  self.call(@methods.files_delete, p)
}

///|
/// https://docs.slack.dev/reference/methods/files.getUploadURLExternal
///
/// Step one of the upload dance: ask for a URL, PUT the bytes to it yourself,
/// then call `files.completeUploadExternal`. The PUT is not a Web API call and
/// this library does not do it -- see the README.
pub async fn Client::files_get_upload_url_external(
  self : Self,
  filename~ : String,
  length~ : Int,
  alt_txt? : String,
  snippet_type? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("filename", Some(filename))
  p.put_int("length", Some(length))
  p.put_str("alt_txt", alt_txt)
  p.put_str("snippet_type", snippet_type)
  self.call(@methods.files_get_upload_url_external, p)
}

///|
/// https://docs.slack.dev/reference/methods/files.completeUploadExternal
pub async fn Client::files_complete_upload_external(
  self : Self,
  files~ : Json,
  channel_id? : String,
  initial_comment? : String,
  thread_ts? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_json("files", Some(files))
  p.put_str("channel_id", channel_id)
  p.put_str("initial_comment", initial_comment)
  p.put_str("thread_ts", thread_ts)
  self.call(@methods.files_complete_upload_external, p)
}

///|
/// https://docs.slack.dev/reference/methods/pins.add
pub async fn Client::pins_add(
  self : Self,
  channel~ : String,
  timestamp? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("timestamp", timestamp)
  self.call(@methods.pins_add, p)
}

///|
/// https://docs.slack.dev/reference/methods/pins.remove
pub async fn Client::pins_remove(
  self : Self,
  channel~ : String,
  timestamp? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("timestamp", timestamp)
  self.call(@methods.pins_remove, p)
}

///|
/// https://docs.slack.dev/reference/methods/pins.list
pub async fn Client::pins_list(
  self : Self,
  channel~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  self.call(@methods.pins_list, p)
}

///|
/// https://docs.slack.dev/reference/methods/bookmarks.list
pub async fn Client::bookmarks_list(
  self : Self,
  channel_id~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel_id", Some(channel_id))
  self.call(@methods.bookmarks_list, p)
}

///|
/// https://docs.slack.dev/reference/methods/bookmarks.add
pub async fn Client::bookmarks_add(
  self : Self,
  channel_id~ : String,
  title~ : String,
  type_~ : String,
  link? : String,
  emoji? : String,
  entity_id? : String,
  parent_id? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel_id", Some(channel_id))
  p.put_str("title", Some(title))
  p.put_str("type", Some(type_))
  p.put_str("link", link)
  p.put_str("emoji", emoji)
  p.put_str("entity_id", entity_id)
  p.put_str("parent_id", parent_id)
  self.call(@methods.bookmarks_add, p)
}
