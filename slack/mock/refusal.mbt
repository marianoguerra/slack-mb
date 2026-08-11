// How a handler declines.

///|
/// A refusal, on its way to `{"ok": false, "error": ...}`.
///
/// Every handler is written as though it succeeds and raises this when it
/// cannot, which is what keeps sixty-odd handlers to a handful of lines each.
/// The dispatcher turns it into an HTTP 200 carrying `ok: false` -- the shape
/// Slack really answers a refusal with, and the reason `ok` and the status code
/// are two separate questions throughout this library.
priv suberror Refusal {
  Refusal(
    code~ : String,
    needed~ : String?,
    provided~ : String?,
    messages~ : Array[String]
  )
}

///|
/// The common case: a bare error code, the way Slack sends most of them.
fn refuse(code : String) -> Refusal {
  Refusal(code~, needed=None, provided=None, messages=[])
}

///|
/// A refusal carrying `response_metadata.messages`.
///
/// Slack uses this for the diagnostics that say WHERE a payload was wrong --
/// `[ERROR] unsupported type: sections [json-pointer:/blocks/0/type]` -- and
/// `ResponseMetadata::diagnostics` in @api exists to read them.
fn refuse_with_messages(code : String, messages : Array[String]) -> Refusal {
  Refusal(code~, needed=None, provided=None, messages~)
}

///|
/// `missing_scope`, spelled the way the error taxonomy reads it.
///
/// `needed` and `provided` are the whole content of a missing scope:
/// `SlackError::describe_error_java` is the only description that surfaces
/// them, and `ext/cmd/integration`'s `Report::check` turns exactly this pair
/// into a skip. A mock that refused without them would fail a scenario where
/// real Slack skips it.
fn refuse_scope(needed : String, provided : Array[String]) -> Refusal {
  Refusal(
    code="missing_scope",
    needed=Some(needed),
    provided=Some(provided.join(",")),
    messages=[],
  )
}
