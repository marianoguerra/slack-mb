// Client-side throttling.
//
// Ported from slack-morphism's `ratectl` module. The point of throttling on the
// client is that a 429 is not free: it costs a round trip, it counts against
// you, and Slack's `Retry-After` is a floor rather than a schedule. Pacing
// requests to the documented tier means most apps never see one.
//
// Nothing here reads a clock. Every entry point takes `now` as an epoch
// milliseconds argument, which is what makes slack-morphism's three counter
// tests deterministic -- and what lets this package build on wasm, where there
// is no wall clock to read.

///|
/// A rate limit: `value` requests per `per_millis` milliseconds.
pub(all) struct Limit {
  value : Int
  per_millis : Int64
} derive(Eq, Debug)

///|
/// Both arguments must be positive; slack-morphism asserts the same, and a zero
/// here would make the bucket arithmetic divide by zero rather than merely
/// misbehave.
pub fn Limit::new(value : Int, per_millis : Int64) -> Limit {
  guard value > 0 else { abort("rate limit value must be positive") }
  guard per_millis > 0L else { abort("rate limit window must be positive") }
  { value, per_millis }
}

///|
/// The minimum spacing between two requests, in milliseconds.
pub fn Limit::rate_limit_in_millis(self : Self) -> Int64 {
  self.per_millis / self.value.to_int64()
}

///|
/// How many requests may burst before pacing kicks in.
///
/// `per / spacing`, which is `value` again whenever the division is exact --
/// and slack-morphism computes it this way rather than reusing `value` because
/// integer truncation in `rate_limit_in_millis` means the two can differ.
pub fn Limit::capacity(self : Self) -> Int {
  (self.per_millis / self.rate_limit_in_millis()).to_int()
}

///|
/// The limit Slack documents for a tier.
pub fn Limit::of_tier(tier : @methods.RateLimitTier) -> Limit {
  Limit::new(tier.allowed_requests_per_minute(), 60_000L)
}

///|
/// The limit for a method, falling back to Tier2 for anything Slack's metadata
/// does not list -- the same fallback java-slack-sdk uses.
pub fn Limit::of_method(method_name : String) -> Limit {
  Limit::new(@methods.allowed_requests_per_minute(method_name), 60_000L)
}

///|
pub fn Limit::counter(self : Self, now : Int64) -> ThrottlingCounter {
  ThrottlingCounter::new(self.capacity(), self.rate_limit_in_millis(), now)
}
