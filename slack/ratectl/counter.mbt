///|
/// A leaky bucket, ported from slack-morphism's `ThrottlingCounter`.
///
/// Persistent rather than mutable: `update` returns the next counter instead of
/// changing this one. That is what makes the arithmetic testable -- the three
/// tests below are slack-morphism's, and they work only because the counter and
/// the clock are both values.
///
/// `capacity` is deliberately allowed to go negative. It is not "tokens left",
/// it is how far ahead or behind schedule the caller is, and the depth of the
/// hole is what sizes the penalty in `delay_millis`.
pub(all) struct ThrottlingCounter {
  capacity : Int64
  max_capacity : Int
  /// When the most recent token notionally arrived. Advances in whole
  /// `rate_limit_in_millis` steps, not to `now`, so fractional time is carried
  /// forward rather than discarded.
  last_arrived : Int64
  /// When `update` last ran. Only used to measure how long the caller already
  /// waited on its own.
  last_updated : Int64
  rate_limit_in_millis : Int64
  /// How long to wait before sending, in milliseconds. Zero when there was
  /// capacity.
  delay_millis : Int64
} derive(Eq, Debug)

///|
/// A full bucket as of `now` (epoch milliseconds).
pub fn ThrottlingCounter::new(
  max_capacity : Int,
  rate_limit_in_millis : Int64,
  now : Int64,
) -> ThrottlingCounter {
  {
    capacity: max_capacity.to_int64(),
    max_capacity,
    last_arrived: now,
    last_updated: now,
    rate_limit_in_millis,
    delay_millis: 0L,
  }
}

///|
/// Account for one request at `now`, and return the counter that results.
///
/// Read `delay_millis` on the result: zero means send immediately, anything
/// else is how long to wait first.
pub fn ThrottlingCounter::update(self : Self, now : Int64) -> ThrottlingCounter {
  let elapsed = if now > self.last_arrived {
    now - self.last_arrived
  } else {
    0L
  }
  // Tokens are only credited in whole steps, and `last_arrived` moves by
  // exactly those steps. Advancing it to `now` instead would silently discard
  // the remainder and make the bucket refill slower than the limit allows.
  let (arrived, new_last_arrived) = if elapsed >= self.rate_limit_in_millis {
    let n = elapsed / self.rate_limit_in_millis
    (n, self.last_arrived + n * self.rate_limit_in_millis)
  } else {
    (0L, self.last_arrived)
  }
  let refilled = {
    let c = self.capacity + arrived
    if c > self.max_capacity.to_int64() {
      self.max_capacity.to_int64()
    } else {
      c
    }
  }
  if refilled > 0L {
    {
      ..self,
      capacity: refilled - 1L,
      last_arrived: new_last_arrived,
      last_updated: now,
      delay_millis: 0L,
    }
  } else {
    // Out of capacity. Wait one full step, less whatever the caller already
    // spent since the last attempt, plus a penalty proportional to how far into
    // the hole the bucket already was -- so a caller that keeps hammering backs
    // off further each time instead of settling into a tight retry loop.
    let already_waited = if now > self.last_updated {
      now - self.last_updated
    } else {
      0L
    }
    let abs_capacity = if self.capacity < 0L {
      -self.capacity
    } else {
      self.capacity
    }
    let penalty = self.rate_limit_in_millis *
      abs_capacity /
      self.max_capacity.to_int64()
    let base = if self.rate_limit_in_millis > already_waited {
      self.rate_limit_in_millis - already_waited
    } else {
      0L
    }
    {
      ..self,
      capacity: refilled - 1L,
      last_arrived: new_last_arrived,
      last_updated: now,
      delay_millis: base + penalty,
    }
  }
}

///|
/// Adopt a delay Slack asked for.
///
/// `Retry-After` is authoritative in a way the local bucket is not: it is the
/// server saying how long it will keep refusing. Taking the larger of the two
/// means a server that is stricter than the documented tier -- which happens,
/// since the tiers are floors -- is still respected.
pub fn ThrottlingCounter::with_retry_after(
  self : Self,
  seconds : Int,
) -> ThrottlingCounter {
  let asked = seconds.to_int64() * 1000L
  if asked > self.delay_millis {
    { ..self, delay_millis: asked }
  } else {
    self
  }
}
