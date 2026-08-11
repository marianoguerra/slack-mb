// The chat.* family: everything that writes a message.

///|
/// Validate a `blocks` payload, if validation is on.
///
/// THIS IS THE MOST INVENTED BEHAVIOUR IN THIS PACKAGE, and it is worth being
/// plain about. Slack really does refuse a malformed Block Kit payload with
/// `invalid_blocks` and really does put a `[ERROR] ... [json-pointer:/...]`
/// line in `response_metadata.messages` -- `ResponseMetadata::diagnostics`
/// exists to read exactly that, and the format is copied from responses
/// recorded in the wild. But the mapping from "which block failed" to "what
/// Slack would have said about it" is a reconstruction: no fixture in this
/// repository records the message for a given bad payload, and Slack's
/// validator knows about fields this library has never heard of.
///
/// So: what is trustworthy here is that a payload @blocks cannot parse is
/// refused, with the right error code and a diagnostic in the right shape.
/// What is NOT trustworthy is the exact wording, or the belief that anything
/// @blocks accepts Slack would accept too. `set_validate_blocks(false)` turns
/// the whole thing off.
fn Workspace::check_blocks(self : Self, blocks : Json?) -> Unit raise Refusal {
  guard self.validate_blocks else { return }
  guard blocks is Some(payload) else { return }
  // Strict, not lenient: the point is to refuse what Slack would refuse, and
  // `Lenient` exists so that a CLIENT can read a block type it does not know.
  // A server has no such excuse.
  //
  // `describe_error` is java-slack-sdk's own wording, which is the closest
  // thing to a source this message has.
  let parsed = @blocks.parse_blocks(payload, policy=Strict) catch {
    e => raise invalid_blocks(e.describe_error())
  }
  // `None` means the payload was not an array at all.
  guard parsed is Some(blocks) else {
    raise invalid_blocks("blocks must be an array")
  }
  // Parsing says the shapes are known; validating says they are legal -- a
  // button with no text parses and is still refused.
  @blocks.validate_blocks(blocks) catch {
    e => raise invalid_blocks(e.describe_error())
  }
}

///|
/// An `invalid_blocks` refusal, with a diagnostic in the shape Slack sends.
///
/// The `[ERROR] ... [json-pointer:...]` format is real -- it is what
/// `ResponseMetadata::diagnostics` parses, and the envelope tests carry
/// recorded examples of it. The pointer is `/blocks` rather than
/// `/blocks/0/type`, because @blocks does not report WHICH block failed and
/// inventing an index would be a lie a caller might act on.
fn invalid_blocks(why : String) -> Refusal {
  refuse_with_messages("invalid_blocks", [
    "[ERROR] \{why} [json-pointer:/blocks]",
  ])
}

///|
/// Read the message-shaped arguments every posting method shares.
fn Workspace::message_payload(
  self : Self,
  form : Form,
) -> (Json?, Json?, Json?) raise Refusal {
  let blocks = form.json("blocks")
  self.check_blocks(blocks)
  (blocks, form.json("attachments"), form.json("metadata"))
}

///|
/// `chat.postMessage`.
///
/// One of the three methods that accept a channel NAME as well as an id. See
/// `resolve_channel` for why that asymmetry is reproduced rather than smoothed
/// over.
fn Workspace::chat_post_message(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let channel = self.channel_arg(form, allow_name=true)
  if channel.is_archived {
    raise refuse("is_archived")
  }
  let (blocks, attachments, metadata) = self.message_payload(form)
  let text = form.get("text").unwrap_or("")
  // Slack wants SOMETHING to show. A message with neither text nor blocks nor
  // attachments is `no_text`, which is a common surprise for a caller who
  // built blocks and forgot the fallback.
  guard !text.is_empty() || blocks is Some(_) || attachments is Some(_) else {
    raise refuse("no_text")
  }
  let thread_ts = self.resolve_thread(channel, form)
  let ts = self.next_ts()
  let message : Message = {
    ts,
    text,
    user: auth.user_id,
    bot_id: auth.bot_id,
    subtype: None,
    blocks,
    attachments,
    metadata,
    thread_ts,
    reply_count: 0,
    reply_users: [],
    latest_reply: None,
    reactions: [],
    edited: None,
  }
  channel.messages.push(message)
  if thread_ts is Some(parent) {
    self.note_reply(channel, parent, auth.user_id, ts)
  }
  {
    // The RESOLVED id, not whatever the caller passed. This is what makes
    // posting by `#name` and then updating by id work at all, and it is what
    // ext/cmd/integration threads through the rest of its run.
    "channel": Json::string(channel.id),
    "ts": Json::string(ts),
    "message": message.to_json(),
  }
}

///|
/// The thread a message belongs to, checking that it exists.
fn Workspace::resolve_thread(
  self : Self,
  channel : Channel,
  form : Form,
) -> String? raise Refusal {
  ignore(self)
  guard form.get("thread_ts") is Some(parent) && !parent.is_empty() else {
    return None
  }
  for message in channel.messages {
    if message.ts == parent {
      return Some(parent)
    }
  }
  raise refuse("thread_not_found")
}

///|
/// `chat.postEphemeral`.
///
/// Nothing is stored: an ephemeral message exists only in one person's client
/// and is not in the channel's history, which is exactly why it answers with
/// `message_ts` and NOT with `ts` or `message`. A caller that tried to update
/// or delete one would find nothing, against Slack as well as here.
fn Workspace::chat_post_ephemeral(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form, allow_name=true)
  let user = form.require_as("user", "user_not_found")
  guard self.users.get(user) is Some(_) else { raise refuse("user_not_found") }
  guard channel.members.contains(user) else {
    raise refuse("user_not_in_channel")
  }
  let (blocks, _, _) = self.message_payload(form)
  guard form.has("text") || blocks is Some(_) else { raise refuse("no_text") }
  { "message_ts": Json::string(self.next_ts()) }
}

///|
/// `chat.update`.
///
/// Two rules worth their own lines, both of them the decode side of what
/// `slack/client/chat.mbt` documents on the encode side:
///
/// An ABSENT `blocks` field keeps the message's existing blocks; an EMPTY one
/// (`[]`) clears them. That is why `Params::put_json` sends `[]` rather than
/// omitting the field, and why `ext/test/calls` has a test asserting the empty
/// array reaches the wire.
///
/// And the channel is resolved by id only. `chat.postMessage` takes a `#name`
/// and this does not -- see `resolve_channel`.
fn Workspace::chat_update(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let channel = self.channel_arg(form)
  let ts = form.require_as("ts", "message_not_found")
  guard self.find_message(channel, ts) is Some(message) else {
    raise refuse("message_not_found")
  }
  let blocks = form.json("blocks")
  self.check_blocks(blocks)
  if blocks is Some(_) {
    message.blocks = blocks
  }
  if form.json("attachments") is Some(attachments) {
    message.attachments = Some(attachments)
  }
  if form.json("metadata") is Some(metadata) {
    message.metadata = Some(metadata)
  }
  if form.get("text") is Some(text) {
    message.text = text
  }
  message.edited = Some((auth.user_id, self.next_ts()))
  {
    "channel": Json::string(channel.id),
    "ts": Json::string(message.ts),
    "text": Json::string(message.text),
    "message": message.to_json(),
  }
}

///|
fn Workspace::find_message(
  self : Self,
  channel : Channel,
  ts : String,
) -> Message? {
  ignore(self)
  for message in channel.messages {
    if message.ts == ts {
      return Some(message)
    }
  }
  None
}

///|
/// `chat.delete`. By id only, like `chat.update`.
fn Workspace::chat_delete(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let ts = form.require_as("ts", "message_not_found")
  for i in 0..<channel.messages.length() {
    if channel.messages[i].ts == ts {
      channel.messages.remove(i) |> ignore
      remove_string(channel.pins, ts)
      return { "channel": Json::string(channel.id), "ts": Json::string(ts) }
    }
  }
  raise refuse("message_not_found")
}

///|
/// `chat.meMessage`: a `/me` line. Stored with Slack's `me_message` subtype,
/// so it comes back out of history distinguishable from an ordinary post.
fn Workspace::chat_me_message(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let channel = self.channel_arg(form, allow_name=true)
  let text = form.require_as("text", "no_text")
  let ts = self.next_ts()
  channel.messages.push({
    ts,
    text,
    user: auth.user_id,
    bot_id: auth.bot_id,
    subtype: Some("me_message"),
    blocks: None,
    attachments: None,
    metadata: None,
    thread_ts: None,
    reply_count: 0,
    reply_users: [],
    latest_reply: None,
    reactions: [],
    edited: None,
  })
  { "channel": Json::string(channel.id), "ts": Json::string(ts) }
}

///|
/// `chat.scheduleMessage`.
///
/// The message is NOT posted -- it is held, and nothing here ever posts it,
/// because that would need a clock this package deliberately does not have.
/// `chat.scheduledMessages.list` is how a test sees it, and
/// `advance` plus a manual post is how a test that needs it delivered gets
/// there. A divergence, and the honest one: a mock that fired timers would be
/// a scheduler.
fn Workspace::chat_schedule_message(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form, allow_name=true)
  let post_at = match form.i64("post_at") {
    Some(t) => t
    None => raise refuse("invalid_time")
  }
  // Slack refuses a time in the past, and refuses one more than 120 days out.
  // The first is the one a test hits by accident, having written a literal.
  guard post_at * 1000L > self.now else { raise refuse("time_in_past") }
  let (blocks, _, _) = self.message_payload(form)
  let id = self.next_scheduled_id()
  self.scheduled[id] = {
    id,
    channel: channel.id,
    text: form.get("text").unwrap_or(""),
    post_at,
    date_created: self.now / 1000L,
    blocks,
    thread_ts: form.get("thread_ts"),
  }
  let message : Map[String, Json] = Map([])
  message["type"] = Json::string("message")
  message["user"] = Json::string(auth.user_id)
  if auth.bot_id is Some(bot_id) {
    message["bot_id"] = Json::string(bot_id)
  }
  message["text"] = Json::string(form.get("text").unwrap_or(""))
  if blocks is Some(b) {
    message["blocks"] = b
  }
  {
    "scheduled_message_id": Json::string(id),
    "channel": Json::string(channel.id),
    "post_at": Json::number(post_at.to_double(), repr=post_at.to_string()),
    "message": Json::object(message),
  }
}

///|
/// `chat.deleteScheduledMessage`.
fn Workspace::chat_delete_scheduled_message(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let id = form.require_as(
    "scheduled_message_id", "invalid_scheduled_message_id",
  )
  guard self.scheduled.get(id) is Some(_) else {
    raise refuse("invalid_scheduled_message_id")
  }
  self.scheduled.remove(id)
  Map([])
}

///|
/// `chat.scheduledMessages.list`.
fn Workspace::chat_scheduled_messages_list(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  ignore(auth)
  let wanted = form.get("channel")
  let out : Array[Json] = []
  for _, scheduled in self.scheduled {
    if wanted is Some(id) && !id.is_empty() && scheduled.channel != id {
      continue
    }
    out.push(scheduled.to_json())
  }
  let (page, next_cursor) = page_of(out, form)
  {
    "scheduled_messages": Json::array(page),
    "response_metadata": Json::object({
      "next_cursor": Json::string(next_cursor),
    }),
  }
}

///|
/// `chat.getPermalink`.
///
/// The one implemented method whose documented scope is literally "none". The
/// URL shape is Slack's: `/archives/<channel>/p<ts with the dot removed>`.
fn Workspace::chat_get_permalink(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let ts = form.require_as("message_ts", "message_not_found")
  guard self.find_message(channel, ts) is Some(_) else {
    raise refuse("message_not_found")
  }
  let compact = ts.split(".").map(part => part.to_owned()).collect().join("")
  {
    "channel": Json::string(channel.id),
    "permalink": Json::string(
      "https://\{self.team.domain}.slack.com/archives/\{channel.id}/p\{compact}",
    ),
  }
}

///|
/// `chat.unfurl`.
///
/// Accepted and discarded. Unfurling attaches a preview to a link inside a
/// message that Slack has already decided to ask about, and there is no link
/// unfurling in this mock to attach it to -- so what a test can check here is
/// that the call was made, with what, and that the arguments were well formed.
/// `calls_to("chat.unfurl")` is the assertion surface.
fn Workspace::chat_unfurl(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let channel = self.channel_arg(form)
  let ts = form.require_as("ts", "message_not_found")
  guard self.find_message(channel, ts) is Some(_) else {
    raise refuse("message_not_found")
  }
  guard form.json("unfurls") is Some(Object(_)) else {
    raise refuse("invalid_arguments")
  }
  Map([])
}
