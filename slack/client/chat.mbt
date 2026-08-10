// Typed calls: chat.*
//
// Every one of these is `call` with the arguments spelled out. What the typing
// buys is not safety on the wire -- Slack validates anyway -- but the two
// things a caller cannot get from `call`: the argument names are in the
// signature rather than in a browser tab, and `blocks` takes a
// `LayoutBlock` list rather than a hand-built `Json`.
//
// Named arguments are used everywhere, and only the genuinely required ones are
// positional, so a call site reads as prose and adding an argument later is not
// a breaking change.

///|
/// https://docs.slack.dev/reference/methods/chat.postMessage
///
/// `text` is optional in the schema but should almost always be set even when
/// `blocks` is: it is what shows in notifications, in the sidebar preview and
/// in clients that cannot render blocks. node-slack-sdk warns when it is
/// missing; this library documents it here instead of logging at you.
pub async fn Client::chat_post_message(
  self : Self,
  channel~ : String,
  text? : String,
  blocks? : Array[@blocks.LayoutBlock],
  attachments? : Json,
  thread_ts? : String,
  reply_broadcast? : Bool,
  unfurl_links? : Bool,
  unfurl_media? : Bool,
  mrkdwn? : Bool,
  parse? : String,
  link_names? : Bool,
  username? : String,
  icon_emoji? : String,
  icon_url? : String,
  metadata? : Json,
  markdown_text? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("text", text)
  p.put_json("blocks", blocks.map(b => @blocks.blocks_to_json(b)))
  p.put_json("attachments", attachments)
  p.put_str("thread_ts", thread_ts)
  p.put_bool("reply_broadcast", reply_broadcast)
  p.put_bool("unfurl_links", unfurl_links)
  p.put_bool("unfurl_media", unfurl_media)
  p.put_bool("mrkdwn", mrkdwn)
  p.put_str("parse", parse)
  p.put_bool("link_names", link_names)
  p.put_str("username", username)
  p.put_str("icon_emoji", icon_emoji)
  p.put_str("icon_url", icon_url)
  p.put_json("metadata", metadata)
  p.put_str("markdown_text", markdown_text)
  self.call(@methods.chat_post_message, p)
}

///|
/// https://docs.slack.dev/reference/methods/chat.update
///
/// Note what an omitted `blocks` means here: the existing blocks stay. To
/// REMOVE them, pass an empty list -- which serialises to `[]` rather than
/// vanishing, exactly as java-slack-sdk pins.
pub async fn Client::chat_update(
  self : Self,
  channel~ : String,
  ts~ : String,
  text? : String,
  blocks? : Array[@blocks.LayoutBlock],
  attachments? : Json,
  link_names? : Bool,
  parse? : String,
  metadata? : Json,
  markdown_text? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("ts", Some(ts))
  p.put_str("text", text)
  p.put_json("blocks", blocks.map(b => @blocks.blocks_to_json(b)))
  p.put_json("attachments", attachments)
  p.put_bool("link_names", link_names)
  p.put_str("parse", parse)
  p.put_json("metadata", metadata)
  p.put_str("markdown_text", markdown_text)
  self.call(@methods.chat_update, p)
}

///|
/// https://docs.slack.dev/reference/methods/chat.delete
pub async fn Client::chat_delete(
  self : Self,
  channel~ : String,
  ts~ : String,
  as_user? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("ts", Some(ts))
  p.put_bool("as_user", as_user)
  self.call(@methods.chat_delete, p)
}

///|
/// https://docs.slack.dev/reference/methods/chat.postEphemeral
///
/// Visible to one user, and never stored. There is no `ts` to update or delete
/// afterwards.
pub async fn Client::chat_post_ephemeral(
  self : Self,
  channel~ : String,
  user~ : String,
  text? : String,
  blocks? : Array[@blocks.LayoutBlock],
  attachments? : Json,
  thread_ts? : String,
  parse? : String,
  link_names? : Bool,
  username? : String,
  icon_emoji? : String,
  icon_url? : String,
  markdown_text? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("user", Some(user))
  p.put_str("text", text)
  p.put_json("blocks", blocks.map(b => @blocks.blocks_to_json(b)))
  p.put_json("attachments", attachments)
  p.put_str("thread_ts", thread_ts)
  p.put_str("parse", parse)
  p.put_bool("link_names", link_names)
  p.put_str("username", username)
  p.put_str("icon_emoji", icon_emoji)
  p.put_str("icon_url", icon_url)
  p.put_str("markdown_text", markdown_text)
  self.call(@methods.chat_post_ephemeral, p)
}

///|
/// https://docs.slack.dev/reference/methods/chat.scheduleMessage
pub async fn Client::chat_schedule_message(
  self : Self,
  channel~ : String,
  post_at~ : Int64,
  text? : String,
  blocks? : Array[@blocks.LayoutBlock],
  attachments? : Json,
  thread_ts? : String,
  reply_broadcast? : Bool,
  unfurl_links? : Bool,
  unfurl_media? : Bool,
  metadata? : Json,
  markdown_text? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_i64("post_at", Some(post_at))
  p.put_str("text", text)
  p.put_json("blocks", blocks.map(b => @blocks.blocks_to_json(b)))
  p.put_json("attachments", attachments)
  p.put_str("thread_ts", thread_ts)
  p.put_bool("reply_broadcast", reply_broadcast)
  p.put_bool("unfurl_links", unfurl_links)
  p.put_bool("unfurl_media", unfurl_media)
  p.put_json("metadata", metadata)
  p.put_str("markdown_text", markdown_text)
  self.call(@methods.chat_schedule_message, p)
}

///|
/// https://docs.slack.dev/reference/methods/chat.deleteScheduledMessage
pub async fn Client::chat_delete_scheduled_message(
  self : Self,
  channel~ : String,
  scheduled_message_id~ : String,
  as_user? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("scheduled_message_id", Some(scheduled_message_id))
  p.put_bool("as_user", as_user)
  self.call(@methods.chat_delete_scheduled_message, p)
}

///|
/// https://docs.slack.dev/reference/methods/chat.getPermalink
pub async fn Client::chat_get_permalink(
  self : Self,
  channel~ : String,
  message_ts~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("message_ts", Some(message_ts))
  self.call(@methods.chat_get_permalink, p)
}

///|
/// https://docs.slack.dev/reference/methods/chat.meMessage
pub async fn Client::chat_me_message(
  self : Self,
  channel~ : String,
  text~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("text", Some(text))
  self.call(@methods.chat_me_message, p)
}

///|
/// https://docs.slack.dev/reference/methods/chat.unfurl
///
/// `user_auth_blocks` is spelled that way on the wire; java-slack-sdk's
/// `RequestFormBuilderTest` has a case for it precisely because the field name
/// does not match the Java one.
pub async fn Client::chat_unfurl(
  self : Self,
  channel~ : String,
  ts~ : String,
  unfurls~ : Json,
  user_auth_required? : Bool,
  user_auth_message? : String,
  user_auth_url? : String,
  user_auth_blocks? : Array[@blocks.LayoutBlock],
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", Some(channel))
  p.put_str("ts", Some(ts))
  p.put_json("unfurls", Some(unfurls))
  p.put_bool("user_auth_required", user_auth_required)
  p.put_str("user_auth_message", user_auth_message)
  p.put_str("user_auth_url", user_auth_url)
  p.put_json(
    "user_auth_blocks",
    user_auth_blocks.map(b => @blocks.blocks_to_json(b)),
  )
  self.call(@methods.chat_unfurl, p)
}

///|
/// https://docs.slack.dev/reference/methods/chat.scheduledMessages.list
pub async fn Client::chat_scheduled_messages_list(
  self : Self,
  channel? : String,
  cursor? : String,
  limit? : Int,
  latest? : String,
  oldest? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("channel", channel)
  p.put_str("cursor", cursor)
  p.put_int("limit", limit)
  p.put_str("latest", latest)
  p.put_str("oldest", oldest)
  self.call(@methods.chat_scheduled_messages_list, p)
}
