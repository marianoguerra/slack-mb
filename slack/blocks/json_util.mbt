// The take-and-remove helpers this package parses with, and the one that is
// specific to it.
//
// The helpers themselves moved to @jsonx when @model came along and needed the
// same discipline; the reasoning behind that discipline is in their new home.
// They are aliased rather than re-implemented so that every call site in this
// package still reads `take_str(rest, "text")`, and so that there is exactly
// one definition for `ext/test/corpus` to hold to the round-trip property.

///|
using @jsonx {
  fields_of,
  take_str,
  take_bool,
  take_int,
  take_json,
  take_obj,
  take_arr,
  take_str_arr,
  put_str,
  put_bool,
  put_int,
  put_json,
  put_obj,
  put_arr,
  put_str_arr,
  merge_extra,
}

///|
/// Start an output object with its `type` tag.
///
/// Stays here rather than in @jsonx: a type-tagged object is a Block Kit shape.
/// A `User` or a `Channel` carries no `type`, so @model has no use for it.
fn out_of(type_ : String) -> Map[String, Json] {
  let o : Map[String, Json] = Map([])
  o["type"] = Json::string(type_)
  o
}
