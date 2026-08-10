// Ported from java-slack-sdk's `SlackSignatureTest` and slack-morphism's
// `signature_verifier::test`.
//
// Two golden vectors from two independent implementations, computed with
// different secrets over different bodies. Either one alone proves the HMAC
// runs; together they leave nowhere for a construction bug to hide -- a wrong
// base string or a swapped key/message argument cannot satisfy both.

///|
/// java-slack-sdk `SlackSignatureTest#generate`. The body is a real slash
/// command payload, percent-encoding and all, which is the point: it is the
/// shape that breaks when a framework re-serialises the form before verifying.
let java_secret : String = "8f742231b10e8888abcd99yyyzzz85a5"

///|
let java_timestamp : String = "1531420618"

///|
let java_body : String =
  #|token=xyzz0WbapA4vBCDEFasx0q6G&team_id=T1DC2JH3J&team_domain=testteamnow&channel_id=G8PSS9T3V&channel_name=foobar&user_id=U2CERLKJA&user_name=roadrunner&command=%2Fwebhook-collect&text=&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2FT1DC2JH3J%2F397700885554%2F96rGlfmibIGlgcZRskXaIFfN&trigger_id=398738663015.47445629121.803a0bc887a14d10d2c447fce8b6703c

///|
let java_signature : String = "v0=a2114d57b48eac39b9ad189dd8316235a7b4a8d21a10bd27519666489c69b503"

///|
/// slack-morphism `test_precoded_data`.
let morphism_secret : String = "fa2c05deeef5a4077494e89f54394de0"

///|
let morphism_signature : String = "v0=baa91ef62d346e56607bbdd278a8acd570b91226854f15a382f43d33be42f666"

///|
fn verifier(secret : String) -> @signature.Verifier {
  @signature.Verifier::new(secret) catch {
    e => abort("verifier construction failed: \{e}")
  }
}

///|
test "the java-slack-sdk golden vector" {
  assert_eq(
    verifier(java_secret).sign(java_body, java_timestamp),
    java_signature,
  )
}

///|
test "the slack-morphism golden vector" {
  // Verified at 1531420620 -- two seconds after the timestamp -- exactly as
  // morphism's `verify_at_time` call does.
  verifier(morphism_secret).verify_at_time(
    morphism_signature, "test-body", "1531420618", 1531420620L,
  )
}

///|
/// Signing and verifying are the same computation read in two directions; a
/// round trip catches a `sign` that drifts from what `verify_at_time` expects.
test "a signature this library produces is one it accepts" {
  let v = verifier("some-signing-secret")
  let body = "payload=%7B%22type%22%3A%22block_actions%22%7D"
  let sig = v.sign(body, "1700000000")
  v.verify_at_time(sig, body, "1700000000", 1700000000L)
}

///|
/// An empty or whitespace-only secret is what an unset SLACK_SIGNING_SECRET
/// looks like, and it must fail loudly at construction rather than silently
/// signing everything with the empty key.
test "an empty signing secret is rejected at construction" {
  for bad in ["", " ", "\t\n"] {
    try @signature.Verifier::new(bad) |> ignore catch {
      @signature.EmptySigningSecret => ()
      e => fail("unexpected error for \{bad.escape()}: \{e}")
    } noraise {
      _ => fail("expected \{bad.escape()} to be rejected")
    }
  }
}

///|
test "a non-numeric timestamp is malformed, not merely expired" {
  let v = verifier(java_secret)
  for bad in ["", "not-a-number", "17000000oo", "1.5"] {
    try v.verify_at_time(java_signature, java_body, bad, 1531420618L) catch {
      @signature.MalformedTimestamp(got) => assert_eq(got, bad)
      e => fail("unexpected error for \{bad.escape()}: \{e}")
    } noraise {
      _ => fail("expected \{bad.escape()} to be rejected")
    }
  }
}

///|
/// java-slack-sdk's `TimestampVerifier` test checks `now` and `now - 301`; this
/// is the same boundary, expressed against the seam that makes it deterministic.
test "the replay window is exactly five minutes wide" {
  let v = verifier(java_secret)
  let ts = 1531420618L

  // Dead on the boundary is still accepted.
  v.verify_at_time(java_signature, java_body, java_timestamp, ts + 300L)
  v.verify_at_time(java_signature, java_body, java_timestamp, ts - 300L)

  // One second past it, in either direction, is not.
  for now in [ts + 301L, ts - 301L] {
    try v.verify_at_time(java_signature, java_body, java_timestamp, now) catch {
      @signature.ExpiredTimestamp(ts=got, ..) => assert_eq(got, java_timestamp)
      e => fail("unexpected error at now=\{now}: \{e}")
    } noraise {
      _ => fail("expected now=\{now} to be outside the window")
    }
  }
}

///|
/// The divergence from java-slack-sdk, pinned so it cannot be "fixed" by
/// accident: java checks only `now - ts`, so it accepts any future timestamp.
/// Here the window is two-sided, as in slack-morphism.
test "a far-future timestamp is rejected, unlike java-slack-sdk" {
  let v = verifier(java_secret)
  let far_future = 1531420618L - 86400L // now is a day BEHIND the request
  try
    v.verify_at_time(java_signature, java_body, java_timestamp, far_future)
  catch {
    @signature.ExpiredTimestamp(..) => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a future timestamp to be rejected")
  }
}

///|
/// A wider window is a per-verifier decision, so a receiver with known clock
/// skew does not have to fork the library.
test "max_age_seconds widens the window" {
  let v = @signature.Verifier::new(java_secret, max_age_seconds=3600) catch {
    e => abort("\{e}")
  }
  v.verify_at_time(
    java_signature,
    java_body,
    java_timestamp,
    1531420618L + 3000L,
  )
}

///|
/// slack-morphism `check_signature_error`: sign with one key, verify with
/// another.
test "a signature made with the wrong secret is rejected" {
  let honest = verifier("correct-key")
  let forger = verifier("malicious-key")
  let body = "test-body"
  let forged = forger.sign(body, "1531420618")
  try honest.verify_at_time(forged, body, "1531420618", 1531420618L) catch {
    @signature.WrongSignature(received~, expected~, body_len~) => {
      assert_eq(received, forged)
      assert_not_eq(expected, forged)
      assert_eq(body_len, body.length())
    }
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected the forged signature to be rejected")
  }
}

///|
/// The whole reason the raw body matters: one flipped character anywhere in it
/// invalidates the signature.
test "a tampered body is rejected" {
  let v = verifier(java_secret)
  let tampered = java_body.replace(old="roadrunner", new="wilecoyote")
  assert_not_eq(tampered, java_body)
  try
    v.verify_at_time(java_signature, tampered, java_timestamp, 1531420618L)
  catch {
    @signature.WrongSignature(..) => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a tampered body to be rejected")
  }
}

///|
/// Slack's own signature is a `v0=` prefix over hex. A caller who strips the
/// prefix, or sends the digest alone, must not accidentally pass.
test "the v0= prefix is part of the signature" {
  let v = verifier(java_secret)
  let bare = java_signature.replace(old="v0=", new="")
  try v.verify_at_time(bare, java_body, java_timestamp, 1531420618L) catch {
    @signature.WrongSignature(..) => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a prefix-less signature to be rejected")
  }
}

///|
/// java-slack-sdk pins header-name case-insensitivity in
/// `WebEndpointRequestTest` and `BlockActionRequestTest`; gateways disagree
/// about casing and a receiver should not have to care.
test "headers are looked up case-insensitively" {
  let v = verifier(java_secret)
  for
    names in [
      ["x-slack-signature", "x-slack-request-timestamp"],
      ["X-Slack-Signature", "X-Slack-Request-Timestamp"],
      ["X-SLACK-SIGNATURE", "X-SLACK-REQUEST-TIMESTAMP"],
    ] {
    let headers : Map[String, String] = Map([])
    headers[names[0]] = java_signature
    headers[names[1]] = java_timestamp
    v.verify_headers(headers, java_body, 1531420618L)
  }
}

///|
test "a missing header names itself" {
  let v = verifier(java_secret)
  let only_ts = { "x-slack-request-timestamp": java_timestamp }
  try v.verify_headers(only_ts, java_body, 1531420618L) catch {
    @signature.MissingHeader(name) => assert_eq(name, "x-slack-signature")
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a missing-signature error")
  }
  let only_sig = { "x-slack-signature": java_signature }
  try v.verify_headers(only_sig, java_body, 1531420618L) catch {
    @signature.MissingHeader(name) =>
      assert_eq(name, "x-slack-request-timestamp")
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a missing-timestamp error")
  }
}

///|
/// The messages are what an operator sees in a log at 3am, so they are pinned.
test "error messages say what went wrong" {
  let empty = @signature.EmptySigningSecret
  assert_true(empty.describe_error().contains("SLACK_SIGNING_SECRET"))
  let expired = @signature.ExpiredTimestamp(
    ts="1531420618",
    now=1600000000L,
    max_age_seconds=300,
  )
  assert_true(expired.describe_error().contains("1531420618"))
  assert_true(expired.describe_error().contains("300"))
}
