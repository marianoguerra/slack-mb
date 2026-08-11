// reactions.*, pins.* and bookmarks.*.

///|
/// `reactions.add`.
///
/// `already_reacted` is the interesting refusal: an app that reacts on every
/// event and does not handle it will log an error on the second identical
/// event, which is a real and common bug.
fn Workspace::reactions_add(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let channel = self.channel_arg(form)
  let ts = form.require_as("timestamp", "message_not_found")
  let name = normalize_emoji(form.require_as("name", "invalid_name"))
  guard self.find_message(channel, ts) is Some(message) else {
    raise refuse("message_not_found")
  }
  for reaction in message.reactions {
    if reaction.name == name {
      if reaction.users.contains(auth.user_id) {
        raise refuse("already_reacted")
      }
      reaction.users.push(auth.user_id)
      return Map([])
    }
  }
  message.reactions.push({ name, users: [auth.user_id] })
  Map([])
}

///|
/// Emoji names travel without their colons. Slack accepts `:wave:` in message
/// TEXT and requires `wave` in `reactions.add`, and sending the colons is the
/// mistake people make first -- so they are stripped rather than refused,
/// because Slack does accept them here too.
fn normalize_emoji(raw : String) -> String {
  let mut name = raw
  if name.has_prefix(":") {
    name = name[1:].to_owned()
  }
  if name.has_suffix(":") {
    name = name[0:name.length() - 1].to_owned()
  }
  name
}

///|
/// `reactions.remove`.
fn Workspace::reactions_remove(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let channel = self.channel_arg(form)
  let ts = form.require_as("timestamp", "message_not_found")
  let name = normalize_emoji(form.require_as("name", "invalid_name"))
  guard self.find_message(channel, ts) is Some(message) else {
    raise refuse("message_not_found")
  }
  for i in 0..<message.reactions.length() {
    let reaction = message.reactions[i]
    if reaction.name == name {
      guard reaction.users.contains(auth.user_id) else {
        raise refuse("no_reaction")
      }
      remove_string(reaction.users, auth.user_id)
      // A reaction nobody holds is not a reaction. Slack drops it from the
      // message rather than leaving a zero count, and a client rendering one
      // would show an empty pill.
      if reaction.users.is_empty() {
        message.reactions.remove(i) |> ignore
      }
      return Map([])
    }
  }
  raise refuse("no_reaction")
}

///|
/// `reactions.get`: one item and its reactions.
fn Workspace::reactions_get(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  // `file` and `file_comment` are the other two things reactions attach to.
  // Neither is modelled, and answering `not_reactable` says so honestly rather
  // than pretending the file has no reactions.
  if form.has("file") || form.has("file_comment") {
    raise refuse("not_reactable")
  }
  let channel = self.channel_arg(form)
  let ts = form.require_as("timestamp", "message_not_found")
  guard self.find_message(channel, ts) is Some(message) else {
    raise refuse("message_not_found")
  }
  {
    "type": Json::string("message"),
    "channel": Json::string(channel.id),
    "message": message.to_json(),
  }
}

///|
/// `reactions.list`: every item the user has reacted to.
fn Workspace::reactions_list(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  let who = form.get("user").unwrap_or(auth.user_id)
  let items : Array[Json] = []
  for _, channel in self.channels {
    for message in channel.messages {
      let mut reacted = false
      for reaction in message.reactions {
        if reaction.users.contains(who) {
          reacted = true
        }
      }
      if reacted {
        items.push(
          Json::object({
            "type": Json::string("message"),
            "channel": Json::string(channel.id),
            "message": message.to_json(),
          }),
        )
      }
    }
  }
  let (page, next_cursor) = page_of(items, form)
  {
    "items": Json::array(page),
    "response_metadata": Json::object({
      "next_cursor": Json::string(next_cursor),
    }),
  }
}

///|
/// `pins.add`.
fn Workspace::pins_add(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let ts = form.require_as("timestamp", "message_not_found")
  guard self.find_message(channel, ts) is Some(_) else {
    raise refuse("message_not_found")
  }
  if channel.pins.contains(ts) {
    raise refuse("already_pinned")
  }
  channel.pins.push(ts)
  Map([])
}

///|
/// `pins.remove`.
fn Workspace::pins_remove(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let ts = form.require_as("timestamp", "message_not_found")
  guard channel.pins.contains(ts) else { raise refuse("no_pin") }
  remove_string(channel.pins, ts)
  Map([])
}

///|
/// `pins.list`.
///
/// The `created_by` is the channel's creator rather than whoever pinned it:
/// the store does not remember who pinned a message, because nothing in the
/// typed client surface asks. If that becomes interesting, `Channel.pins`
/// grows from `Array[String]` to a record and this line changes.
fn Workspace::pins_list(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let items : Array[Json] = []
  for ts in channel.pins {
    guard self.find_message(channel, ts) is Some(message) else { continue }
    items.push(
      Json::object({
        "type": Json::string("message"),
        "created": Json::number(
          (self.now / 1000L).to_double(),
          repr=(self.now / 1000L).to_string(),
        ),
        "created_by": Json::string(channel.creator),
        "channel": Json::string(channel.id),
        "message": message.to_json(),
      }),
    )
  }
  { "items": Json::array(items) }
}

///|
/// `bookmarks.add`.
fn Workspace::bookmarks_add(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form, allow_name=false)
  let title = form.require_as("title", "invalid_arguments")
  // `type` is required and Slack only documents `link`. Anything else is
  // refused rather than stored, because a bookmark of an unknown type is a
  // thing no client knows how to render.
  let type_ = form.require_as("type", "invalid_arguments")
  guard type_ == "link" else { raise refuse("invalid_bookmark_type") }
  let id = self.add_bookmark(
    channel=channel.id,
    title~,
    link=form.get("link").unwrap_or(""),
    emoji=form.get("emoji").unwrap_or(""),
    type_~,
  )
  for bookmark in channel.bookmarks {
    if bookmark.id == id {
      return { "bookmark": bookmark.to_json() }
    }
  }
  raise refuse("internal_error")
}

///|
/// `bookmarks.list`.
fn Workspace::bookmarks_list(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  // `channel_id`, not `channel`. The only method in the implemented surface
  // that spells it that way, which is why it does not go through
  // `channel_arg`.
  let id = form.require_as("channel_id", "channel_not_found")
  let channel = self.resolve_channel(id)
  { "bookmarks": Json::array(channel.bookmarks.map(b => b.to_json())) }
}
