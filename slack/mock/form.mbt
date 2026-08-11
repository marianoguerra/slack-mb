// Reading the decoded form body.
//
// The typed half of `@api.decode_form`: that gives ordered `(String, String)`
// pairs, and this turns them into the Ints, Bools, CSV lists and JSON blobs the
// handlers actually want. It is the mirror of `@api.Params` -- `Params` writes
// the wire, `Form` reads it -- and keeping it here rather than in @api is
// deliberate: which spelling a field wants is a per-method fact, and the
// handlers are where those facts live.

///|
/// One decoded request body.
pub struct Form {
  entries : Array[(String, String)]
}

///|
pub fn Form::of(entries : Array[(String, String)]) -> Form {
  { entries, }
}

///|
/// An empty body. For a method that takes no arguments, and for tests.
pub fn Form::new() -> Form {
  { entries: [] }
}

///|
pub fn Form::entries(self : Self) -> Array[(String, String)] {
  self.entries
}

///|
/// The first value for a field, or `None`.
///
/// First and not last: Slack's own parser takes the first, and a repeated field
/// is a caller bug rather than an override.
pub fn Form::get(self : Self, key : String) -> String? {
  for entry in self.entries {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
pub fn Form::has(self : Self, key : String) -> Bool {
  self.get(key) is Some(_)
}

///|
/// A field that must name something, or the error code the method uses.
///
/// An EMPTY value counts as absent: Slack treats `channel=` as a missing
/// channel rather than as a channel named "", and the `put_*` family on
/// `Params` never emits an empty field for an absent argument -- so a field
/// that arrives empty was empty in the caller's hand.
///
/// The code is a parameter because Slack does not answer `invalid_arguments`
/// for every absent argument: a missing `channel` is `channel_not_found`, a
/// missing `user` is `user_not_found`. Which one is a per-method fact, so the
/// handler says.
fn Form::require_as(
  self : Self,
  key : String,
  code : String,
) -> String raise Refusal {
  match self.get(key) {
    Some(v) if !v.is_empty() => v
    _ => raise refuse(code)
  }
}

///|
/// An integer field, or `None` if absent or unparseable.
///
/// Unparseable reads as absent rather than raising, because that is what the
/// handler wants nearly everywhere: `limit=abc` should fall back to the
/// method's default, not fail the call. A handler that needs to reject it can
/// check `has` first.
pub fn Form::int(self : Self, key : String) -> Int? {
  guard self.get(key) is Some(v) else { return None }
  Some(@string.parse_int(v)) catch {
    _ => None
  }
}

///|
pub fn Form::i64(self : Self, key : String) -> Int64? {
  guard self.get(key) is Some(v) else { return None }
  Some(@string.parse_int64(v)) catch {
    _ => None
  }
}

///|
/// A boolean field, in either spelling.
///
/// Not a nicety: `Client.bool_style` is a knob, because node-slack-sdk sends
/// `true`/`false` and java-slack-sdk sends `1`/`0` and Slack accepts both. A
/// mock that understood only one spelling would silently misread half its
/// callers -- `exclude_archived=1` read as absent is a listing with the
/// archived channels still in it, which looks like a paging bug.
pub fn Form::bool(self : Self, key : String) -> Bool? {
  match self.get(key) {
    Some("true") | Some("1") => Some(true)
    Some("false") | Some("0") => Some(false)
    _ => None
  }
}

///|
/// A boolean field with a default, which is how nearly every handler wants it.
fn Form::flag(self : Self, key : String, default~ : Bool) -> Bool {
  self.bool(key).unwrap_or(default)
}

///|
/// A comma-joined list. `Params::put_csv` is what writes these.
///
/// An empty field yields an empty array, not `[""]` -- the difference between
/// "no users" and "one user whose id is the empty string", and the second one
/// makes `conversations.invite` refuse with a baffling `user_not_found`.
pub fn Form::csv(self : Self, key : String) -> Array[String]? {
  match self.get(key) {
    Some(v) =>
      if v.is_empty() {
        Some([])
      } else {
        Some(v.split(",").map(part => part.to_owned()).collect())
      }
    None => None
  }
}

///|
/// A field carrying JSON -- `blocks`, `attachments`, `metadata`, `view`.
///
/// Unparseable JSON is a refusal rather than `None`, because there is no
/// sensible fallback: a caller who sent `blocks=notjson` meant to send blocks.
/// Slack answers `invalid_arguments` for a malformed `blocks` field, before it
/// gets as far as `invalid_blocks`.
fn Form::json(self : Self, key : String) -> Json? raise Refusal {
  guard self.get(key) is Some(v) else { return None }
  Some(@json.parse(v)) catch {
    _ => raise refuse("invalid_arguments")
  }
}
