// Ported from slack-morphism's `throttling_counter.rs` tests.
//
// Upstream's tests use `Instant::now()` plus arithmetic, which works only
// because the counter is persistent and never reads the clock itself. Here
// `now` is an ordinary `Int64` argument, so the tests do not even need a fake
// clock -- they just pass numbers.

///|
/// slack-morphism's fixture: 15 requests per 60 seconds, which is
/// `rate_limit_in_millis = 4000` and `capacity = 15`.
fn limit() -> @ratectl.Limit {
  @ratectl.Limit::new(15, 60_000L)
}

///|
test "the limit's derived spacing and capacity" {
  assert_eq(limit().rate_limit_in_millis(), 4000L)
  assert_eq(limit().capacity(), 15)
}

///|
/// slack-morphism `check_decreased`: a request that arrives before a token has
/// refilled spends capacity but is not delayed -- that is the burst allowance.
test "a request inside the window spends capacity without waiting" {
  let now = 1_000_000L
  let counter = limit().counter(now)
  let updated = counter.update(now + counter.rate_limit_in_millis - 1L)
  assert_eq(updated.last_arrived, counter.last_arrived)
  assert_eq(updated.delay_millis, 0L)
  assert_eq(updated.capacity, counter.capacity - 1L)
}

///|
/// slack-morphism `check_max_available`: a token refills, but the bucket was
/// already full, so the refill is capped rather than accumulating -- which is
/// what stops an idle client from banking an unlimited burst.
test "capacity is capped at the maximum, however long the client idled" {
  let now = 1_000_000L
  let counter = limit().counter(now)
  let updated = counter.update(now + counter.rate_limit_in_millis + 1L)
  assert_eq(updated.delay_millis, 0L)
  assert_eq(updated.capacity, (counter.max_capacity - 1).to_int64())

  // An hour of idling credits no more than one bucketful.
  let after_idle = counter.update(now + 3_600_000L)
  assert_eq(after_idle.capacity, (counter.max_capacity - 1).to_int64())
  assert_eq(after_idle.delay_millis, 0L)
}

///|
/// slack-morphism `check_delay`: exhaust the bucket at a single instant, and the
/// request past the end waits exactly one spacing interval.
test "the request past the bucket waits one interval" {
  let now = 1_000_000L
  let start = limit().counter(now)
  let mut counter = start
  for _ in 0..<(start.capacity.to_int() + 1) {
    counter = counter.update(now)
  }
  assert_eq(counter.delay_millis, start.rate_limit_in_millis)
}

///|
/// Capacity going negative is the design, not a bug: it measures how far behind
/// schedule the caller is, and that depth is what grows the penalty. A caller
/// who ignores the delay and keeps calling backs off further each time instead
/// of settling into a tight retry loop.
test "the penalty grows the deeper the caller digs" {
  let now = 1_000_000L
  let mut counter = limit().counter(now)
  // Drain the bucket exactly.
  for _ in 0..<15 {
    counter = counter.update(now)
  }
  assert_eq(counter.capacity, 0L)
  assert_eq(counter.delay_millis, 0L)
  let mut previous = 0L
  for i in 0..<5 {
    counter = counter.update(now)
    assert_eq(counter.capacity, (-1 - i).to_int64())
    assert_true(
      counter.delay_millis >= previous,
      msg="delay should not shrink while over budget (step \{i})",
    )
    previous = counter.delay_millis
  }
  // Five requests past the end of a 15-deep bucket: one full interval plus a
  // penalty of 4/15 of an interval.
  assert_eq(counter.delay_millis, 4000L + 4000L * 4L / 15L)
}

///|
/// Time the caller already spent waiting counts against the delay it is told to
/// wait, so a client that paced itself is not made to wait twice.
test "time already elapsed is credited against the delay" {
  let now = 1_000_000L
  let mut counter = limit().counter(now)
  for _ in 0..<16 {
    counter = counter.update(now)
  }
  assert_eq(counter.delay_millis, 4000L)
  // Ask again 1000ms later: one interval minus the 1000ms already waited, plus
  // the penalty for being one request into the hole.
  let later = counter.update(now + 1000L)
  assert_eq(later.delay_millis, 4000L - 1000L + 4000L * 1L / 15L)
}

///|
/// A clock that jumps backwards -- NTP correction, a suspended laptop -- must
/// not produce a negative elapsed time and credit the bucket for it.
test "a backwards clock does not credit capacity" {
  let now = 1_000_000L
  let counter = limit().counter(now)
  let updated = counter.update(now - 60_000L)
  assert_eq(updated.capacity, counter.capacity - 1L)
  assert_eq(updated.delay_millis, 0L)
}

///|
/// `Retry-After` is the server saying how long it will keep refusing, which is
/// authoritative in a way the local bucket is not -- the tiers are documented
/// floors, so Slack is allowed to be stricter than the arithmetic here.
test "Retry-After wins when it is longer than the computed delay" {
  let now = 1_000_000L
  let counter = limit().counter(now)
  assert_eq(counter.with_retry_after(30).delay_millis, 30_000L)
  // ...and does not shorten a delay the bucket already computed.
  let mut drained = limit().counter(now)
  for _ in 0..<16 {
    drained = drained.update(now)
  }
  assert_eq(drained.delay_millis, 4000L)
  assert_eq(drained.with_retry_after(1).delay_millis, 4000L)
  assert_eq(drained.with_retry_after(10).delay_millis, 10_000L)
}

///|
/// The tier table and the bucket arithmetic have to agree, or throttling would
/// pace a method to a limit Slack never documented.
test "every tier produces a usable limit" {
  for tier in @methods.all_tiers {
    let l = @ratectl.Limit::of_tier(tier)
    assert_eq(l.value, tier.allowed_requests_per_minute())
    assert_eq(l.per_millis, 60_000L)
    assert_true(l.rate_limit_in_millis() > 0L, msg=tier.to_metadata_name())
    assert_true(l.capacity() > 0, msg=tier.to_metadata_name())
  }
  // Tier1 is one request per minute: a whole minute of spacing, capacity 1.
  let tier1 = @ratectl.Limit::of_tier(Tier1)
  assert_eq(tier1.rate_limit_in_millis(), 60_000L)
  assert_eq(tier1.capacity(), 1)
  // Tier4 is 100/minute: 600ms apart, capacity 100.
  let tier4 = @ratectl.Limit::of_tier(Tier4)
  assert_eq(tier4.rate_limit_in_millis(), 600L)
  assert_eq(tier4.capacity(), 100)
}

///|
/// An unknown method is paced as Tier2 rather than left unthrottled, matching
/// java-slack-sdk.
test "an unknown method is paced as Tier2" {
  assert_eq(
    @ratectl.Limit::of_method("chat.notARealMethod"),
    @ratectl.Limit::of_tier(Tier2),
  )
  assert_eq(
    @ratectl.Limit::of_method(@methods.conversations_history),
    @ratectl.Limit::of_tier(Tier3),
  )
}
