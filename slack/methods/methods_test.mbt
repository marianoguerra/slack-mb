// The tier table is generated data, so what is worth testing is the shape of
// it and the judgements layered on top -- not the 326 individual entries, which
// ext/test/coverage checks against Slack's own documentation instead.

///|
test "the table covers every method in Slack's rate-limit metadata" {
  assert_eq(@methods.method_names.length(), 326)
  // Every listed name resolves; a name in the list with no tier would mean the
  // generator emitted one loop and not the other.
  for name in @methods.method_names {
    assert_true(@methods.tier_of(name) is Some(_), msg=name)
    assert_true(@methods.is_known(name), msg=name)
  }
}

///|
test "the method_names list is sorted and free of duplicates" {
  let mut previous = ""
  for name in @methods.method_names {
    assert_true(
      previous.lexical_compare(name) < 0,
      msg="\{previous} should sort before \{name}",
    )
    previous = name
  }
}

///|
/// java-slack-sdk's `MethodsRateLimitTier.allowedRequestsPerMinute`, verbatim.
/// The two 60s are not the same 60: `chat.postMessage` is per channel and
/// `assistant.threads.setStatus` is per DM.
test "tier limits match java-slack-sdk" {
  assert_eq(@methods.RateLimitTier::Tier1.allowed_requests_per_minute(), 1)
  assert_eq(@methods.RateLimitTier::Tier2.allowed_requests_per_minute(), 20)
  assert_eq(@methods.RateLimitTier::Tier3.allowed_requests_per_minute(), 50)
  assert_eq(@methods.RateLimitTier::Tier4.allowed_requests_per_minute(), 100)
  assert_eq(
    @methods.RateLimitTier::SpecialAuthTest.allowed_requests_per_minute(),
    600,
  )
  assert_eq(
    @methods.RateLimitTier::SpecialChatGetPermalink.allowed_requests_per_minute(),
    600,
  )
  assert_eq(
    @methods.RateLimitTier::SpecialChatPostMessage.allowed_requests_per_minute(),
    60,
  )
  assert_eq(
    @methods.RateLimitTier::SpecialAssistantThreadsSetStatus.allowed_requests_per_minute(),
    60,
  )
}

///|
/// Every tier round-trips through the metadata spelling, which is what the
/// generator emits and what a refreshed `rate_limit_tiers.json` will contain.
test "tier names round-trip" {
  assert_eq(@methods.all_tiers.length(), 8)
  for tier in @methods.all_tiers {
    assert_eq(
      @methods.RateLimitTier::parse(tier.to_metadata_name()),
      Some(tier),
    )
  }
  assert_eq(@methods.RateLimitTier::parse("Tier9"), None)
  assert_eq(@methods.RateLimitTier::parse(""), None)
}

///|
/// java-slack-sdk treats an unrecognised method as Tier2 rather than crashing
/// or leaving it unthrottled. Tier2 is not necessarily right, but a wrong
/// number is recoverable and no number is not.
test "an unknown method falls back to Tier2" {
  assert_eq(@methods.tier_of("chat.notARealMethod"), None)
  assert_false(@methods.is_known("chat.notARealMethod"))
  assert_eq(@methods.allowed_requests_per_minute("chat.notARealMethod"), 20)
  assert_eq(@methods.allowed_requests_per_minute(""), 20)
}

///|
/// A spot-check that the generated constants say what their names claim, across
/// every tier including the four special ones.
test "the generated constants and their tiers" {
  assert_eq(@methods.chat_post_message, "chat.postMessage")
  assert_eq(@methods.conversations_list, "conversations.list")
  assert_eq(@methods.users_lookup_by_email, "users.lookupByEmail")
  assert_eq(
    @methods.admin_conversations_bulk_archive, "admin.conversations.bulkArchive",
  )
  assert_eq(@methods.oauth_v2_access, "oauth.v2.access")
  assert_eq(
    @methods.files_get_upload_url_external, "files.getUploadURLExternal",
  )
  assert_eq(
    @methods.tier_of(@methods.chat_post_message),
    Some(SpecialChatPostMessage),
  )
  assert_eq(@methods.tier_of(@methods.auth_test), Some(SpecialAuthTest))
  assert_eq(
    @methods.tier_of(@methods.chat_get_permalink),
    Some(SpecialChatGetPermalink),
  )
  assert_eq(
    @methods.tier_of(@methods.assistant_threads_set_status),
    Some(SpecialAssistantThreadsSetStatus),
  )
  assert_eq(@methods.tier_of(@methods.conversations_list), Some(Tier2))
  assert_eq(@methods.tier_of(@methods.conversations_history), Some(Tier3))
  assert_eq(@methods.tier_of(@methods.admin_apps_uninstall), Some(Tier1))
}

///|
/// `chat.postMessage`'s limit is per channel, which is why a throttling key for
/// it has to include the channel id -- see @ratectl. Recorded here because the
/// number alone does not say so.
test "the special tiers are the ones with a scope other than the workspace" {
  let per_channel = @methods.RateLimitTier::SpecialChatPostMessage
  let per_dm = @methods.RateLimitTier::SpecialAssistantThreadsSetStatus
  assert_eq(per_channel.allowed_requests_per_minute(), 60)
  assert_eq(per_dm.allowed_requests_per_minute(), 60)
  // ...and they are a far higher allowance than the tier they would otherwise
  // fall into, which is the whole reason they are called out separately.
  assert_true(
    per_channel.allowed_requests_per_minute() >
    @methods.RateLimitTier::Tier2.allowed_requests_per_minute(),
  )
}
