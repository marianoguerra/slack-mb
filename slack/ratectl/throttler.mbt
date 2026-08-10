///|
/// One bucket per rate-limit scope, so a burst of `conversations.list` does not
/// slow down `chat.postMessage`.
///
/// The scope is the interesting part. Slack's limits are mostly per method per
/// workspace, but `chat.postMessage` is per *channel* and
/// `assistant.threads.setStatus` is per *DM* -- so a single bucket keyed on the
/// method name alone would throttle a bot posting to fifty channels as if it
/// were posting fifty times to one. `throttling_key` encodes that; it is the
/// same key shape java-slack-sdk uses for its metrics datastore.
pub struct Throttler {
  buckets : Map[String, ThrottlingCounter]
  /// Prefixed onto every key, so two workspaces served by one process do not
  /// share a bucket. Empty for a single-workspace app.
  team_id : String
}

///|
pub fn Throttler::new(team_id? : String = "") -> Throttler {
  { buckets: Map([]), team_id }
}

///|
/// The bucket key for a call.
///
/// `scope` is the channel id for `chat.postMessage` and the DM id for
/// `assistant.threads.setStatus`; for every other method it is ignored, because
/// their limits are per workspace and keying them per channel would let a bot
/// exceed the workspace limit by spreading calls across channels.
pub fn Throttler::throttling_key(
  self : Self,
  method_name : String,
  scope? : String,
) -> String {
  let per_scope = match @methods.tier_of(method_name) {
    Some(SpecialChatPostMessage) => true
    Some(SpecialAssistantThreadsSetStatus) => true
    _ => false
  }
  let suffix = if per_scope && scope is Some(s) { "_" + s } else { "" }
  self.team_id + "|" + method_name + suffix
}

///|
/// Account for one call and return how long to wait before sending it, in
/// milliseconds. Zero means send now.
///
/// This mutates the throttler -- the call is assumed to happen. A caller who
/// asks and then does not send has told the bucket a lie, and the bucket will
/// pace them slightly more conservatively than necessary. That is the right
/// direction to be wrong in.
pub fn Throttler::acquire(
  self : Self,
  method_name : String,
  now : Int64,
  scope? : String,
) -> Int64 {
  let key = self.throttling_key(method_name, scope?)
  let counter = match self.buckets.get(key) {
    Some(c) => c
    None => Limit::of_method(method_name).counter(now)
  }
  let updated = counter.update(now)
  self.buckets[key] = updated
  updated.delay_millis
}

///|
/// Record a `Retry-After` Slack sent, so the next `acquire` for the same scope
/// respects it.
pub fn Throttler::note_retry_after(
  self : Self,
  method_name : String,
  seconds : Int,
  now : Int64,
  scope? : String,
) -> Unit {
  let key = self.throttling_key(method_name, scope?)
  let counter = match self.buckets.get(key) {
    Some(c) => c
    None => Limit::of_method(method_name).counter(now)
  }
  self.buckets[key] = counter.with_retry_after(seconds)
}

///|
/// The delay currently recorded for a scope, without accounting for a call.
pub fn Throttler::delay_millis(
  self : Self,
  method_name : String,
  scope? : String,
) -> Int64 {
  match self.buckets.get(self.throttling_key(method_name, scope?)) {
    Some(c) => c.delay_millis
    None => 0L
  }
}
