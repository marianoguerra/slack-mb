// The four invariants @blocks and @model both rely on.
//
// `ext/test/corpus` already exercises these against 2,548 real blocks, but only
// transitively: it can tell you a round trip broke, not which helper let the
// field through. Each test here pins one rule its doc comment states, so a
// future @model parser inherits a promise rather than an observation.

///|
/// A refused value stays put, so it lands in `extra` instead of vanishing.
///
/// The corpus is the reason: java-slack-sdk's samples merge every observed
/// shape of a payload into one object, so a field routinely arrives at a type
/// its own model does not expect.
test "a value of the wrong type is not taken" {
  let rest : Map[String, Json] = {
    "text": Json::number(1.0),
    "emoji": Json::string("yes"),
    "count": Json::string("3"),
  }
  assert_eq(@jsonx.take_str(rest, "text"), None)
  assert_eq(@jsonx.take_bool(rest, "emoji"), None)
  assert_eq(@jsonx.take_int(rest, "count"), None)
  assert_eq(rest.length(), 3)
}

///|
/// A fractional number is not an integer, and rounding it would lose the value
/// on the way back out.
test "take_int refuses a fraction and accepts a whole double" {
  let rest : Map[String, Json] = {
    "frac": Json::number(1.5),
    "whole": Json::number(3.0),
  }
  assert_eq(@jsonx.take_int(rest, "frac"), None)
  assert_eq(@jsonx.take_int(rest, "whole"), Some(3))
  assert_eq(rest.contains("frac"), true)
  assert_eq(rest.contains("whole"), false)
}

///|
/// The same rule as `take_int`, at the width the epoch-second fields need.
/// 2^31 seconds after 1970 is January 2038, which an `Int` cannot hold and a
/// `created` field will eventually carry.
test "take_int64 spans past what an Int holds" {
  let beyond_int = 2147483648.0
  let rest : Map[String, Json] = {
    "created": Json::number(beyond_int),
    "frac": Json::number(1.5),
  }
  assert_eq(@jsonx.take_int64(rest, "created"), Some(2147483648L))
  assert_eq(@jsonx.take_int64(rest, "frac"), None)
  assert_eq(rest.contains("frac"), true)
  let out : Map[String, Json] = Map([])
  @jsonx.put_int64(out, "created", Some(2147483648L))
  assert_eq(out.get("created"), Some(Json::number(beyond_int)))
}

///|
/// All-or-nothing: one bad element leaves the whole key alone. A half-parsed
/// list would round-trip as a shorter list, which is silent data loss.
test "take_arr keeps the key when any element is refused" {
  let str_of = j => if j is String(s) { Some(s) } else { None }
  let rest : Map[String, Json] = {
    "mixed": [Json::string("a"), Json::number(2.0)],
    "clean": [Json::string("a"), Json::string("b")],
  }
  assert_eq(@jsonx.take_arr(rest, "mixed", str_of), None)
  assert_eq(rest.contains("mixed"), true)
  assert_eq(@jsonx.take_arr(rest, "clean", str_of), Some(["a", "b"]))
  assert_eq(rest.contains("clean"), false)
}

///|
/// An empty array is written, not omitted: Slack distinguishes "no such field"
/// from "an empty one", so a round trip must too.
test "put_arr writes an empty array but omits an absent one" {
  let o : Map[String, Json] = Map([])
  @jsonx.put_str_arr(o, "empty", Some([]))
  @jsonx.put_str_arr(o, "absent", None)
  assert_eq(o.get("empty"), Some(Json::array([])))
  assert_eq(o.contains("absent"), false)
}

///|
/// A modelled field wins over an `extra` of the same name -- the typed one is
/// the one the caller can see in their editor.
test "merge_extra does not let extra shadow a modelled field" {
  let o : Map[String, Json] = { "text": Json::string("modelled") }
  let extra : Map[String, Json] = {
    "text": Json::string("stale"),
    "unmodelled": Json::string("kept"),
  }
  assert_eq(@jsonx.merge_extra(o, extra), {
    "text": "modelled",
    "unmodelled": "kept",
  })
}

///|
/// `fields_of` hands back a copy, so taking from it cannot mutate the caller's
/// input. Every `from_json` starts here for that reason.
test "fields_of copies rather than aliases" {
  let source : Map[String, Json] = { "text": Json::string("hi") }
  let rest = @jsonx.fields_of(source)
  assert_eq(@jsonx.take_str(rest, "text"), Some("hi"))
  assert_eq(rest.length(), 0)
  assert_eq(source.length(), 1)
}
