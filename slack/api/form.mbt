// Turning arguments into an `application/x-www-form-urlencoded` request body.
//
// Every Slack Web API method takes its arguments as a form body, even the ones
// whose arguments are structured -- `blocks` and `attachments` travel as a JSON
// string inside a form field, not as a JSON request. Getting this wrong is the
// single most common source of "invalid_blocks" from a client that looks
// correct, so the rules are pinned by the reference SDKs' own golden strings in
// form_test.mbt rather than restated here.

///|
/// One argument value.
///
/// A closed set rather than `Json`, because Slack's form encoding treats these
/// cases differently and a caller who hands over a bare `Json` has already lost
/// the distinction: `Str("42")` and `Int(42)` are the same bytes on the wire,
/// but `Csv(["a","b"])` and `JsonVal(["a","b"])` are `a,b` and `["a","b"]`, and
/// which one a field wants is a per-field fact from Slack's docs.
pub(all) enum ParamValue {
  Str(String)
  Int(Int)
  I64(Int64)
  Num(Double)
  Bool(Bool)
  /// Comma-joined, no spaces. Slack documents `users`, `channels`, `user_ids`
  /// and friends this way. java-slack-sdk joins these by hand at each such
  /// field -- 67 separate call sites -- which is the honest shape of it: the
  /// decision belongs to the field, not to a generic rule that would also
  /// mangle `blocks`.
  Csv(Array[String])
  /// Serialised with `Json::stringify`. `blocks`, `attachments`, `metadata`,
  /// and anything the generic `call` was handed as structured data.
  ///
  /// An empty array becomes `[]` and is NOT omitted: java-slack-sdk pins that,
  /// and Slack distinguishes "no blocks field" (keep the existing blocks on an
  /// update) from "an empty blocks field" (clear them).
  JsonVal(Json)
} derive(Eq, Debug)

///|
/// How booleans reach the wire.
///
/// The reference SDKs disagree: node-slack-sdk sends `true`/`false`,
/// java-slack-sdk sends `1`/`0`. Slack accepts both, so this is a knob rather
/// than a fork -- and having it is what lets both SDKs' golden strings be
/// tested literally.
pub(all) enum BoolStyle {
  /// `true` / `false`. node-slack-sdk, and what Slack's docs show. The default.
  TrueFalse
  /// `1` / `0`. java-slack-sdk's `RequestFormBuilder.setIfNotNull`.
  OneZero
} derive(Eq, Debug)

///|
/// An ordered list of `(name, value)` pairs.
///
/// Ordered, and not a `Map`: every reference SDK's golden request body is
/// position-sensitive, MoonBit's `Map` is a hash map, and a body whose field
/// order changes between runs is miserable to diff in a proxy log.
pub(all) struct Params {
  entries : Array[(String, ParamValue)]
} derive(Eq, Debug)

///|
pub fn Params::new() -> Params {
  { entries: [] }
}

///|
pub fn Params::of(entries : Array[(String, ParamValue)]) -> Params {
  { entries, }
}

///|
pub fn Params::length(self : Self) -> Int {
  self.entries.length()
}

///|
/// Append a value unconditionally.
pub fn Params::put(self : Self, key : String, value : ParamValue) -> Unit {
  self.entries.push((key, value))
}

///|
/// Append a value, or nothing at all when it is `None`.
///
/// The whole `put_*` family exists for this one behaviour. An absent argument
/// must vanish from the body; it must never become the four characters `null`,
/// which is what a naive `to_string` on an option produces and is the most
/// common form-encoding bug in hand-rolled Slack clients. Slack would read it
/// as the literal string "null" and reject or, worse, accept it.
pub fn Params::put_opt(self : Self, key : String, value : ParamValue?) -> Unit {
  if value is Some(v) {
    self.entries.push((key, v))
  }
}

///|
pub fn Params::put_str(self : Self, key : String, value : String?) -> Unit {
  self.put_opt(key, value.map(x => Str(x)))
}

///|
pub fn Params::put_int(self : Self, key : String, value : Int?) -> Unit {
  self.put_opt(key, value.map(x => Int(x)))
}

///|
pub fn Params::put_i64(self : Self, key : String, value : Int64?) -> Unit {
  self.put_opt(key, value.map(x => I64(x)))
}

///|
pub fn Params::put_num(self : Self, key : String, value : Double?) -> Unit {
  self.put_opt(key, value.map(x => Num(x)))
}

///|
pub fn Params::put_bool(self : Self, key : String, value : Bool?) -> Unit {
  self.put_opt(key, value.map(x => Bool(x)))
}

///|
pub fn Params::put_csv(
  self : Self,
  key : String,
  value : Array[String]?,
) -> Unit {
  self.put_opt(key, value.map(x => Csv(x)))
}

///|
pub fn Params::put_json(self : Self, key : String, value : Json?) -> Unit {
  self.put_opt(key, value.map(x => JsonVal(x)))
}

///|
/// The value as it appears between the `=` and the `&`, before percent-encoding.
pub fn ParamValue::to_wire(self : Self, bool_style~ : BoolStyle) -> String {
  match self {
    Str(s) => s
    Int(i) => i.to_string()
    I64(i) => i.to_string()
    Num(d) => d.to_string()
    Bool(b) =>
      match (b, bool_style) {
        (true, TrueFalse) => "true"
        (false, TrueFalse) => "false"
        (true, OneZero) => "1"
        (false, OneZero) => "0"
      }
    Csv(items) => items.join(",")
    JsonVal(j) => j.stringify()
  }
}

///|
/// Serialise to an `application/x-www-form-urlencoded` body.
pub fn encode_form(
  params : Params,
  bool_style? : BoolStyle = TrueFalse,
) -> String {
  let out = StringBuilder::new()
  let mut first = true
  for entry in params.entries {
    let (key, value) = entry
    if !first {
      out.write_char('&')
    }
    first = false
    out.write_string(percent_encode_component(key))
    out.write_char('=')
    out.write_string(percent_encode_component(value.to_wire(bool_style~)))
  }
  out.to_string()
}

///|
/// True for the characters JavaScript's `encodeURIComponent` leaves alone.
///
/// That is the set both reference implementations use --
/// node-slack-sdk goes through `node:querystring`, whose escape table is the
/// same one -- so matching it is what makes their golden bodies reproducible
/// here byte for byte.
fn is_unreserved(b : Byte) -> Bool {
  let c = b.to_int()
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  c == '-'.to_int() ||
  c == '_'.to_int() ||
  c == '.'.to_int() ||
  c == '!'.to_int() ||
  c == '~'.to_int() ||
  c == '*'.to_int() ||
  c == '\''.to_int() ||
  c == '('.to_int() ||
  c == ')'.to_int()
}

///|
let upper_hex : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
]

///|
/// Percent-encode one form field name or value.
///
/// Over the UTF-8 bytes, not the characters: MoonBit strings are UTF-16, so
/// encoding per code unit would emit surrogate halves for anything outside the
/// BMP and mis-encode every accented character. A body that disagrees with its
/// own `Content-Length` is the failure mode.
///
/// Space becomes `%20`, not `+`. Both are legal and Slack reads either, but
/// `%20` is what `node:querystring` and OkHttp's `FormBody` both emit, and a
/// signature is computed over the bytes actually sent -- so "whatever the
/// reference SDKs send" is the only defensible choice.
pub fn percent_encode_component(s : String) -> String {
  let bytes = @utf8.encode(s)
  let out = StringBuilder::new(size_hint=bytes.length())
  for i in 0..<bytes.length() {
    let b = bytes[i]
    if is_unreserved(b) {
      out.write_char(b.to_int().unsafe_to_char())
    } else {
      let v = b.to_int()
      out.write_char('%')
      out.write_char(upper_hex[v >> 4])
      out.write_char(upper_hex[v & 0xf])
    }
  }
  out.to_string()
}
