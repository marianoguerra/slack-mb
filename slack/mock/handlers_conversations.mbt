// The conversations.* family.

///|
/// Resolve a `channel` argument to a channel.
///
/// `allow_name` is the whole reason this is one function called from many
/// places instead of a lookup at each site. Slack accepts a channel NAME
/// (`#slack-integration`) for `chat.postMessage` and refuses the same string
/// with `channel_not_found` for `chat.update`, `chat.delete` and
/// `conversations.history` -- a genuine asymmetry in the API, discovered by
/// running `ext/cmd/integration` against a live workspace (see its header
/// comment) and handled there by threading the resolved id out of the post
/// response into everything downstream.
///
/// Reproducing it is the point: an app that only ever ran against a mock which
/// accepted names everywhere would break the first time it updated a message.
fn Workspace::resolve_channel(
  self : Self,
  spec : String,
  allow_name? : Bool = false,
) -> Channel raise Refusal {
  if self.channels.get(spec) is Some(channel) {
    return channel
  }
  if allow_name {
    let wanted = if spec.has_prefix("#") { spec[1:].to_owned() } else { spec }
    for _, channel in self.channels {
      if channel.kind != Im && channel.name == wanted {
        return channel
      }
    }
  }
  raise refuse("channel_not_found")
}

///|
/// The `channel` argument, required, resolved.
fn Workspace::channel_arg(
  self : Self,
  form : Form,
  allow_name? : Bool = false,
) -> Channel raise Refusal {
  self.resolve_channel(
    form.require_as("channel", "channel_not_found"),
    allow_name~,
  )
}

///|
/// `conversations.list`.
///
/// `types` defaults to public channels alone, which is Slack's default and the
/// one people are surprised by: a bot that lists conversations and cannot find
/// its DMs has usually just not asked for them.
fn Workspace::conversations_list(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  ignore(auth)
  let types = form.csv("types").unwrap_or(["public_channel"])
  let exclude_archived = form.flag("exclude_archived", default=false)
  let matching : Array[Json] = []
  for _, channel in self.channels {
    if exclude_archived && channel.is_archived {
      continue
    }
    if !type_matches(channel.kind, types) {
      continue
    }
    matching.push(channel.to_json(include_num_members=true, for_list=true))
  }
  let (page, next_cursor) = page_of(matching, form)
  {
    "channels": Json::array(page),
    "response_metadata": Json::object({
      "next_cursor": Json::string(next_cursor),
    }),
  }
}

///|
/// Whether a conversation is one of the kinds asked for.
///
/// The four names are Slack's, and `private_channel` covers a private channel
/// only -- not a DM, which is `im`, even though both are private. That
/// distinction is why `types` exists at all.
fn type_matches(kind : ChannelKind, types : Array[String]) -> Bool {
  let wanted = match kind {
    Public => "public_channel"
    Private => "private_channel"
    Im => "im"
    Mpim => "mpim"
  }
  types.contains(wanted)
}

///|
/// `conversations.info`.
fn Workspace::conversations_info(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  {
    "channel": channel.to_json(
      include_num_members=form.flag("include_num_members", default=false),
      include_locale=form.flag("include_locale", default=false),
    ),
  }
}

///|
/// `conversations.members`: ids only, paginated.
fn Workspace::conversations_members(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let members = channel.members.map(id => Json::string(id))
  let (page, next_cursor) = page_of(members, form)
  {
    "members": Json::array(page),
    "response_metadata": Json::object({
      "next_cursor": Json::string(next_cursor),
    }),
  }
}

///|
/// `conversations.history`.
///
/// NEWEST FIRST, which is the thing to get right: Slack returns a channel's
/// history in reverse chronological order, `latest` is the newer bound and
/// `oldest` the older one, and a client that assumed the array was oldest-first
/// would render every conversation backwards. The store keeps them
/// oldest-first, so this reverses on the way out.
///
/// The channel is resolved by ID ONLY -- a `#name` here is `channel_not_found`.
/// See `resolve_channel`.
fn Workspace::conversations_history(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let inclusive = form.flag("inclusive", default=false)
  let selected : Array[Json] = []
  // Reverse iteration: newest first.
  let mut i = channel.messages.length() - 1
  while i >= 0 {
    let message = channel.messages[i]
    i -= 1
    // A reply belongs to its thread, not to the channel's top level. Slack
    // omits replies from history unless they were also broadcast, which is why
    // a channel with a busy thread looks quiet here.
    if message.thread_ts is Some(parent) && parent != message.ts {
      continue
    }
    if !in_ts_window(message.ts, form, inclusive~) {
      continue
    }
    selected.push(message.to_json())
  }
  let (page, next_cursor) = page_of(selected, form)
  {
    "messages": Json::array(page),
    "has_more": Json::boolean(!next_cursor.is_empty()),
    "pin_count": Json::number(
      channel.pins.length().to_double(),
      repr=channel.pins.length().to_string(),
    ),
    "response_metadata": Json::object({
      "next_cursor": Json::string(next_cursor),
    }),
  }
}

///|
/// Whether a timestamp falls inside the `oldest`/`latest` bounds.
///
/// Both are EXCLUSIVE unless `inclusive` is set, which is Slack's rule and the
/// reason paging through history by passing the last `ts` as the next `latest`
/// does not repeat a message.
fn in_ts_window(ts : String, form : Form, inclusive~ : Bool) -> Bool {
  if form.get("oldest") is Some(oldest) && !oldest.is_empty() {
    let cmp = ts_compare(ts, oldest)
    if cmp < 0 || (cmp == 0 && !inclusive) {
      return false
    }
  }
  if form.get("latest") is Some(latest) && !latest.is_empty() {
    let cmp = ts_compare(ts, latest)
    if cmp > 0 || (cmp == 0 && !inclusive) {
      return false
    }
  }
  true
}

///|
/// `conversations.replies`: the parent first, then its replies oldest-first.
///
/// The opposite order from `conversations.history`, and also Slack's. A thread
/// reads top to bottom; a channel reads bottom to top.
fn Workspace::conversations_replies(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let root_ts = form.require_as("ts", "thread_not_found")
  let inclusive = form.flag("inclusive", default=false)
  let selected : Array[Json] = []
  let mut found_root = false
  for message in channel.messages {
    let belongs = message.ts == root_ts ||
      (message.thread_ts is Some(parent) && parent == root_ts)
    if !belongs {
      continue
    }
    if message.ts == root_ts {
      found_root = true
      // The root is always returned, whatever the window says: it is the thing
      // that was asked for.
      selected.push(message.to_json())
      continue
    }
    if !in_ts_window(message.ts, form, inclusive~) {
      continue
    }
    selected.push(message.to_json())
  }
  guard found_root else { raise refuse("thread_not_found") }
  let (page, next_cursor) = page_of(selected, form)
  {
    "messages": Json::array(page),
    "has_more": Json::boolean(!next_cursor.is_empty()),
    "response_metadata": Json::object({
      "next_cursor": Json::string(next_cursor),
    }),
  }
}

///|
/// `conversations.create`.
fn Workspace::conversations_create(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let name = normalize_channel_name(form.require_as("name", "invalid_name"))
  guard !name.is_empty() else { raise refuse("invalid_name") }
  for _, existing in self.channels {
    if existing.kind != Im && existing.name == name {
      raise refuse("name_taken")
    }
  }
  let id = self.add_channel(
    name~,
    is_private=form.flag("is_private", default=false),
    members=[auth.user_id],
    creator=auth.user_id,
  )
  guard self.channels.get(id) is Some(channel) else {
    raise refuse("internal_error")
  }
  {
    "channel": channel.to_json(),
    // Present and empty on success. Slack puts the reason a name was altered
    // here, and an app that shows it to a user needs the field to exist.
    "detail": Json::string(""),
  }
}

///|
/// Slack's channel-name rules, as far as they matter here: lowercase, no
/// leading `#`. The real ones also strip punctuation and cap the length; those
/// are not reproduced, because a test that depended on them would be testing a
/// guess.
fn normalize_channel_name(raw : String) -> String {
  let trimmed = if raw.has_prefix("#") { raw[1:].to_owned() } else { raw }
  trimmed.to_lower()
}

///|
/// `conversations.invite`.
fn Workspace::conversations_invite(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let users = match form.csv("users") {
    Some(list) if !list.is_empty() => list
    _ => raise refuse("no_user")
  }
  for id in users {
    guard self.users.get(id) is Some(_) else { raise refuse("user_not_found") }
    if channel.members.contains(id) {
      raise refuse("already_in_channel")
    }
  }
  for id in users {
    channel.members.push(id)
  }
  { "channel": channel.to_json() }
}

///|
/// `conversations.join`. Joining a channel you are already in succeeds --
/// Slack makes it idempotent, and an app that re-joins on every start relies
/// on that.
fn Workspace::conversations_join(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let channel = self.channel_arg(form)
  guard channel.kind == Public else { raise refuse("channel_not_found") }
  if channel.is_archived {
    raise refuse("is_archived")
  }
  if !channel.members.contains(auth.user_id) {
    channel.members.push(auth.user_id)
  }
  { "channel": channel.to_json() }
}

///|
/// `conversations.kick`.
fn Workspace::conversations_kick(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let user = form.require_as("user", "user_not_found")
  guard channel.members.contains(user) else { raise refuse("not_in_channel") }
  remove_string(channel.members, user)
  Map([])
}

///|
/// `conversations.leave`.
fn Workspace::conversations_leave(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let channel = self.channel_arg(form)
  remove_string(channel.members, auth.user_id)
  Map([])
}

///|
/// Drop the first occurrence of a string from an array, in place.
fn remove_string(items : Array[String], wanted : String) -> Unit {
  for i in 0..<items.length() {
    if items[i] == wanted {
      items.remove(i) |> ignore
      return
    }
  }
}

///|
/// `conversations.archive`.
fn Workspace::conversations_archive(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  if channel.is_archived {
    raise refuse("already_archived")
  }
  // Slack refuses to archive #general, and says so with its own code. An app
  // that swept up old channels would otherwise take the workspace's default
  // channel with it.
  if channel.name == "general" {
    raise refuse("cant_archive_general")
  }
  channel.is_archived = true
  Map([])
}

///|
/// `conversations.close`: for a DM or MPIM, the counterpart of `open`.
///
/// `already_closed` and `no_op` both report "nothing happened", and both are in
/// Slack's response. They are the same value here, which is what Slack sends
/// too -- two names for one fact, kept because a client may read either.
fn Workspace::conversations_close(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let was_closed = !channel.is_open
  channel.is_open = false
  {
    "no_op": Json::boolean(was_closed),
    "already_closed": Json::boolean(was_closed),
  }
}

///|
/// `conversations.open`: find or create the DM with a user.
///
/// Its `channel` object is much SMALLER than every other method's -- no
/// `creator`, no `name`, no `topic`, no `is_member` -- which the corpus pins
/// and which is why this does not go through `Channel::to_json`. A DM has none
/// of those things, and answering with them would invent state.
fn Workspace::conversations_open(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  // Re-opening a conversation by id, rather than opening one with a user.
  if form.get("channel") is Some(id) && !id.is_empty() {
    let channel = self.resolve_channel(id)
    let was_open = channel.is_open
    channel.is_open = true
    return {
      "no_op": Json::boolean(was_open),
      "already_open": Json::boolean(was_open),
      "channel": self.im_json(channel),
    }
  }
  let users = match form.csv("users") {
    Some(list) if !list.is_empty() => list
    _ => raise refuse("users_not_found")
  }
  for id in users {
    guard self.users.get(id) is Some(_) else { raise refuse("users_not_found") }
  }
  // An existing conversation with exactly these members is reused, which is
  // what makes `conversations.open` safe to call before every DM.
  let wanted = if users.length() == 1 { users } else { users }
  for _, channel in self.channels {
    let kind_matches = if wanted.length() == 1 {
      channel.kind == Im
    } else {
      channel.kind == Mpim
    }
    if kind_matches && same_members(channel.members, wanted) {
      let was_open = channel.is_open
      channel.is_open = true
      return {
        "no_op": Json::boolean(was_open),
        "already_open": Json::boolean(was_open),
        "channel": self.im_json(channel),
      }
    }
  }
  guard !form.flag("prevent_creation", default=false) else {
    raise refuse("channel_not_found")
  }
  ignore(auth)
  let id = if wanted.length() == 1 {
    self.add_im(user=wanted[0])
  } else {
    self.add_mpim(users=wanted)
  }
  guard self.channels.get(id) is Some(channel) else {
    raise refuse("internal_error")
  }
  {
    "no_op": Json::boolean(false),
    "already_open": Json::boolean(false),
    "channel": self.im_json(channel),
  }
}

///|
/// Whether two membership lists hold the same ids, order aside.
fn same_members(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for id in b {
    if !a.contains(id) {
      return false
    }
  }
  true
}

///|
/// The small channel object `conversations.open` answers with.
fn Workspace::im_json(self : Self, channel : Channel) -> Json {
  Json::object({
    "id": Json::string(channel.id),
    "created": Json::number(
      channel.created.to_double(),
      repr=channel.created.to_string(),
    ),
    "is_im": Json::boolean(channel.kind == Im),
    "is_org_shared": Json::boolean(false),
    "is_archived": Json::boolean(channel.is_archived),
    "is_open": Json::boolean(channel.is_open),
    "user": Json::string(
      if channel.members.is_empty() {
        ""
      } else {
        channel.members[0]
      },
    ),
    "last_read": Json::string(channel.last_read),
    "unread_count": Json::number(0.0, repr="0"),
    "unread_count_display": Json::number(0.0, repr="0"),
    "priority": Json::number(0.0, repr="0"),
    "updated": Json::number(
      (self.now / 1000L).to_double(),
      repr=(self.now / 1000L).to_string(),
    ),
  })
}

///|
/// `conversations.rename`.
fn Workspace::conversations_rename(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let name = normalize_channel_name(form.require_as("name", "invalid_name"))
  guard !name.is_empty() else { raise refuse("invalid_name") }
  for _, existing in self.channels {
    if existing.id != channel.id && existing.kind != Im && existing.name == name {
      raise refuse("name_taken")
    }
  }
  // The old name is kept. Slack does this so that a link to the previous name
  // still resolves, and `previous_names` is where a client finds it.
  if !channel.name.is_empty() && !channel.previous_names.contains(channel.name) {
    channel.previous_names.push(channel.name)
  }
  channel.name = name
  { "channel": channel.to_json() }
}

///|
/// `conversations.mark`: move the read cursor.
fn Workspace::conversations_mark(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  channel.last_read = form.require_as("ts", "invalid_timestamp")
  Map([])
}

///|
/// `conversations.setPurpose`.
fn Workspace::conversations_set_purpose(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let channel = self.channel_arg(form)
  let purpose = form.get("purpose").unwrap_or("")
  channel.purpose = {
    value: purpose,
    creator: auth.user_id,
    last_set: self.now / 1000L,
  }
  { "channel": channel.to_json() }
}

///|
/// `conversations.setTopic`.
fn Workspace::conversations_set_topic(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let channel = self.channel_arg(form)
  let topic = form.get("topic").unwrap_or("")
  channel.topic = {
    value: topic,
    creator: auth.user_id,
    last_set: self.now / 1000L,
  }
  { "channel": channel.to_json() }
}
