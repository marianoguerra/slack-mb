// The workspace, and everything in it.
//
// These are the mock's OWN types, not the library's. @client deliberately has
// no `User`/`Channel`/`Message` structs -- `ApiResponse.raw` is the escape
// hatch that keeps 326 methods reachable without 326 response types -- and
// adding them to the public API here would be a second, competing model of
// Slack. What lives in this file is a store, and `render.mbt` is the only thing
// that turns it into the JSON Slack would have sent.

///|
/// One in-memory Slack workspace.
///
/// Abstract on purpose: the type is public and its representation is not, so
/// every field below can change without breaking a consumer. That is the
/// opposite of `@api.Params`, which is `pub(all)` precisely so a caller can
/// build one -- here the state model is expected to grow, the accessors at the
/// bottom of this file are the supported way to read it, and the seeding API
/// in seed.mbt is the supported way to write it.
struct Workspace {
  team : Team
  /// Insertion-ordered, and iterated in that order by `users.list`. MoonBit's
  /// `Map` is a LinkedHashMap, which is what makes every listing response
  /// byte-stable across runs without a sort.
  users : Map[String, User]
  channels : Map[String, Channel]
  usergroups : Map[String, Usergroup]
  files : Map[String, FileRecord]
  views : Map[String, ViewRecord]
  scheduled : Map[String, ScheduledMessage]
  /// Keyed by the raw token string, which is what arrives in the header.
  tokens : Map[String, TokenRecord]
  ids : IdSeq
  /// Queued faults, per api method. `"*"` is the catch-all.
  faults : Map[String, Array[Fault]]
  /// Every request handled, in order: the assertion surface `FakeTransport.sent`
  /// gives, plus the decoded form and what came back.
  calls : Array[CallRecord]
  /// Epoch milliseconds. Never read from a clock -- see `ids.mbt`.
  mut now : Int64
  /// How far `now` moves per handled call.
  mut tick_millis : Int64
  /// Answer `unknown_method` for a real Slack method this mock has not
  /// modelled, the way Slack would, instead of saying so. Off by default.
  mut strict_unknown : Bool
  /// Parse `blocks` and refuse `invalid_blocks` when it does not.
  mut validate_blocks : Bool
  /// The ids `demo()` minted, by name. Empty for any other workspace.
  demo_ids_slot : Map[String, String]
}

///|
pub struct Team {
  id : String
  name : String
  domain : String
  email_domain : String
  enterprise_id : String?
}

///|
pub struct User {
  id : String
  team_id : String
  name : String
  mut real_name : String
  mut display_name : String
  mut email : String
  mut title : String
  mut phone : String
  mut status_text : String
  mut status_emoji : String
  tz : String
  tz_label : String
  tz_offset : Int
  is_bot : Bool
  bot_id : String?
  is_admin : Bool
  is_owner : Bool
  deleted : Bool
  /// `"active"` or `"away"`. A string rather than a Bool because that is what
  /// `users.setPresence` takes and `users.getPresence` returns.
  mut presence : String
  mut updated : Int64
  /// Profile fields this model does not name. The same escape hatch as
  /// `extra` on every Block Kit struct, for the same reason: a consumer who
  /// seeds a field we have never heard of should get it back.
  profile_extra : Map[String, Json]
}

///|
/// Which of the four things Slack calls a "conversation" this is.
///
/// One type rather than four, because that is how the API treats them:
/// `conversations.history` reads a DM as readily as a channel, and the `types`
/// filter on `conversations.list` is the only place the difference is named.
pub enum ChannelKind {
  Public
  Private
  Im
  Mpim
} derive(Eq, Debug)

///|
pub struct Channel {
  id : String
  mut name : String
  kind : ChannelKind
  created : Int64
  creator : String
  mut is_archived : Bool
  /// im/mpim only: `conversations.open` and `conversations.close`.
  mut is_open : Bool
  members : Array[String]
  mut topic : ChannelText
  mut purpose : ChannelText
  /// Oldest first, append-only. `conversations.history` reverses on the way
  /// out, because Slack answers newest first.
  messages : Array[Message]
  /// Message timestamps, in the order they were pinned.
  pins : Array[String]
  bookmarks : Array[Bookmark]
  previous_names : Array[String]
  mut last_read : String
}

///|
/// A channel topic or purpose. Slack models both the same way, down to the
/// `last_set` epoch and the id of whoever set it.
pub struct ChannelText {
  value : String
  creator : String
  last_set : Int64
}

///|
pub fn ChannelText::empty() -> ChannelText {
  { value: "", creator: "", last_set: 0L }
}

///|
pub struct Message {
  ts : String
  mut text : String
  user : String
  bot_id : String?
  subtype : String?
  /// Held as `Json`, not `Array[@blocks.LayoutBlock]`, and that is deliberate:
  /// what the caller sent comes back byte for byte. It is what makes the Block
  /// Kit round-trip check on mock output mean something -- a store that parsed
  /// and re-serialised would quietly normalise away the very fields the
  /// round-trip property exists to protect.
  mut blocks : Json?
  mut attachments : Json?
  mut metadata : Json?
  /// Set on a reply, and also on the parent once it has one -- which is what
  /// Slack does, and what makes a parent identifiable as a thread root.
  mut thread_ts : String?
  mut reply_count : Int
  reply_users : Array[String]
  mut latest_reply : String?
  /// Ordered by first add, as Slack orders them.
  reactions : Array[Reaction]
  /// `(user, ts)` of the edit, present only after `chat.update`.
  mut edited : (String, String)?
}

///|
pub struct Reaction {
  name : String
  users : Array[String]
}

///|
pub struct Bookmark {
  id : String
  channel_id : String
  title : String
  type_ : String
  link : String
  emoji : String
  date_created : Int64
}

///|
pub struct Usergroup {
  id : String
  team_id : String
  name : String
  handle : String
  description : String
  mut users : Array[String]
  channels : Array[String]
  date_create : Int64
  mut date_update : Int64
  date_delete : Int64
}

///|
pub struct FileRecord {
  id : String
  name : String
  mut title : String
  mimetype : String
  filetype : String
  user : String
  size : Int
  created : Int64
  channels : Array[String]
  mut deleted : Bool
  /// Set by `files.getUploadURLExternal`, cleared by
  /// `files.completeUploadExternal`. A file with one is not yet real.
  mut upload_token : String?
}

///|
pub enum ViewKind {
  Modal
  Home
} derive(Eq, Debug)

///|
pub struct ViewRecord {
  id : String
  kind : ViewKind
  mut payload : Json
  mut hash : String
  external_id : String?
  root_view_id : String
  previous_view_id : String?
  /// The user a `views.publish` home tab belongs to.
  user_id : String?
}

///|
pub struct ScheduledMessage {
  id : String
  channel : String
  text : String
  post_at : Int64
  date_created : Int64
  blocks : Json?
  thread_ts : String?
}

///|
/// One handled request, for a test to assert on afterwards.
pub struct CallRecord {
  api_method : String
  /// The decoded form body. What actually went on the wire, not what the
  /// caller passed -- which is the difference that catches an encoder bug.
  form : Array[(String, String)]
  status : Int
  ok : Bool
  error : String?
}

///|
/// Every request handled, in order.
pub fn Workspace::calls(self : Self) -> Array[CallRecord] {
  self.calls
}

///|
pub fn Workspace::call_count(self : Self) -> Int {
  self.calls.length()
}

///|
/// Every call to one method, in order. Saves each test the same filter.
pub fn Workspace::calls_to(
  self : Self,
  api_method : String,
) -> Array[CallRecord] {
  self.calls.filter(c => c.api_method == api_method)
}

///|
pub fn Workspace::last_call(self : Self) -> CallRecord? {
  if self.calls.is_empty() {
    None
  } else {
    Some(self.calls[self.calls.length() - 1])
  }
}

///|
/// The value of one field of the nth call's form body.
pub fn CallRecord::field(self : Self, name : String) -> String? {
  for entry in self.form {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}

///|
pub fn Workspace::team(self : Self) -> Team {
  self.team
}

///|
/// Look a user up by id. `None` rather than a raise: a test asking whether a
/// user exists is a normal thing to want.
pub fn Workspace::user(self : Self, id : String) -> User? {
  self.users.get(id)
}

///|
pub fn Workspace::channel(self : Self, id : String) -> Channel? {
  self.channels.get(id)
}

///|
/// Every message in a channel, oldest first. Empty for an unknown channel.
pub fn Workspace::messages(self : Self, channel_id : String) -> Array[Message] {
  match self.channels.get(channel_id) {
    Some(c) => c.messages
    None => []
  }
}

///|
/// One message by channel and timestamp.
pub fn Workspace::message(
  self : Self,
  channel_id : String,
  ts : String,
) -> Message? {
  for message in self.messages(channel_id) {
    if message.ts == ts {
      return Some(message)
    }
  }
  None
}
