// The few questions worth asking that a field cannot answer.
//
// Deliberately short. Every field on these structs is public, so an accessor
// has to earn its place by collapsing an option chain a caller would otherwise
// get subtly wrong -- which name Slack's own clients show, which timestamp
// identifies a thread. Anything that is just `self.field` is not here.

///|
/// The name to show for a user.
///
/// `display_name`, then `real_name`, then `name`, then the id. That is the
/// order Slack's own clients fall back in, and the reason a bot that shows
/// `user.name` looks wrong: `name` is the handle, which for many workspaces has
/// not been the thing anyone recognises since Slack made display names
/// editable. An empty string counts as absent, because Slack sends `""` rather
/// than omitting the field when a user has not set one.
pub fn User::display(self : User) -> String {
  for candidate in [self.display_name(), self.real_name, self.name] {
    if candidate is Some(name) && name != "" {
      return name
    }
  }
  self.id
}

///|
/// The user's `display_name`, which lives on the profile rather than the user.
fn User::display_name(self : User) -> String? {
  match self.profile {
    Some(profile) => profile.display_name
    None => None
  }
}

///|
/// The name to show for a conversation, falling back to its id.
///
/// A DM has no `name` at all, so the id is not a defensive fallback here -- it
/// is the answer for every `is_im` conversation Slack returns.
pub fn Channel::display(self : Channel) -> String {
  if self.name is Some(name) && name != "" {
    name
  } else {
    self.id
  }
}

///|
/// A topic or purpose's text, which is absent and empty often enough that
/// unwrapping it at every call site is noise.
pub fn ChannelText::text(self : ChannelText) -> String {
  self.value.unwrap_or("")
}

///|
/// The `ts` that identifies the thread a message belongs to.
///
/// `thread_ts` on a reply, `ts` on anything else -- including the message that
/// STARTED the thread, which carries both and whose two values are equal. Using
/// `thread_ts` alone loses every message that is not in a thread; using `ts`
/// alone scatters a thread across its replies.
pub fn Message::thread_root(self : Message) -> String? {
  match self.thread_ts {
    Some(ts) => Some(ts)
    None => self.ts
  }
}

///|
/// Whether this message is a reply inside a thread, as opposed to the parent
/// that started one.
///
/// The parent carries `thread_ts == ts`, so testing for `thread_ts` alone
/// counts it as its own reply.
pub fn Message::is_thread_reply(self : Message) -> Bool {
  match (self.thread_ts, self.ts) {
    (Some(thread), Some(ts)) => thread != ts
    (Some(_), None) => true
    _ => false
  }
}
