// The scoping rules, which are the part of throttling that is Slack knowledge
// rather than arithmetic.

///|
test "each method gets its own bucket" {
  let t = @ratectl.Throttler::new()
  let now = 1_000_000L
  // conversations.list is Tier2: 20/minute, so the 21st call in one instant
  // waits. chat.getPermalink allows 600/minute and is unaffected.
  for _ in 0..<20 {
    assert_eq(t.acquire(@methods.conversations_list, now), 0L)
  }
  assert_true(t.acquire(@methods.conversations_list, now) > 0L)
  assert_eq(t.acquire(@methods.chat_get_permalink, now), 0L)
}

///|
/// `chat.postMessage`'s limit is roughly one message per second PER CHANNEL. A
/// bucket keyed on the method name alone would throttle a bot posting to fifty
/// channels as though it were posting fifty times to one -- which is the whole
/// reason Slack calls this tier out separately.
test "chat.postMessage is throttled per channel" {
  let t = @ratectl.Throttler::new()
  let now = 1_000_000L
  // 60/minute is a capacity of 60 for one channel.
  for _ in 0..<60 {
    assert_eq(t.acquire(@methods.chat_post_message, now, scope="C111"), 0L)
  }
  assert_true(t.acquire(@methods.chat_post_message, now, scope="C111") > 0L)
  // A different channel starts with a full bucket.
  assert_eq(t.acquire(@methods.chat_post_message, now, scope="C222"), 0L)
}

///|
/// The converse, and the reason the rule is not just "always key by scope": a
/// per-workspace limit keyed per channel would let a bot exceed the workspace
/// limit simply by spreading its calls around.
test "a per-workspace method ignores the scope" {
  let t = @ratectl.Throttler::new()
  let now = 1_000_000L
  assert_eq(
    t.throttling_key(@methods.conversations_list, scope="C111"),
    t.throttling_key(@methods.conversations_list, scope="C222"),
  )
  for _ in 0..<20 {
    t.acquire(@methods.conversations_list, now, scope="C111") |> ignore
  }
  // Spreading across channels does not buy more budget.
  assert_true(t.acquire(@methods.conversations_list, now, scope="C999") > 0L)
}

///|
test "assistant.threads.setStatus is throttled per DM" {
  let t = @ratectl.Throttler::new()
  assert_not_eq(
    t.throttling_key(@methods.assistant_threads_set_status, scope="D111"),
    t.throttling_key(@methods.assistant_threads_set_status, scope="D222"),
  )
}

///|
/// One process serving several workspaces must not pool their budgets: Slack
/// counts per workspace, so sharing a bucket would throttle a quiet workspace
/// because a busy one was busy.
test "workspaces do not share buckets" {
  let a = @ratectl.Throttler::new(team_id="T111")
  let b = @ratectl.Throttler::new(team_id="T222")
  assert_not_eq(
    a.throttling_key(@methods.conversations_list),
    b.throttling_key(@methods.conversations_list),
  )
  let now = 1_000_000L
  for _ in 0..<21 {
    a.acquire(@methods.conversations_list, now) |> ignore
  }
  assert_eq(b.acquire(@methods.conversations_list, now), 0L)
}

///|
/// A `Retry-After` Slack sent applies to the scope it was sent for and nothing
/// else.
test "a noted Retry-After applies to its own scope" {
  let t = @ratectl.Throttler::new()
  let now = 1_000_000L
  t.note_retry_after(@methods.chat_post_message, 30, now, scope="C111")
  assert_eq(t.delay_millis(@methods.chat_post_message, scope="C111"), 30_000L)
  assert_eq(t.delay_millis(@methods.chat_post_message, scope="C222"), 0L)
  assert_eq(t.delay_millis(@methods.conversations_list), 0L)
}

///|
/// Waiting the delay out restores capacity, which is the whole point: a client
/// that obeys the pacing never gets throttled again.
test "capacity recovers once the caller waits" {
  let t = @ratectl.Throttler::new()
  let mut now = 1_000_000L
  for _ in 0..<20 {
    t.acquire(@methods.conversations_list, now) |> ignore
  }
  let delay = t.acquire(@methods.conversations_list, now)
  assert_true(delay > 0L)
  // Tier2 is 20/minute: 3000ms apart. After a full window the bucket is full.
  now = now + 60_000L
  assert_eq(t.acquire(@methods.conversations_list, now), 0L)
}
