// Slack's rate-limit tiers.
//
// https://docs.slack.dev/apis/web-api/rate-limits
//
// Every method belongs to a tier, and the tier is the only public statement
// Slack makes about how fast you may call it. The mapping is data, not
// knowledge: it lives in ext/metadata/rate_limit_tiers.json and is compiled
// into generated_methods.mbt by ext/tools/gen_methods. This file holds only the
// part that is a judgement -- what each tier means in requests per minute.

///|
pub(all) enum RateLimitTier {
  /// 1+ per minute. "Access tier 1 methods infrequently."
  Tier1
  /// 20+ per minute. The default, and by far the most common.
  Tier2
  /// 50+ per minute. Usually the paginating collection methods.
  Tier3
  /// 100+ per minute.
  Tier4
  /// `auth.test`: hundreds per minute.
  SpecialAuthTest
  /// `chat.getPermalink`: hundreds per minute.
  SpecialChatGetPermalink
  /// `chat.postMessage`: roughly one message per second **per channel**, with
  /// a separate workspace-wide ceiling above that. The per-channel part is why
  /// a throttling key for this method has to include the channel id.
  SpecialChatPostMessage
  /// `assistant.threads.setStatus`: like `chat.postMessage`, but per DM.
  SpecialAssistantThreadsSetStatus
} derive(Eq, Hash, Debug)

///|
/// The tier's documented floor, in requests per minute.
///
/// A floor, not a quota: Slack says "20+" and tolerates bursts. Treating it as
/// a hard ceiling is the conservative reading and the one @ratectl uses.
pub fn RateLimitTier::allowed_requests_per_minute(self : Self) -> Int {
  match self {
    Tier1 => 1
    Tier2 => 20
    Tier3 => 50
    Tier4 => 100
    SpecialAuthTest => 600
    SpecialChatGetPermalink => 600
    SpecialChatPostMessage => 60
    SpecialAssistantThreadsSetStatus => 60
  }
}

///|
/// The name this tier has in Slack's own metadata, which is the spelling
/// java-slack-sdk's enum uses and the one in `rate_limit_tiers.json`.
pub fn RateLimitTier::to_metadata_name(self : Self) -> String {
  match self {
    Tier1 => "Tier1"
    Tier2 => "Tier2"
    Tier3 => "Tier3"
    Tier4 => "Tier4"
    SpecialAuthTest => "SpecialTier_auth_test"
    SpecialChatGetPermalink => "SpecialTier_chat_getPermalink"
    SpecialChatPostMessage => "SpecialTier_chat_postMessage"
    SpecialAssistantThreadsSetStatus =>
      "SpecialTier_assistant_threads_setStatus"
  }
}

///|
pub fn RateLimitTier::parse(name : String) -> RateLimitTier? {
  match name {
    "Tier1" => Some(Tier1)
    "Tier2" => Some(Tier2)
    "Tier3" => Some(Tier3)
    "Tier4" => Some(Tier4)
    "SpecialTier_auth_test" => Some(SpecialAuthTest)
    "SpecialTier_chat_getPermalink" => Some(SpecialChatGetPermalink)
    "SpecialTier_chat_postMessage" => Some(SpecialChatPostMessage)
    "SpecialTier_assistant_threads_setStatus" =>
      Some(SpecialAssistantThreadsSetStatus)
    _ => None
  }
}

///|
/// Every tier, for tests and for anyone enumerating them.
pub let all_tiers : Array[RateLimitTier] = [
  Tier1,
  Tier2,
  Tier3,
  Tier4,
  SpecialAuthTest,
  SpecialChatGetPermalink,
  SpecialChatPostMessage,
  SpecialAssistantThreadsSetStatus,
]

///|
/// The tier for a method, or `None` if Slack's metadata does not list it.
pub fn tier_of(method_name : String) -> RateLimitTier? {
  method_tiers.get(method_name)
}

///|
/// The rate limit for a method, defaulting to Tier2 for anything unknown.
///
/// java-slack-sdk does the same: an unrecognised method is throttled as Tier2
/// rather than crashing or being left unthrottled. Tier2 is not necessarily
/// right -- but a wrong number is recoverable and no number is not.
pub fn allowed_requests_per_minute(method_name : String) -> Int {
  match tier_of(method_name) {
    Some(t) => t.allowed_requests_per_minute()
    None => RateLimitTier::Tier2.allowed_requests_per_minute()
  }
}

///|
/// Whether Slack's metadata knows this method at all. Useful for validating a
/// name before it reaches the network.
pub fn is_known(method_name : String) -> Bool {
  method_tiers.contains(method_name)
}
