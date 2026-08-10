// Typed calls: conversations.*
//
// The family where pagination actually matters -- `list`, `history`, `replies`
// and `members` all page -- so each of them has a `_all` companion that walks
// every page and hands back the items.

///|
/// https://docs.slack.dev/reference/methods/conversations.list
///
/// `types` is comma-joined on the wire: `public_channel,private_channel,mpim,im`.
/// That is a per-field fact from Slack's docs, which is why it is `Csv` here and
/// not a JSON array.
pub async fn Client::conversations_list(
  self : Self,
  types? : Array[String],
  exclude_archived? : Bool,
  limit? : Int,
  cursor? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_csv("types", types)
  p.put_bool("exclude_archived", exclude_archived)
  p.put_int("limit", limit)
  p.put_str("cursor", cursor)
  self.call(@methods.conversations_list, p)
}

///|
/// Every conversation, across every page.
///
/// Tier 2 at 20 requests a minute, and a large workspace has tens of thousands
/// of channels -- so this is the call that will get you rate-limited if
/// anything does. Pass `max_pages` when you only need a sample.
pub async fn Client::conversations_list_all(
  self : Self,
  types? : Array[String],
  exclude_archived? : Bool,
  page_size? : Int = default_page_size,
  max_pages? : Int,
) -> Array[Json] raise @api.SlackError {
  let p = @api.Params::new()
  p.put_csv("types", types)
  p.put_bool("exclude_archived", exclude_archived)
  self.paginate_collect(
    @methods.conversations_list,
    p,
    "channels",
    page_size~,
    max_pages?,
  )
}

///|
/// https://docs.slack.dev/reference/methods/conversations.history
pub async fn Client::conversations_history(
  self : Self,
  channel~ : String,
  cursor? : String,
  limit? : Int,
  latest? : String,
  oldest? : String,
  inclusive? : Bool,
  include_all_metadata? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("cursor", cursor)
  p.put_int("limit", limit)
  p.put_str("latest", latest)
  p.put_str("oldest", oldest)
  p.put_bool("inclusive", inclusive)
  p.put_bool("include_all_metadata", include_all_metadata)
  self.call(@methods.conversations_history, p)
}

///|
/// Every message in a channel, oldest page last.
pub async fn Client::conversations_history_all(
  self : Self,
  channel~ : String,
  latest? : String,
  oldest? : String,
  page_size? : Int = default_page_size,
  max_pages? : Int,
) -> Array[Json] raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("latest", latest)
  p.put_str("oldest", oldest)
  self.paginate_collect(
    @methods.conversations_history,
    p,
    "messages",
    page_size~,
    max_pages?,
  )
}

///|
/// https://docs.slack.dev/reference/methods/conversations.replies
///
/// `ts` is the PARENT message's timestamp. The first item that comes back is
/// that parent, not the first reply.
pub async fn Client::conversations_replies(
  self : Self,
  channel~ : String,
  ts~ : String,
  cursor? : String,
  limit? : Int,
  latest? : String,
  oldest? : String,
  inclusive? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("ts", Some(ts))
  p.put_str("cursor", cursor)
  p.put_int("limit", limit)
  p.put_str("latest", latest)
  p.put_str("oldest", oldest)
  p.put_bool("inclusive", inclusive)
  self.call(@methods.conversations_replies, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.info
pub async fn Client::conversations_info(
  self : Self,
  channel~ : String,
  include_locale? : Bool,
  include_num_members? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_bool("include_locale", include_locale)
  p.put_bool("include_num_members", include_num_members)
  self.call(@methods.conversations_info, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.members
pub async fn Client::conversations_members(
  self : Self,
  channel~ : String,
  cursor? : String,
  limit? : Int,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("cursor", cursor)
  p.put_int("limit", limit)
  self.call(@methods.conversations_members, p)
}

///|
pub async fn Client::conversations_members_all(
  self : Self,
  channel~ : String,
  page_size? : Int = default_page_size,
  max_pages? : Int,
) -> Array[Json] raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  self.paginate_collect(
    @methods.conversations_members,
    p,
    "members",
    page_size~,
    max_pages?,
  )
}

///|
/// https://docs.slack.dev/reference/methods/conversations.create
pub async fn Client::conversations_create(
  self : Self,
  name~ : String,
  is_private? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("name", Some(name))
  p.put_bool("is_private", is_private)
  self.call(@methods.conversations_create, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.invite
///
/// `users` is comma-joined, up to 1,000 ids. java-slack-sdk joins this field by
/// hand for exactly this reason.
pub async fn Client::conversations_invite(
  self : Self,
  channel~ : String,
  users~ : Array[String],
  force? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_csv("users", Some(users))
  p.put_bool("force", force)
  self.call(@methods.conversations_invite, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.join
pub async fn Client::conversations_join(
  self : Self,
  channel~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  self.call(@methods.conversations_join, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.leave
pub async fn Client::conversations_leave(
  self : Self,
  channel~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  self.call(@methods.conversations_leave, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.kick
pub async fn Client::conversations_kick(
  self : Self,
  channel~ : String,
  user~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("user", Some(user))
  self.call(@methods.conversations_kick, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.open
///
/// With `users`, opens a DM or group DM; with `channel`, resumes an existing
/// one.
pub async fn Client::conversations_open(
  self : Self,
  channel? : String,
  users? : Array[String],
  return_im? : Bool,
  prevent_creation? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", channel)
  p.put_csv("users", users)
  p.put_bool("return_im", return_im)
  p.put_bool("prevent_creation", prevent_creation)
  self.call(@methods.conversations_open, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.close
pub async fn Client::conversations_close(
  self : Self,
  channel~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  self.call(@methods.conversations_close, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.archive
pub async fn Client::conversations_archive(
  self : Self,
  channel~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  self.call(@methods.conversations_archive, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.setTopic
pub async fn Client::conversations_set_topic(
  self : Self,
  channel~ : String,
  topic~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("topic", Some(topic))
  self.call(@methods.conversations_set_topic, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.setPurpose
pub async fn Client::conversations_set_purpose(
  self : Self,
  channel~ : String,
  purpose~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("purpose", Some(purpose))
  self.call(@methods.conversations_set_purpose, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.rename
pub async fn Client::conversations_rename(
  self : Self,
  channel~ : String,
  name~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("name", Some(name))
  self.call(@methods.conversations_rename, p)
}

///|
/// https://docs.slack.dev/reference/methods/conversations.mark
pub async fn Client::conversations_mark(
  self : Self,
  channel~ : String,
  ts~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("ts", Some(ts))
  self.call(@methods.conversations_mark, p)
}
