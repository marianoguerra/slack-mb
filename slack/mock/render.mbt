// Turning the store into the JSON Slack would have sent.
//
// The rule this file follows, and the reason ext/test/mockshape exists to
// enforce it: emit only fields the vendored corpus has for that method, and
// emit them at the type the corpus has. A field this mock invents is worse than
// a field it omits -- an omission makes a caller notice, an invention makes
// them build on something Slack will never send.
//
// It is also why the renderers take a flag or two rather than being one
// function per record type. `users.info`'s profile and `users.profile.get`'s
// profile are not the same object in Slack's samples (only the second carries
// `fields`), and a shared renderer that emitted the union would fail the first.

///|
/// An integer-valued JSON number, with its representation pinned.
///
/// `Json::number` takes a `Double`, and a bare `12345.0` is free to stringify
/// as `1.2345e4`. Every timestamp, count and offset Slack sends is an integer,
/// so every one of them goes through here -- a `created` field that arrived as
/// `1.7e9` would parse, compare equal as a number, and look absurd in every log
/// and every recorded golden.
fn jint(v : Int) -> Json {
  Json::number(v.to_double(), repr=v.to_string())
}

///|
fn ji64(v : Int64) -> Json {
  Json::number(v.to_double(), repr=v.to_string())
}

///|
fn jstr(v : String) -> Json {
  Json::string(v)
}

///|
fn jbool(v : Bool) -> Json {
  Json::boolean(v)
}

///|
/// A deterministic avatar URL.
///
/// Slack sends a real Gravatar or file-upload URL; the corpus scrubs every one
/// of them to `https://www.example.com/`, and the scrubber in ext/scenario does
/// the same to these, so only the type survives the comparison. A recognisable
/// host is worth more than a plausible one when it turns up in a failing diff.
fn avatar_url(user_id : String, size : Int) -> String {
  "https://mock.slack.local/avatar/\{user_id}_\{size}.png"
}

///|
pub fn Team::to_json(self : Self) -> Json {
  let o : Map[String, Json] = Map([])
  o["id"] = jstr(self.id)
  o["name"] = jstr(self.name)
  o["domain"] = jstr(self.domain)
  o["email_domain"] = jstr(self.email_domain)
  o["icon"] = Json::object({
    "image_34": jstr("https://mock.slack.local/team_34.png"),
    "image_default": jbool(true),
  })
  o["url"] = jstr("https://\{self.domain}.slack.com/")
  o["is_verified"] = jbool(false)
  if self.enterprise_id is Some(id) {
    o["enterprise_id"] = jstr(id)
  }
  Json::object(o)
}

///|
/// A user's profile.
///
/// `include_fields` adds the `fields` map, which `users.profile.get` carries
/// and `users.info` does not -- see the note at the top of this file.
fn User::profile_json(
  self : Self,
  team_id : String,
  include_fields? : Bool = false,
) -> Json {
  let o : Map[String, Json] = Map([])
  o["title"] = jstr(self.title)
  o["phone"] = jstr(self.phone)
  o["skype"] = jstr("")
  o["real_name"] = jstr(self.real_name)
  o["real_name_normalized"] = jstr(self.real_name)
  o["display_name"] = jstr(self.display_name)
  o["display_name_normalized"] = jstr(self.display_name)
  if include_fields {
    o["fields"] = Json::object(Map([]))
  }
  o["status_text"] = jstr(self.status_text)
  o["status_emoji"] = jstr(self.status_emoji)
  o["status_expiration"] = jint(0)
  o["avatar_hash"] = jstr("g\{self.id.to_lower()}")
  o["always_active"] = jbool(false)
  o["first_name"] = jstr(first_word(self.real_name))
  o["last_name"] = jstr(rest_words(self.real_name))
  o["image_24"] = jstr(avatar_url(self.id, 24))
  o["image_32"] = jstr(avatar_url(self.id, 32))
  o["image_48"] = jstr(avatar_url(self.id, 48))
  o["image_72"] = jstr(avatar_url(self.id, 72))
  o["image_192"] = jstr(avatar_url(self.id, 192))
  o["image_512"] = jstr(avatar_url(self.id, 512))
  o["status_text_canonical"] = jstr("")
  o["is_custom_image"] = jbool(false)
  o["email"] = jstr(self.email)
  ignore(team_id)
  // Anything the caller seeded that this model does not name. Last, so a
  // consumer cannot accidentally shadow a field the renderer computed.
  for key, value in self.profile_extra {
    o[key] = value
  }
  Json::object(o)
}

///|
/// The part of a real name before the first space, and the part after it.
/// Slack derives `first_name`/`last_name` this way when a user has not set
/// them, and a name with no space has an empty last name rather than a
/// duplicated first one.
fn first_word(s : String) -> String {
  match s.find(" ") {
    Some(i) => s[0:i].to_owned()
    None => s
  }
}

///|
fn rest_words(s : String) -> String {
  match s.find(" ") {
    Some(i) => s[i + 1:].to_owned()
    None => ""
  }
}

///|
/// One user, as `users.info` and `users.list` both send them.
pub fn User::to_json(
  self : Self,
  team_id : String,
  include_locale? : Bool = false,
) -> Json {
  let o : Map[String, Json] = Map([])
  o["id"] = jstr(self.id)
  o["team_id"] = jstr(self.team_id)
  o["name"] = jstr(self.name)
  o["deleted"] = jbool(self.deleted)
  o["color"] = jstr("9f69e7")
  o["real_name"] = jstr(self.real_name)
  o["tz"] = jstr(self.tz)
  o["tz_label"] = jstr(self.tz_label)
  o["tz_offset"] = jint(self.tz_offset)
  o["profile"] = self.profile_json(team_id)
  o["is_admin"] = jbool(self.is_admin)
  o["is_owner"] = jbool(self.is_owner)
  o["is_primary_owner"] = jbool(self.is_owner)
  o["is_restricted"] = jbool(false)
  o["is_ultra_restricted"] = jbool(false)
  o["is_bot"] = jbool(self.is_bot)
  o["is_app_user"] = jbool(false)
  o["is_email_confirmed"] = jbool(true)
  o["updated"] = ji64(self.updated)
  if include_locale {
    o["locale"] = jstr("en-US")
  }
  Json::object(o)
}

///|
/// One conversation.
///
/// `include_num_members` and `include_locale` follow the two flags
/// `conversations.info` takes; `for_list` adds the three fields
/// `conversations.list` carries for a DM and `conversations.info`'s sample does
/// not (`user`, `is_user_deleted`, `priority`).
///
/// `include_membership` is off for `users.conversations` alone, whose recorded
/// sample carries neither `is_member` nor `num_members`. That is not a gap in
/// the recording: the method answers with the conversations a user is already
/// in, so "are they a member" has one answer and Slack does not send it.
pub fn Channel::to_json(
  self : Self,
  include_num_members? : Bool = false,
  include_locale? : Bool = false,
  include_membership? : Bool = true,
  for_list? : Bool = false,
) -> Json {
  let o : Map[String, Json] = Map([])
  o["id"] = jstr(self.id)
  // A DM has no name in Slack's payload at all, and a client that showed an
  // empty one would render a blank row. `conversations.list` is where this is
  // visible, because it returns every kind at once.
  if self.kind != Im {
    o["name"] = jstr(self.name)
    o["name_normalized"] = jstr(self.name)
  }
  o["is_channel"] = jbool(self.kind == Public || self.kind == Private)
  o["is_group"] = jbool(self.kind == Private)
  o["is_im"] = jbool(self.kind == Im)
  o["is_mpim"] = jbool(self.kind == Mpim)
  o["is_private"] = jbool(
    self.kind == Private || self.kind == Im || self.kind == Mpim,
  )
  o["created"] = ji64(self.created)
  o["creator"] = jstr(self.creator)
  o["is_archived"] = jbool(self.is_archived)
  o["is_general"] = jbool(self.name == "general")
  o["unlinked"] = jint(0)
  o["is_shared"] = jbool(false)
  o["is_org_shared"] = jbool(false)
  o["is_ext_shared"] = jbool(false)
  o["is_pending_ext_shared"] = jbool(false)
  o["pending_shared"] = Json::array([])
  o["pending_connected_team_ids"] = Json::array([])
  o["shared_team_ids"] = Json::array([])
  if include_membership {
    if include_membership {
      o["is_member"] = jbool(true)
    }
  }
  o["previous_names"] = Json::array(self.previous_names.map(n => jstr(n)))
  if for_list && self.kind == Im {
    o["user"] = jstr(if self.members.is_empty() { "" } else { self.members[0] })
    o["is_user_deleted"] = jbool(false)
    o["priority"] = jint(0)
  }
  if self.kind != Im {
    o["topic"] = self.topic.to_json()
    o["purpose"] = self.purpose.to_json()
  }
  if include_num_members && include_membership {
    o["num_members"] = jint(self.members.length())
  }
  if include_locale {
    o["locale"] = jstr("en-US")
  }
  Json::object(o)
}

///|
pub fn ChannelText::to_json(self : Self) -> Json {
  Json::object({
    "value": jstr(self.value),
    "creator": jstr(self.creator),
    "last_set": ji64(self.last_set),
  })
}

///|
/// One message, as it appears inside `conversations.history` and friends.
///
/// `blocks` comes back out exactly as it went in. That is the property
/// ext/test/mockshape's round-trip check leans on, and the reason `Message`
/// stores `Json` rather than parsed blocks.
pub fn Message::to_json(self : Self, channel_id? : String = "") -> Json {
  let o : Map[String, Json] = Map([])
  o["type"] = jstr("message")
  if self.subtype is Some(sub) {
    o["subtype"] = jstr(sub)
  }
  o["user"] = jstr(self.user)
  if self.bot_id is Some(id) {
    o["bot_id"] = jstr(id)
  }
  o["text"] = jstr(self.text)
  o["ts"] = jstr(self.ts)
  if self.blocks is Some(blocks) {
    o["blocks"] = blocks
  }
  if self.attachments is Some(attachments) {
    o["attachments"] = attachments
  }
  if self.metadata is Some(metadata) {
    o["metadata"] = metadata
  }
  if self.thread_ts is Some(thread_ts) {
    o["thread_ts"] = jstr(thread_ts)
    // The counters only exist on a parent. A reply carries `thread_ts` and
    // nothing else, which is how a client tells the two apart.
    if thread_ts == self.ts {
      o["reply_count"] = jint(self.reply_count)
      o["reply_users_count"] = jint(self.reply_users.length())
      o["reply_users"] = Json::array(self.reply_users.map(u => jstr(u)))
      if self.latest_reply is Some(latest) {
        o["latest_reply"] = jstr(latest)
      }
    }
  }
  if !self.reactions.is_empty() {
    o["reactions"] = Json::array(self.reactions.map(r => r.to_json()))
  }
  if self.edited is Some(edited) {
    o["edited"] = Json::object({ "user": jstr(edited.0), "ts": jstr(edited.1) })
  }
  if !channel_id.is_empty() {
    o["channel"] = jstr(channel_id)
  }
  Json::object(o)
}

///|
pub fn Reaction::to_json(self : Self) -> Json {
  Json::object({
    "name": jstr(self.name),
    "users": Json::array(self.users.map(u => jstr(u))),
    "count": jint(self.users.length()),
  })
}

///|
pub fn Bookmark::to_json(self : Self) -> Json {
  Json::object({
    "id": jstr(self.id),
    "channel_id": jstr(self.channel_id),
    "title": jstr(self.title),
    "link": jstr(self.link),
    "emoji": jstr(self.emoji),
    "type": jstr(self.type_),
    "date_created": ji64(self.date_created),
  })
}

///|
pub fn Usergroup::to_json(
  self : Self,
  include_count? : Bool = false,
  include_users? : Bool = false,
) -> Json {
  let o : Map[String, Json] = Map([])
  o["id"] = jstr(self.id)
  o["team_id"] = jstr(self.team_id)
  o["is_usergroup"] = jbool(true)
  o["name"] = jstr(self.name)
  o["description"] = jstr(self.description)
  o["handle"] = jstr(self.handle)
  o["is_external"] = jbool(false)
  o["date_create"] = ji64(self.date_create)
  o["date_update"] = ji64(self.date_update)
  o["date_delete"] = ji64(self.date_delete)
  o["auto_provision"] = jbool(false)
  o["is_subteam"] = jbool(true)
  o["is_visible"] = jbool(true)
  o["channel_count"] = jint(self.channels.length())
  o["created_by"] = jstr("")
  o["updated_by"] = jstr("")
  o["prefs"] = Json::object({
    "channels": Json::array(self.channels.map(c => jstr(c))),
    "groups": Json::array([]),
  })
  if include_users {
    o["users"] = Json::array(self.users.map(u => jstr(u)))
  }
  if include_count {
    o["user_count"] = jint(self.users.length())
  }
  Json::object(o)
}

///|
pub fn FileRecord::to_json(self : Self) -> Json {
  Json::object({
    "id": jstr(self.id),
    "created": ji64(self.created),
    "timestamp": ji64(self.created),
    "name": jstr(self.name),
    "title": jstr(self.title),
    "mimetype": jstr(self.mimetype),
    "filetype": jstr(self.filetype),
    "pretty_type": jstr(self.filetype),
    "user": jstr(self.user),
    "size": jint(self.size),
    "mode": jstr("hosted"),
    "is_external": jbool(false),
    "external_type": jstr(""),
    "is_public": jbool(true),
    "public_url_shared": jbool(false),
    "url_private": jstr(
      "https://mock.slack.local/files/\{self.id}/\{self.name}",
    ),
    "url_private_download": jstr(
      "https://mock.slack.local/files/\{self.id}/download/\{self.name}",
    ),
    "permalink": jstr("https://mock.slack.local/files/\{self.user}/\{self.id}"),
    "channels": Json::array(self.channels.map(c => jstr(c))),
    "groups": Json::array([]),
    "ims": Json::array([]),
    "comments_count": jint(0),
  })
}

///|
/// A view, as `views.open` and friends echo it back.
///
/// The `view` a caller sent is stored and returned as `Json`, with the
/// server-assigned fields merged over it -- the same discipline as `Message`,
/// and for the same reason: `blocks` inside a view must survive the round trip.
pub fn ViewRecord::to_json(self : Self, team_id : String) -> Json {
  let o : Map[String, Json] = Map([])
  if self.payload is Object(fields) {
    for key, value in fields {
      o[key] = value
    }
  }
  o["id"] = jstr(self.id)
  o["team_id"] = jstr(team_id)
  o["type"] = jstr(
    match self.kind {
      Modal => "modal"
      Home => "home"
    },
  )
  o["hash"] = jstr(self.hash)
  o["state"] = Json::object({ "values": Json::object(Map([])) })
  o["root_view_id"] = jstr(self.root_view_id)
  o["previous_view_id"] = match self.previous_view_id {
    Some(id) => jstr(id)
    None => Json::null()
  }
  o["app_id"] = jstr("")
  o["bot_id"] = jstr("")
  o["external_id"] = jstr(self.external_id.unwrap_or(""))
  Json::object(o)
}

///|
pub fn ScheduledMessage::to_json(self : Self) -> Json {
  let o : Map[String, Json] = Map([])
  o["id"] = jstr(self.id)
  o["channel_id"] = jstr(self.channel)
  o["post_at"] = ji64(self.post_at)
  o["date_created"] = ji64(self.date_created)
  o["text"] = jstr(self.text)
  Json::object(o)
}
