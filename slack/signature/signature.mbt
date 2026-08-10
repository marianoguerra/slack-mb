// Verifying that a request really came from Slack.
//
// https://docs.slack.dev/authentication/verifying-requests-from-slack
//
// Slack signs `v0:{timestamp}:{raw body}` with the app's signing secret using
// HMAC-SHA256 and sends the lowercase hex digest as `v0=<hex>`. Two things make
// this easy to get subtly wrong, and both are pinned by tests here:
//
//   * The body must be the RAW bytes, byte for byte as received. A framework
//     that parses and re-serialises the form -- reordering keys, normalising
//     percent-encoding -- produces a body that no longer hashes to the same
//     value. This package therefore takes the body as a string it encodes
//     itself and never touches its contents.
//   * The timestamp is not decoration. Without checking it, a signature
//     captured off the wire stays valid forever.

///|
pub let header_signature : String = "x-slack-signature"

///|
pub let header_timestamp : String = "x-slack-request-timestamp"

///|
/// The environment variable Slack's own SDKs read the secret from. Named here
/// so a caller does not have to guess at the spelling; this package never reads
/// the environment itself (it has no way to, on wasm).
pub let signing_secret_env : String = "SLACK_SIGNING_SECRET"

///|
/// Slack's documented replay window.
pub let max_timestamp_age_seconds : Int = 60 * 5

///|
/// Why a request was rejected.
///
/// Separate variants rather than a bare `Bool` because the failures mean
/// completely different things operationally: a bad secret is a deployment
/// mistake, an expired timestamp is usually clock skew, and a wrong signature
/// is either a bug or an attack. A receiver still answers all of them with 401.
pub(all) suberror SignatureError {
  /// The signing secret is empty. A deployment mistake, not a request problem.
  EmptySigningSecret
  /// The timestamp header is not an integer.
  MalformedTimestamp(String)
  /// The timestamp is outside the replay window.
  ExpiredTimestamp(ts~ : String, now~ : Int64, max_age_seconds~ : Int)
  /// The signature does not match. `expected` is included because it is the
  /// only way to debug a mismatch, and it is not a secret -- anyone who can
  /// produce the body and the timestamp can compute it.
  WrongSignature(received~ : String, expected~ : String, body_len~ : Int)
  /// A required header was absent.
  MissingHeader(String)
} derive(Eq, Debug)

///|
pub impl Show for SignatureError with fn output(self, logger) {
  logger.write_string(self.describe_error())
}

///|
pub fn SignatureError::describe_error(self : Self) -> String {
  match self {
    EmptySigningSecret =>
      "The signing secret is required to generate signature values. Set the env variable \{signing_secret_env} or pass the value to Verifier::new."
    MalformedTimestamp(ts) => "Timestamp is not a valid integer: '\{ts}'"
    ExpiredTimestamp(ts~, now~, max_age_seconds~) =>
      "Timestamp is either incorrect or expired: now: \{now}, ts: \{ts}. It should be within \{max_age_seconds} seconds."
    WrongSignature(received~, expected~, body_len~) =>
      "Slack request signature validation error: body len: \{body_len}, received hash: \{received}, generated hash: \{expected}"
    MissingHeader(name) => "Missing request header: \{name}"
  }
}

///|
/// Holds one app's signing secret.
///
/// `max_age_seconds` is per-verifier rather than a global constant because a
/// receiver behind a load balancer with known clock skew may legitimately need
/// a wider window, and forking the library to widen it would be absurd.
pub struct Verifier {
  secret : String
  max_age_seconds : Int
}

///|
/// Raises on an empty or whitespace-only secret, which is what an unset
/// environment variable usually looks like. java-slack-sdk fails at
/// construction the same way; slack-morphism defers it to the first
/// verification, which is a worse place to learn about it.
pub fn Verifier::new(
  signing_secret : String,
  max_age_seconds? : Int = max_timestamp_age_seconds,
) -> Verifier raise SignatureError {
  if signing_secret.trim().is_empty() {
    raise EmptySigningSecret
  }
  { secret: signing_secret, max_age_seconds }
}

///|
/// The `v0=<lowercase hex>` value Slack would have sent for this body and
/// timestamp. Public because a test harness needs to produce signed requests,
/// and because it is exactly what verification compares against.
pub fn Verifier::sign(self : Self, body : String, timestamp : String) -> String {
  let base = "v0:\{timestamp}:\{body}"
  let mac = @crypto.hmac_sha256(
    @utf8.encode(self.secret)[:],
    @utf8.encode(base)[:],
  )
  "v0=" + @crypto.to_hex(mac[:])
}

///|
/// Verify a request as of `now` (epoch seconds).
///
/// The timestamp is checked first: a stale request is rejected without hashing
/// a body that may be megabytes long, which is the difference between shrugging
/// off a replay flood and doing the attacker's HMAC work for them.
///
/// The window is two-sided, following slack-morphism. java-slack-sdk checks
/// only `now - ts`, so it accepts arbitrarily future timestamps -- a receiver
/// whose clock runs behind Slack's would happily accept a signature it should
/// have questioned. Widen `max_age_seconds` if your clocks disagree; don't
/// accept the future silently.
pub fn Verifier::verify_at_time(
  self : Self,
  signature : String,
  body : String,
  timestamp : String,
  now : Int64,
) -> Unit raise SignatureError {
  let ts_value = @string.parse_int64(timestamp) catch {
    _ => raise MalformedTimestamp(timestamp)
  }
  let age = now - ts_value
  let abs_age = if age < 0L { -age } else { age }
  if abs_age > self.max_age_seconds.to_int64() {
    raise ExpiredTimestamp(
      ts=timestamp,
      now~,
      max_age_seconds=self.max_age_seconds,
    )
  }
  let expected = self.sign(body, timestamp)
  let matches = @crypto.constant_time_eq(
    @utf8.encode(signature)[:],
    @utf8.encode(expected)[:],
  )
  if !matches {
    raise WrongSignature(received=signature, expected~, body_len=body.length())
  }
}

///|
/// Verify from a header map, looking both names up case-insensitively.
///
/// Header casing is not stable across gateways -- API Gateway lowercases,
/// others preserve whatever the client sent -- and java-slack-sdk has a test
/// for exactly this. Doing the fold here beats every caller remembering to.
pub fn Verifier::verify_headers(
  self : Self,
  headers : Map[String, String],
  body : String,
  now : Int64,
) -> Unit raise SignatureError {
  guard header_lookup(headers, header_signature) is Some(sig) else {
    raise MissingHeader(header_signature)
  }
  guard header_lookup(headers, header_timestamp) is Some(ts) else {
    raise MissingHeader(header_timestamp)
  }
  self.verify_at_time(sig, body, ts, now)
}

///|
fn header_lookup(headers : Map[String, String], name : String) -> String? {
  match headers.get(name) {
    Some(v) => Some(v)
    None => {
      for k, v in headers {
        if k.to_lower() == name {
          return Some(v)
        }
      }
      None
    }
  }
}
