// Reading and writing JSON objects without losing anything.
//
// Every `from_json` built on these helpers works the same way: copy the object,
// take the fields it models -- which REMOVES them -- and keep whatever is left
// in `extra`. `to_json` writes the modelled fields back and then merges `extra`.
//
// The take-and-remove shape is what makes the round-trip property hold. A
// parser that instead listed its known keys and treated the rest as extra would
// silently drop any known key whose value had an unexpected type; here a field
// that fails to parse is simply never taken, so it stays in `extra` and comes
// back out unchanged. That matters more than it sounds: java-slack-sdk's
// fixture corpus scrubs values to type-representative placeholders and merges
// every observed shape of a payload into one object, so fields routinely appear
// with the "wrong" type or on an object that has no business carrying them.
//
// These lived in @blocks until @model needed the same discipline. `ext/test/
// corpus` checks the property they exist to support against 2,548 real blocks,
// which is the reason to share them rather than write a second set.

///|
/// A mutable copy of an object's fields, to take from.
pub fn fields_of(o : Map[String, Json]) -> Map[String, Json] {
  o.copy()
}

///|
pub fn take_str(rest : Map[String, Json], key : String) -> String? {
  match rest.get(key) {
    Some(String(s)) => {
      rest.remove(key)
      Some(s)
    }
    _ => None
  }
}

///|
pub fn take_bool(rest : Map[String, Json], key : String) -> Bool? {
  match rest.get(key) {
    Some(True) => {
      rest.remove(key)
      Some(true)
    }
    Some(False) => {
      rest.remove(key)
      Some(false)
    }
    _ => None
  }
}

///|
/// Whole numbers only. A Slack integer field carrying `1.5` is not an integer,
/// and rounding it would lose the value on the way back out.
pub fn take_int(rest : Map[String, Json], key : String) -> Int? {
  match rest.get(key) {
    Some(Number(n, ..)) => {
      let i = n.to_int()
      if i.to_double() == n {
        rest.remove(key)
        Some(i)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Whole numbers, as `Int64`.
///
/// For the epoch-second fields Slack puts on almost every entity -- `updated`,
/// `created`, `last_set`. They fit in an `Int` until 2038, which is not a
/// property to build a library on.
pub fn take_int64(rest : Map[String, Json], key : String) -> Int64? {
  match rest.get(key) {
    Some(Number(n, ..)) => {
      let i = n.to_int64()
      if i.to_double() == n {
        rest.remove(key)
        Some(i)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
pub fn take_json(rest : Map[String, Json], key : String) -> Json? {
  match rest.get(key) {
    Some(v) => {
      rest.remove(key)
      Some(v)
    }
    None => None
  }
}

///|
/// Take a nested object through a parser, leaving the key in place if the
/// parser refuses it.
pub fn[T] take_obj(
  rest : Map[String, Json],
  key : String,
  parse : (Json) -> T?,
) -> T? {
  match rest.get(key) {
    Some(v) =>
      match parse(v) {
        Some(parsed) => {
          rest.remove(key)
          Some(parsed)
        }
        None => None
      }
    None => None
  }
}

///|
/// Take an array through an element parser.
///
/// All-or-nothing: if any element is refused, the whole key stays put. A
/// half-parsed list would round-trip as a shorter list, which is a silent data
/// loss and exactly the kind of thing the corpus test exists to catch.
pub fn[T] take_arr(
  rest : Map[String, Json],
  key : String,
  parse : (Json) -> T?,
) -> Array[T]? {
  guard rest.get(key) is Some(Array(items)) else { return None }
  let out = []
  for item in items {
    guard parse(item) is Some(parsed) else { return None }
    out.push(parsed)
  }
  rest.remove(key)
  Some(out)
}

///|
pub fn take_str_arr(rest : Map[String, Json], key : String) -> Array[String]? {
  take_arr(rest, key, j => {
    match j {
      String(s) => Some(s)
      _ => None
    }
  })
}

///|
pub fn put_str(o : Map[String, Json], key : String, v : String?) -> Unit {
  if v is Some(s) {
    o[key] = Json::string(s)
  }
}

///|
pub fn put_bool(o : Map[String, Json], key : String, v : Bool?) -> Unit {
  if v is Some(b) {
    o[key] = Json::boolean(b)
  }
}

///|
pub fn put_int(o : Map[String, Json], key : String, v : Int?) -> Unit {
  if v is Some(i) {
    o[key] = Json::number(i.to_double())
  }
}

///|
pub fn put_int64(o : Map[String, Json], key : String, v : Int64?) -> Unit {
  if v is Some(i) {
    o[key] = Json::number(i.to_double())
  }
}

///|
pub fn put_json(o : Map[String, Json], key : String, v : Json?) -> Unit {
  if v is Some(j) {
    o[key] = j
  }
}

///|
pub fn[T] put_obj(
  o : Map[String, Json],
  key : String,
  v : T?,
  encode : (T) -> Json,
) -> Unit {
  if v is Some(x) {
    o[key] = encode(x)
  }
}

///|
/// Write an array, omitting it entirely when absent.
///
/// An EMPTY array is written, not omitted: Slack distinguishes "no such field"
/// from "an empty one" -- see the `blocks: []` case in @api's form encoder --
/// and so must a round trip.
pub fn[T] put_arr(
  o : Map[String, Json],
  key : String,
  v : Array[T]?,
  encode : (T) -> Json,
) -> Unit {
  if v is Some(items) {
    o[key] = Json::array(items.map(encode))
  }
}

///|
pub fn put_str_arr(
  o : Map[String, Json],
  key : String,
  v : Array[String]?,
) -> Unit {
  put_arr(o, key, v, Json::string)
}

///|
/// Merge the unmodelled fields back in.
///
/// Modelled fields win on a collision, which can only happen if a caller edited
/// `extra` by hand to shadow one -- in which case the typed field is the one
/// they can see in their editor and the one they meant.
pub fn merge_extra(o : Map[String, Json], extra : Map[String, Json]) -> Json {
  for key, value in extra {
    if !o.contains(key) {
      o[key] = value
    }
  }
  Json::object(o)
}
