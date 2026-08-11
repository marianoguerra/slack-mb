// The wrapped calls.
//
// Each one is its `@client` counterpart, unchanged in name and arguments, plus
// the key its method puts the payload under. The key is the only thing this
// file knows that `@client` does not, and it is written out per method rather
// than derived, because there is no rule to derive it from -- see api.mbt.
//
// `catch { e => raise Slack(e) }` on every call is the wrapping being explicit.
// A `SlackError` reaching a caller of this package unwrapped would mean two
// error types in one signature, which is the cost this design exists to avoid.

///|
/// `users.info`, as a `User`.
pub async fn Api::users_info(
  self : Api,
  user~ : String,
  include_locale? : Bool,
) -> @model.User raise TypedError {
  let response = self.client.users_info(user~, include_locale?) catch {
    e => raise Slack(e)
  }
  entity(response, "users.info", "user", @model.User::from_json)
}

///|
/// `users.lookupByEmail`, as a `User`.
pub async fn Api::users_lookup_by_email(
  self : Api,
  email~ : String,
) -> @model.User raise TypedError {
  let response = self.client.users_lookup_by_email(email~) catch {
    e => raise Slack(e)
  }
  entity(response, "users.lookupByEmail", "user", @model.User::from_json)
}

///|
/// One page of `users.list`.
///
/// The members are objects here. On `conversations.members` the identically
/// named key holds ids.
pub async fn Api::users_list(
  self : Api,
  cursor? : String,
  limit? : Int,
  include_locale? : Bool,
) -> Page[@model.User] raise TypedError {
  let response = self.client.users_list(cursor?, limit?, include_locale?) catch {
    e => raise Slack(e)
  }
  page(response, "users.list", "members", @model.User::from_json)
}

///|
/// Every page of `users.list`.
pub async fn Api::users_list_all(
  self : Api,
  include_locale? : Bool,
  page_size? : Int,
  max_pages? : Int,
) -> Array[@model.User] raise TypedError {
  let items = self.client.users_list_all(
    include_locale?,
    page_size?,
    max_pages?,
  ) catch {
    e => raise Slack(e)
  }
  all(items, "users.list", "members", @model.User::from_json)
}

///|
/// `users.profile.get`, as a `Profile`.
pub async fn Api::users_profile_get(
  self : Api,
  user? : String,
  include_labels? : Bool,
) -> @model.Profile raise TypedError {
  let response = self.client.users_profile_get(user?, include_labels?) catch {
    e => raise Slack(e)
  }
  entity(response, "users.profile.get", "profile", @model.Profile::from_json)
}

///|
/// `users.profile.set`, answering the profile as stored.
pub async fn Api::users_profile_set(
  self : Api,
  user? : String,
  profile? : Json,
  name? : String,
  value? : String,
) -> @model.Profile raise TypedError {
  let response = self.client.users_profile_set(user?, profile?, name?, value?) catch {
    e => raise Slack(e)
  }
  entity(response, "users.profile.set", "profile", @model.Profile::from_json)
}

///|
/// One page of `users.conversations`.
pub async fn Api::users_conversations(
  self : Api,
  user? : String,
  types? : Array[String],
  exclude_archived? : Bool,
  cursor? : String,
  limit? : Int,
) -> Page[@model.Channel] raise TypedError {
  let response = self.client.users_conversations(
    user?,
    types?,
    exclude_archived?,
    cursor?,
    limit?,
  ) catch {
    e => raise Slack(e)
  }
  page(response, "users.conversations", "channels", @model.Channel::from_json)
}

///|
/// `conversations.info`, as a `Channel`.
pub async fn Api::conversations_info(
  self : Api,
  channel~ : String,
  include_locale? : Bool,
  include_num_members? : Bool,
) -> @model.Channel raise TypedError {
  let response = self.client.conversations_info(
    channel~,
    include_locale?,
    include_num_members?,
  ) catch {
    e => raise Slack(e)
  }
  entity(response, "conversations.info", "channel", @model.Channel::from_json)
}

///|
/// `conversations.create`, as the channel it created.
pub async fn Api::conversations_create(
  self : Api,
  name~ : String,
  is_private? : Bool,
) -> @model.Channel raise TypedError {
  let response = self.client.conversations_create(name~, is_private?) catch {
    e => raise Slack(e)
  }
  entity(response, "conversations.create", "channel", @model.Channel::from_json)
}

///|
/// `conversations.open`, as the DM or MPIM it opened or found.
pub async fn Api::conversations_open(
  self : Api,
  channel? : String,
  users? : Array[String],
  return_im? : Bool,
  prevent_creation? : Bool,
) -> @model.Channel raise TypedError {
  let response = self.client.conversations_open(
    channel?,
    users?,
    return_im?,
    prevent_creation?,
  ) catch {
    e => raise Slack(e)
  }
  entity(response, "conversations.open", "channel", @model.Channel::from_json)
}

///|
/// `conversations.setTopic`, as the channel with its new topic.
pub async fn Api::conversations_set_topic(
  self : Api,
  channel~ : String,
  topic~ : String,
) -> @model.Channel raise TypedError {
  let response = self.client.conversations_set_topic(channel~, topic~) catch {
    e => raise Slack(e)
  }
  entity(
    response,
    "conversations.setTopic",
    "channel",
    @model.Channel::from_json,
  )
}

///|
/// `conversations.setPurpose`, as the channel with its new purpose.
pub async fn Api::conversations_set_purpose(
  self : Api,
  channel~ : String,
  purpose~ : String,
) -> @model.Channel raise TypedError {
  let response = self.client.conversations_set_purpose(channel~, purpose~) catch {
    e => raise Slack(e)
  }
  entity(
    response,
    "conversations.setPurpose",
    "channel",
    @model.Channel::from_json,
  )
}

///|
/// One page of `conversations.list`.
pub async fn Api::conversations_list(
  self : Api,
  types? : Array[String],
  exclude_archived? : Bool,
  limit? : Int,
  cursor? : String,
) -> Page[@model.Channel] raise TypedError {
  let response = self.client.conversations_list(
    types?,
    exclude_archived?,
    limit?,
    cursor?,
  ) catch {
    e => raise Slack(e)
  }
  page(response, "conversations.list", "channels", @model.Channel::from_json)
}

///|
/// Every page of `conversations.list`.
///
/// `max_pages` is worth setting: this is a Tier 2 method, and a big workspace
/// will rate-limit a full walk.
pub async fn Api::conversations_list_all(
  self : Api,
  types? : Array[String],
  exclude_archived? : Bool,
  page_size? : Int,
  max_pages? : Int,
) -> Array[@model.Channel] raise TypedError {
  let items = self.client.conversations_list_all(
    types?,
    exclude_archived?,
    page_size?,
    max_pages?,
  ) catch {
    e => raise Slack(e)
  }
  all(items, "conversations.list", "channels", @model.Channel::from_json)
}

///|
/// One page of `conversations.members`, which is ids rather than users.
///
/// The key is `members`, the same key `users.list` uses for whole user
/// objects. Two methods, one key name, two types -- which is the argument
/// against a generic extractor, in one line.
pub async fn Api::conversations_members(
  self : Api,
  channel~ : String,
  cursor? : String,
  limit? : Int,
) -> Page[String] raise TypedError {
  let response = self.client.conversations_members(channel~, cursor?, limit?) catch {
    e => raise Slack(e)
  }
  page(response, "conversations.members", "members", id_of)
}

///|
/// Every page of `conversations.members`.
pub async fn Api::conversations_members_all(
  self : Api,
  channel~ : String,
  page_size? : Int,
  max_pages? : Int,
) -> Array[String] raise TypedError {
  let items = self.client.conversations_members_all(
    channel~,
    page_size?,
    max_pages?,
  ) catch {
    e => raise Slack(e)
  }
  all(items, "conversations.members", "members", id_of)
}

///|
/// One page of `conversations.history`.
pub async fn Api::conversations_history(
  self : Api,
  channel~ : String,
  cursor? : String,
  limit? : Int,
  latest? : String,
  oldest? : String,
  inclusive? : Bool,
  include_all_metadata? : Bool,
) -> Page[@model.Message] raise TypedError {
  let response = self.client.conversations_history(
    channel~,
    cursor?,
    limit?,
    latest?,
    oldest?,
    inclusive?,
    include_all_metadata?,
  ) catch {
    e => raise Slack(e)
  }
  page(response, "conversations.history", "messages", @model.Message::from_json)
}

///|
/// Every page of `conversations.history`.
pub async fn Api::conversations_history_all(
  self : Api,
  channel~ : String,
  latest? : String,
  oldest? : String,
  page_size? : Int,
  max_pages? : Int,
) -> Array[@model.Message] raise TypedError {
  let items = self.client.conversations_history_all(
    channel~,
    latest?,
    oldest?,
    page_size?,
    max_pages?,
  ) catch {
    e => raise Slack(e)
  }
  all(items, "conversations.history", "messages", @model.Message::from_json)
}

///|
/// One page of `conversations.replies`: a thread's parent and its replies.
///
/// The parent comes back first and carries `thread_ts == ts`, which
/// `Message::is_thread_reply` is the way to tell apart.
pub async fn Api::conversations_replies(
  self : Api,
  channel~ : String,
  ts~ : String,
  cursor? : String,
  limit? : Int,
  latest? : String,
  oldest? : String,
  inclusive? : Bool,
) -> Page[@model.Message] raise TypedError {
  let response = self.client.conversations_replies(
    channel~,
    ts~,
    cursor?,
    limit?,
    latest?,
    oldest?,
    inclusive?,
  ) catch {
    e => raise Slack(e)
  }
  page(response, "conversations.replies", "messages", @model.Message::from_json)
}

///|
/// `chat.postMessage`, as where it landed.
///
/// `Posted.channel` is an id and not a `Channel`, because that is what Slack
/// answers here -- even when the request named the channel by name.
pub async fn Api::chat_post_message(
  self : Api,
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
) -> Posted raise TypedError {
  let response = self.client.chat_post_message(
    channel~,
    text?,
    blocks?,
    attachments?,
    thread_ts?,
    reply_broadcast?,
    unfurl_links?,
    unfurl_media?,
    mrkdwn?,
    parse?,
    link_names?,
    username?,
    icon_emoji?,
    icon_url?,
    metadata?,
    markdown_text?,
  ) catch {
    e => raise Slack(e)
  }
  posted(response, "chat.postMessage")
}

///|
/// `chat.update`, as where the edited message is.
pub async fn Api::chat_update(
  self : Api,
  channel~ : String,
  ts~ : String,
  text? : String,
  blocks? : Array[@blocks.LayoutBlock],
  attachments? : Json,
  link_names? : Bool,
  parse? : String,
  metadata? : Json,
  markdown_text? : String,
) -> Posted raise TypedError {
  let response = self.client.chat_update(
    channel~,
    ts~,
    text?,
    blocks?,
    attachments?,
    link_names?,
    parse?,
    metadata?,
    markdown_text?,
  ) catch {
    e => raise Slack(e)
  }
  posted(response, "chat.update")
}

///|
/// The `channel`/`ts`/`message` triple both chat methods answer.
///
/// `message` is optional because it is the one of the three that a caller can
/// do without, and because `chat.update`'s recorded sample carries a `message`
/// with no `ts` -- there is no reason to fail a successful edit over it.
fn posted(
  response : @api.ApiResponse,
  api_method : String,
) -> Posted raise TypedError {
  let channel = entity(response, api_method, "channel", id_of)
  let ts = entity(response, api_method, "ts", id_of)
  let message = match response.get("message") {
    Some(json) => @model.Message::from_json(json)
    None => None
  }
  { channel, ts, message }
}

///|
/// `team.info`, as a `Team`.
pub async fn Api::team_info(
  self : Api,
  team? : String,
  domain? : String,
) -> @model.Team raise TypedError {
  let response = self.client.team_info(team?, domain?) catch {
    e => raise Slack(e)
  }
  entity(response, "team.info", "team", @model.Team::from_json)
}

///|
/// `usergroups.list`, which is not paginated.
pub async fn Api::usergroups_list(
  self : Api,
  include_disabled? : Bool,
  include_count? : Bool,
  include_users? : Bool,
) -> Array[@model.Usergroup] raise TypedError {
  let response = self.client.usergroups_list(
    include_disabled?,
    include_count?,
    include_users?,
  ) catch {
    e => raise Slack(e)
  }
  entities(
    response,
    "usergroups.list",
    "usergroups",
    @model.Usergroup::from_json,
  )
}

///|
/// `usergroups.create`, as the group it created.
pub async fn Api::usergroups_create(
  self : Api,
  name~ : String,
  handle? : String,
  description? : String,
  channels? : Array[String],
  include_count? : Bool,
) -> @model.Usergroup raise TypedError {
  let response = self.client.usergroups_create(
    name~,
    handle?,
    description?,
    channels?,
    include_count?,
  ) catch {
    e => raise Slack(e)
  }
  entity(
    response,
    "usergroups.create",
    "usergroup",
    @model.Usergroup::from_json,
  )
}

///|
/// `usergroups.users.list`, which is ids.
pub async fn Api::usergroups_users_list(
  self : Api,
  usergroup~ : String,
  include_disabled? : Bool,
) -> Array[String] raise TypedError {
  let response = self.client.usergroups_users_list(
    usergroup~,
    include_disabled?,
  ) catch {
    e => raise Slack(e)
  }
  entities(response, "usergroups.users.list", "users", id_of)
}

///|
/// `views.open`, as the view Slack stored.
pub async fn Api::views_open(
  self : Api,
  trigger_id~ : String,
  view~ : Json,
) -> @model.View raise TypedError {
  let response = self.client.views_open(trigger_id~, view~) catch {
    e => raise Slack(e)
  }
  entity(response, "views.open", "view", @model.View::from_json)
}

///|
/// `views.publish`, as the App Home view Slack stored.
pub async fn Api::views_publish(
  self : Api,
  user_id~ : String,
  view~ : Json,
  hash? : String,
) -> @model.View raise TypedError {
  let response = self.client.views_publish(user_id~, view~, hash?) catch {
    e => raise Slack(e)
  }
  entity(response, "views.publish", "view", @model.View::from_json)
}

///|
/// `views.push`, as the view it pushed onto the stack.
pub async fn Api::views_push(
  self : Api,
  trigger_id~ : String,
  view~ : Json,
) -> @model.View raise TypedError {
  let response = self.client.views_push(trigger_id~, view~) catch {
    e => raise Slack(e)
  }
  entity(response, "views.push", "view", @model.View::from_json)
}

///|
/// `views.update`, as the view after the update.
pub async fn Api::views_update(
  self : Api,
  view~ : Json,
  view_id? : String,
  external_id? : String,
  hash? : String,
) -> @model.View raise TypedError {
  let response = self.client.views_update(view~, view_id?, external_id?, hash?) catch {
    e => raise Slack(e)
  }
  entity(response, "views.update", "view", @model.View::from_json)
}

///|
/// `files.info`, as a `File`.
pub async fn Api::files_info(
  self : Api,
  file~ : String,
  cursor? : String,
  limit? : Int,
) -> @model.File raise TypedError {
  let response = self.client.files_info(file~, cursor?, limit?) catch {
    e => raise Slack(e)
  }
  entity(response, "files.info", "file", @model.File::from_json)
}

///|
/// `files.list`, which pages by number rather than by cursor.
///
/// Hence an array and not a `Page`: the `paging` object it answers with is not
/// the cursor scheme the rest of this file uses, and pretending otherwise would
/// hand back a `Page` whose `cursor` was always `None`.
pub async fn Api::files_list(
  self : Api,
  channel? : String,
  user? : String,
  types? : Array[String],
  ts_from? : String,
  ts_to? : String,
  count? : Int,
  page? : Int,
) -> Array[@model.File] raise TypedError {
  let response = self.client.files_list(
    channel?,
    user?,
    types?,
    ts_from?,
    ts_to?,
    count?,
    page?,
  ) catch {
    e => raise Slack(e)
  }
  entities(response, "files.list", "files", @model.File::from_json)
}
