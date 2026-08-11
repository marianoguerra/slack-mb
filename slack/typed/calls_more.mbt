// The rest of the wrapped calls: the ones that answer a method-shaped result,
// and the ones that answer nothing at all.
//
// The second group looks pointless and is not. A method that answers only
// `{"ok": true}` still fails in every way the others do -- `missing_scope`, a
// 429, a dropped socket -- and wrapping it means a caller never has to leave
// `Api` mid-flow and never has to handle two error types in one function.
// `Unit` is the honest return: there is nothing else in the response, and
// `Api::client` is right there for the caller who wants to see it anyway.

///|
/// `auth.test`: who this token is. The first call most apps make.
pub async fn Api::auth_test(self : Api) -> Identity raise TypedError {
  let response = self.client.auth_test() catch { e => raise Slack(e) }
  identity_of(response, "auth.test")
}

///|
/// `auth.revoke`, answering whether the token was actually revoked.
///
/// `dry_run` reports what would happen without doing it, which is the whole
/// reason this answers a `Bool` rather than `Unit`.
pub async fn Api::auth_revoke(
  self : Api,
  dry_run? : Bool,
) -> Bool raise TypedError {
  let response = self.client.auth_revoke(dry_run?) catch { e => raise Slack(e) }
  guard bool_of(response, "revoked") is Some(revoked) else {
    raise ResponseShapeError(api_method="auth.revoke", key="revoked")
  }
  revoked
}

///|
/// `conversations.invite`, as the channel with its new members.
pub async fn Api::conversations_invite(
  self : Api,
  channel~ : String,
  users~ : Array[String],
  force? : Bool,
) -> @model.Channel raise TypedError {
  let response = self.client.conversations_invite(channel~, users~, force?) catch {
    e => raise Slack(e)
  }
  entity(response, "conversations.invite", "channel", @model.Channel::from_json)
}

///|
/// `conversations.join`, as the channel just joined.
pub async fn Api::conversations_join(
  self : Api,
  channel~ : String,
) -> @model.Channel raise TypedError {
  let response = self.client.conversations_join(channel~) catch {
    e => raise Slack(e)
  }
  entity(response, "conversations.join", "channel", @model.Channel::from_json)
}

///|
/// `conversations.rename`, as the channel under its new name.
pub async fn Api::conversations_rename(
  self : Api,
  channel~ : String,
  name~ : String,
) -> @model.Channel raise TypedError {
  let response = self.client.conversations_rename(channel~, name~) catch {
    e => raise Slack(e)
  }
  entity(response, "conversations.rename", "channel", @model.Channel::from_json)
}

///|
/// `conversations.archive`.
pub async fn Api::conversations_archive(
  self : Api,
  channel~ : String,
) -> Unit raise TypedError {
  let discarded = self.client.conversations_archive(channel~) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `conversations.leave`.
pub async fn Api::conversations_leave(
  self : Api,
  channel~ : String,
) -> Unit raise TypedError {
  let discarded = self.client.conversations_leave(channel~) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `conversations.kick`.
pub async fn Api::conversations_kick(
  self : Api,
  channel~ : String,
  user~ : String,
) -> Unit raise TypedError {
  let discarded = self.client.conversations_kick(channel~, user~) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `conversations.close`.
pub async fn Api::conversations_close(
  self : Api,
  channel~ : String,
) -> Unit raise TypedError {
  let discarded = self.client.conversations_close(channel~) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `conversations.mark`: move the read cursor.
pub async fn Api::conversations_mark(
  self : Api,
  channel~ : String,
  ts~ : String,
) -> Unit raise TypedError {
  let discarded = self.client.conversations_mark(channel~, ts~) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `chat.delete`, as what it deleted.
pub async fn Api::chat_delete(
  self : Api,
  channel~ : String,
  ts~ : String,
  as_user? : Bool,
) -> Posted raise TypedError {
  let response = self.client.chat_delete(channel~, ts~, as_user?) catch {
    e => raise Slack(e)
  }
  posted(response, "chat.delete")
}

///|
/// `chat.meMessage`, as where it landed.
pub async fn Api::chat_me_message(
  self : Api,
  channel~ : String,
  text~ : String,
) -> Posted raise TypedError {
  let response = self.client.chat_me_message(channel~, text~) catch {
    e => raise Slack(e)
  }
  posted(response, "chat.meMessage")
}

///|
/// `chat.postEphemeral`, as the `ts` of the message only that user can see.
///
/// A bare `ts` and not a `Posted`: an ephemeral message has no channel echoed
/// back and cannot be updated or deleted, so there is nothing else to carry.
pub async fn Api::chat_post_ephemeral(
  self : Api,
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
) -> String raise TypedError {
  let response = self.client.chat_post_ephemeral(
    channel~,
    user~,
    text?,
    blocks?,
    attachments?,
    thread_ts?,
    parse?,
    link_names?,
    username?,
    icon_emoji?,
    icon_url?,
    markdown_text?,
  ) catch {
    e => raise Slack(e)
  }
  entity(response, "chat.postEphemeral", "message_ts", id_of)
}

///|
/// `chat.getPermalink`, as the URL.
pub async fn Api::chat_get_permalink(
  self : Api,
  channel~ : String,
  message_ts~ : String,
) -> String raise TypedError {
  let response = self.client.chat_get_permalink(channel~, message_ts~) catch {
    e => raise Slack(e)
  }
  entity(response, "chat.getPermalink", "permalink", id_of)
}

///|
/// `chat.scheduleMessage`, as the handle to cancel it with.
pub async fn Api::chat_schedule_message(
  self : Api,
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
) -> Scheduled raise TypedError {
  let response = self.client.chat_schedule_message(
    channel~,
    post_at~,
    text?,
    blocks?,
    attachments?,
    thread_ts?,
    reply_broadcast?,
    unfurl_links?,
    unfurl_media?,
    metadata?,
    markdown_text?,
  ) catch {
    e => raise Slack(e)
  }
  let api_method = "chat.scheduleMessage"
  {
    scheduled_message_id: entity(
      response, api_method, "scheduled_message_id", id_of,
    ),
    channel: entity(response, api_method, "channel", id_of),
    post_at: int64_at(response, api_method, "post_at"),
    message: match response.get("message") {
      Some(json) => @model.Message::from_json(json)
      None => None
    },
  }
}

///|
/// One page of `chat.scheduledMessages.list`.
pub async fn Api::chat_scheduled_messages_list(
  self : Api,
  channel? : String,
  cursor? : String,
  limit? : Int,
  latest? : String,
  oldest? : String,
) -> Page[@model.ScheduledMessage] raise TypedError {
  let response = self.client.chat_scheduled_messages_list(
    channel?,
    cursor?,
    limit?,
    latest?,
    oldest?,
  ) catch {
    e => raise Slack(e)
  }
  page(
    response,
    "chat.scheduledMessages.list",
    "scheduled_messages",
    @model.ScheduledMessage::from_json,
  )
}

///|
/// `chat.deleteScheduledMessage`: cancel one before it is sent.
pub async fn Api::chat_delete_scheduled_message(
  self : Api,
  channel~ : String,
  scheduled_message_id~ : String,
  as_user? : Bool,
) -> Unit raise TypedError {
  let discarded = self.client.chat_delete_scheduled_message(
    channel~,
    scheduled_message_id~,
    as_user?,
  ) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `chat.unfurl`: attach a preview to a link someone posted.
pub async fn Api::chat_unfurl(
  self : Api,
  channel~ : String,
  ts~ : String,
  unfurls~ : Json,
  user_auth_required? : Bool,
  user_auth_message? : String,
  user_auth_url? : String,
  user_auth_blocks? : Array[@blocks.LayoutBlock],
) -> Unit raise TypedError {
  let discarded = self.client.chat_unfurl(
    channel~,
    ts~,
    unfurls~,
    user_auth_required?,
    user_auth_message?,
    user_auth_url?,
    user_auth_blocks?,
  ) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `bookmarks.list`, which is not paginated.
pub async fn Api::bookmarks_list(
  self : Api,
  channel_id~ : String,
) -> Array[@model.Bookmark] raise TypedError {
  let response = self.client.bookmarks_list(channel_id~) catch {
    e => raise Slack(e)
  }
  entities(response, "bookmarks.list", "bookmarks", @model.Bookmark::from_json)
}

///|
/// `bookmarks.add`, as the bookmark it created.
pub async fn Api::bookmarks_add(
  self : Api,
  channel_id~ : String,
  title~ : String,
  type_~ : String,
  link? : String,
  emoji? : String,
  entity_id? : String,
  parent_id? : String,
) -> @model.Bookmark raise TypedError {
  let response = self.client.bookmarks_add(
    channel_id~,
    title~,
    type_~,
    link?,
    emoji?,
    entity_id?,
    parent_id?,
  ) catch {
    e => raise Slack(e)
  }
  entity(response, "bookmarks.add", "bookmark", @model.Bookmark::from_json)
}

///|
/// `reactions.add`.
pub async fn Api::reactions_add(
  self : Api,
  channel~ : String,
  name~ : String,
  timestamp~ : String,
) -> Unit raise TypedError {
  let discarded = self.client.reactions_add(channel~, name~, timestamp~) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `reactions.remove`.
pub async fn Api::reactions_remove(
  self : Api,
  name~ : String,
  channel? : String,
  timestamp? : String,
  file? : String,
  file_comment? : String,
) -> Unit raise TypedError {
  let discarded = self.client.reactions_remove(
    name~,
    channel?,
    timestamp?,
    file?,
    file_comment?,
  ) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `pins.add`.
pub async fn Api::pins_add(
  self : Api,
  channel~ : String,
  timestamp? : String,
) -> Unit raise TypedError {
  let discarded = self.client.pins_add(channel~, timestamp?) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `pins.remove`.
pub async fn Api::pins_remove(
  self : Api,
  channel~ : String,
  timestamp? : String,
) -> Unit raise TypedError {
  let discarded = self.client.pins_remove(channel~, timestamp?) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `usergroups.users.update`, as the group with its new membership.
pub async fn Api::usergroups_users_update(
  self : Api,
  usergroup~ : String,
  users~ : Array[String],
  include_count? : Bool,
) -> @model.Usergroup raise TypedError {
  let response = self.client.usergroups_users_update(
    usergroup~,
    users~,
    include_count?,
  ) catch {
    e => raise Slack(e)
  }
  entity(
    response,
    "usergroups.users.update",
    "usergroup",
    @model.Usergroup::from_json,
  )
}

///|
/// `users.getPresence`.
pub async fn Api::users_get_presence(
  self : Api,
  user? : String,
) -> Presence raise TypedError {
  let response = self.client.users_get_presence(user?) catch {
    e => raise Slack(e)
  }
  {
    presence: entity(response, "users.getPresence", "presence", id_of),
    online: bool_of(response, "online"),
    auto_away: bool_of(response, "auto_away"),
    manual_away: bool_of(response, "manual_away"),
    connection_count: int_of(response, "connection_count"),
    last_activity: int64_of(response, "last_activity"),
  }
}

///|
/// `users.setPresence`.
pub async fn Api::users_set_presence(
  self : Api,
  presence~ : String,
) -> Unit raise TypedError {
  let discarded = self.client.users_set_presence(presence~) catch {
    e => raise Slack(e)
  }
  ignore(discarded)
}

///|
/// `files.delete`.
pub async fn Api::files_delete(
  self : Api,
  file~ : String,
) -> Unit raise TypedError {
  let discarded = self.client.files_delete(file~) catch { e => raise Slack(e) }
  ignore(discarded)
}

///|
/// `files.getUploadURLExternal`, as where to PUT the bytes.
pub async fn Api::files_get_upload_url_external(
  self : Api,
  filename~ : String,
  length~ : Int,
  alt_txt? : String,
  snippet_type? : String,
) -> Upload raise TypedError {
  let response = self.client.files_get_upload_url_external(
    filename~,
    length~,
    alt_txt?,
    snippet_type?,
  ) catch {
    e => raise Slack(e)
  }
  let api_method = "files.getUploadURLExternal"
  {
    upload_url: entity(response, api_method, "upload_url", id_of),
    file_id: entity(response, api_method, "file_id", id_of),
  }
}

///|
/// `files.completeUploadExternal`, as the files it finished.
pub async fn Api::files_complete_upload_external(
  self : Api,
  files~ : Json,
  channel_id? : String,
  initial_comment? : String,
  thread_ts? : String,
) -> Array[@model.File] raise TypedError {
  let response = self.client.files_complete_upload_external(
    files~,
    channel_id?,
    initial_comment?,
    thread_ts?,
  ) catch {
    e => raise Slack(e)
  }
  entities(
    response,
    "files.completeUploadExternal",
    "files",
    @model.File::from_json,
  )
}
