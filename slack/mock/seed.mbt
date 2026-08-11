// Setting the stage.
//
// Every constructor returns the id it minted, so a seeding block reads top-down
// with no id literals in it and no guessing at what the counter is up to.
//
// Seeding is NOT the API. It bypasses scope checks, it does not advance the
// clock the way a handled call does, and it does not refuse anything -- adding
// a message to a channel that does not exist is a no-op rather than a
// `channel_not_found`. That is deliberate: this is how you arrange the world
// before the code under test runs, and a setup step that could fail the way a
// call fails would make every test carry an error path it does not care about.

///|
/// An empty workspace.
///
/// `now` is epoch milliseconds and defaults to 2023-11-14T22:13:20Z -- a real
/// instant, chosen only because it is round in seconds, so the timestamps this
/// mints look like Slack's rather than like 1970.
pub fn Workspace::new(
  team_id? : String = "T00000001",
  team_name? : String = "Mock Workspace",
  domain? : String = "mock",
  email_domain? : String = "example.com",
  enterprise_id? : String,
  now? : Int64 = 1700000000000L,
) -> Workspace {
  {
    team: { id: team_id, name: team_name, domain, email_domain, enterprise_id },
    users: Map([]),
    channels: Map([]),
    usergroups: Map([]),
    files: Map([]),
    views: Map([]),
    scheduled: Map([]),
    tokens: Map([]),
    ids: IdSeq::new(),
    faults: Map([]),
    calls: [],
    now,
    tick_millis: 1000L,
    strict_unknown: false,
    validate_blocks: true,
    demo_ids_slot: Map([]),
  }
}

///|
/// Whether the mock parses `blocks` and refuses `invalid_blocks`.
///
/// On by default. Turn it off for a test that wants to post a payload this
/// library cannot model yet and does not care whether Slack would have taken
/// it -- and see the note on `check_blocks` about how much of that behaviour is
/// reconstructed rather than recorded.
pub fn Workspace::set_validate_blocks(self : Self, on : Bool) -> Unit {
  self.validate_blocks = on
}

///|
/// Answer `unknown_method` for a real Slack method this mock has not modelled,
/// exactly as Slack would, instead of the clearer `mock_method_not_implemented`.
pub fn Workspace::set_strict_unknown(self : Self, on : Bool) -> Unit {
  self.strict_unknown = on
}

///|
/// Add a user. Returns the minted id.
pub fn Workspace::add_user(
  self : Self,
  name~ : String,
  real_name? : String,
  display_name? : String,
  email? : String,
  title? : String = "",
  is_bot? : Bool = false,
  bot_id? : String,
  is_admin? : Bool = false,
  is_owner? : Bool = false,
  tz? : String = "America/Los_Angeles",
  tz_label? : String = "Pacific Standard Time",
  tz_offset? : Int = -28800,
  id? : String,
) -> String {
  let user_id = match id {
    Some(given) => given
    None => self.next_user_id()
  }
  let real = real_name.unwrap_or(name)
  self.users[user_id] = {
    id: user_id,
    team_id: self.team.id,
    name,
    real_name: real,
    display_name: display_name.unwrap_or(real),
    email: email.unwrap_or(name + "@" + self.team.email_domain),
    title,
    phone: "",
    status_text: "",
    status_emoji: "",
    tz,
    tz_label,
    tz_offset,
    is_bot,
    bot_id,
    is_admin,
    is_owner,
    deleted: false,
    presence: "active",
    updated: self.now / 1000L,
    profile_extra: Map([]),
  }
  user_id
}

///|
/// Add a public or private channel. Returns the minted id.
pub fn Workspace::add_channel(
  self : Self,
  name~ : String,
  is_private? : Bool = false,
  members? : Array[String] = [],
  topic? : String = "",
  purpose? : String = "",
  creator? : String,
  is_archived? : Bool = false,
  id? : String,
) -> String {
  let channel_id = match id {
    Some(given) => given
    None => self.next_channel_id()
  }
  let creator_id = creator.unwrap_or(
    if members.is_empty() {
      ""
    } else {
      members[0]
    },
  )
  let seconds = self.now / 1000L
  self.channels[channel_id] = {
    id: channel_id,
    name,
    kind: if is_private {
      Private
    } else {
      Public
    },
    created: seconds,
    creator: creator_id,
    is_archived,
    is_open: true,
    members: members.copy(),
    topic: { value: topic, creator: creator_id, last_set: seconds },
    purpose: { value: purpose, creator: creator_id, last_set: seconds },
    messages: [],
    pins: [],
    bookmarks: [],
    previous_names: [],
    last_read: "0000000000.000000",
  }
  channel_id
}

///|
/// Add a direct message conversation with one user. Returns the minted id.
pub fn Workspace::add_im(self : Self, user~ : String, id? : String) -> String {
  let channel_id = match id {
    Some(given) => given
    None => self.next_im_id()
  }
  let seconds = self.now / 1000L
  self.channels[channel_id] = {
    id: channel_id,
    // A DM has no name. Slack's own payload omits the field entirely, which
    // `render.mbt` handles by branching on `kind`.
    name: "",
    kind: Im,
    created: seconds,
    creator: user,
    is_archived: false,
    is_open: true,
    members: [user],
    topic: ChannelText::empty(),
    purpose: ChannelText::empty(),
    messages: [],
    pins: [],
    bookmarks: [],
    previous_names: [],
    last_read: "0000000000.000000",
  }
  channel_id
}

///|
/// Add a group direct message. Returns the minted id.
pub fn Workspace::add_mpim(
  self : Self,
  users~ : Array[String],
  id? : String,
) -> String {
  let channel_id = match id {
    Some(given) => given
    None => self.next_mpim_id()
  }
  let seconds = self.now / 1000L
  self.channels[channel_id] = {
    id: channel_id,
    // Slack names an mpim after its members: `mpdm-alice--bob--carol-1`. The
    // shape is reproduced because `conversations.list` returns it and an app
    // that displays a conversation name would otherwise show nothing.
    name: "mpdm-" + users.map(u => self.user_name(u)).join("--") + "-1",
    kind: Mpim,
    created: seconds,
    creator: if users.is_empty() {
      ""
    } else {
      users[0]
    },
    is_archived: false,
    is_open: true,
    members: users.copy(),
    topic: ChannelText::empty(),
    purpose: ChannelText::empty(),
    messages: [],
    pins: [],
    bookmarks: [],
    previous_names: [],
    last_read: "0000000000.000000",
  }
  channel_id
}

///|
/// A user's handle, or their id when they are not in this workspace.
fn Workspace::user_name(self : Self, id : String) -> String {
  match self.users.get(id) {
    Some(user) => user.name
    None => id
  }
}

///|
/// Post a message as if a user had. Returns its `ts`.
///
/// A no-op returning the empty string when the channel does not exist -- see
/// the note at the top of this file about seeding not refusing.
pub fn Workspace::add_message(
  self : Self,
  channel~ : String,
  user~ : String,
  text~ : String,
  blocks? : Array[@blocks.LayoutBlock],
  attachments? : Json,
  subtype? : String,
  thread_ts? : String,
  ts? : String,
) -> String {
  guard self.channels.get(channel) is Some(target) else { return "" }
  let stamp = match ts {
    Some(given) => given
    None => {
      self.advance(self.tick_millis)
      self.next_ts()
    }
  }
  let message : Message = {
    ts: stamp,
    text,
    user,
    bot_id: None,
    subtype,
    blocks: blocks.map(bs => @blocks.blocks_to_json(bs)),
    attachments,
    metadata: None,
    thread_ts,
    reply_count: 0,
    reply_users: [],
    latest_reply: None,
    reactions: [],
    edited: None,
  }
  target.messages.push(message)
  if thread_ts is Some(parent_ts) {
    self.note_reply(target, parent_ts, user, stamp)
  }
  stamp
}

///|
/// Record a reply against its parent: the counters `conversations.replies` and
/// every thread-aware client read.
fn Workspace::note_reply(
  self : Self,
  channel : Channel,
  parent_ts : String,
  user : String,
  reply_ts : String,
) -> Unit {
  ignore(self)
  for message in channel.messages {
    if message.ts == parent_ts {
      // Slack sets `thread_ts` on the PARENT too, once it has a reply. It is
      // how a client tells a thread root from an ordinary message.
      message.thread_ts = Some(parent_ts)
      message.reply_count += 1
      if !message.reply_users.contains(user) {
        message.reply_users.push(user)
      }
      message.latest_reply = Some(reply_ts)
      return
    }
  }
}

///|
/// Add a reaction to a message. A no-op if the message is not there.
pub fn Workspace::add_reaction(
  self : Self,
  channel~ : String,
  ts~ : String,
  user~ : String,
  name~ : String,
) -> Unit {
  guard self.message(channel, ts) is Some(message) else { return }
  for reaction in message.reactions {
    if reaction.name == name {
      if !reaction.users.contains(user) {
        reaction.users.push(user)
      }
      return
    }
  }
  message.reactions.push({ name, users: [user] })
}

///|
/// Pin a message. A no-op if the message is not there, or already pinned.
pub fn Workspace::pin(self : Self, channel~ : String, ts~ : String) -> Unit {
  guard self.channels.get(channel) is Some(target) else { return }
  guard self.message(channel, ts) is Some(_) else { return }
  if !target.pins.contains(ts) {
    target.pins.push(ts)
  }
}

///|
/// Add a bookmark to a channel. Returns the minted id.
pub fn Workspace::add_bookmark(
  self : Self,
  channel~ : String,
  title~ : String,
  link? : String = "",
  emoji? : String = "",
  type_? : String = "link",
) -> String {
  guard self.channels.get(channel) is Some(target) else { return "" }
  let id = self.next_bookmark_id()
  target.bookmarks.push({
    id,
    channel_id: channel,
    title,
    type_,
    link,
    emoji,
    date_created: self.now / 1000L,
  })
  id
}

///|
/// Add a user group. Returns the minted id.
pub fn Workspace::add_usergroup(
  self : Self,
  name~ : String,
  handle~ : String,
  description? : String = "",
  users? : Array[String] = [],
  channels? : Array[String] = [],
) -> String {
  let id = self.next_usergroup_id()
  let seconds = self.now / 1000L
  self.usergroups[id] = {
    id,
    team_id: self.team.id,
    name,
    handle,
    description,
    users: users.copy(),
    channels: channels.copy(),
    date_create: seconds,
    date_update: seconds,
    date_delete: 0L,
  }
  id
}

///|
/// Add a file. Returns the minted id.
pub fn Workspace::add_file(
  self : Self,
  name~ : String,
  user~ : String,
  title? : String,
  mimetype? : String = "text/plain",
  filetype? : String = "text",
  size? : Int = 0,
  channels? : Array[String] = [],
) -> String {
  let id = self.next_file_id()
  self.files[id] = {
    id,
    name,
    title: title.unwrap_or(name),
    mimetype,
    filetype,
    user,
    size,
    created: self.now / 1000L,
    channels: channels.copy(),
    deleted: false,
    upload_token: None,
  }
  id
}

///|
/// Put a user in a channel, both ways round. A no-op if either is unknown.
pub fn Workspace::join(self : Self, channel~ : String, user~ : String) -> Unit {
  guard self.channels.get(channel) is Some(target) else { return }
  if !target.members.contains(user) {
    target.members.push(user)
  }
}
