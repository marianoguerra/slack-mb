// Reading and writing Block Kit JSON without losing anything.
//
// Every `from_json` in this package works the same way: copy the object, take
// the fields it models -- which REMOVES them -- and keep whatever is left in
// `extra`. `to_json` writes the modelled fields back and then merges `extra`.
//
// The take-and-remove shape is what makes the round-trip property hold. A
// parser that instead listed its known keys and treated the rest as extra would
// silently drop any known key whose value had an unexpected type; here a field
// that fails to parse is simply never taken, so it stays in `extra` and comes
// back out unchanged. That matters more than it sounds: java-slack-sdk's
// fixture corpus scrubs values to type-representative placeholders and merges
// every observed shape of a block into one object, so fields routinely appear
// with the "wrong" type or on a block that has no business carrying them.

///|
/// A mutable copy of an object's fields, to take from.
fn fields_of(o : Map[String, Json]) -> Map[String, Json] {
  o.copy()
}

///|
fn take_str(rest : Map[String, Json], key : String) -> String? {
  match rest.get(key) {
    Some(String(s)) => {
      rest.remove(key)
      Some(s)
    }
    _ => None
  }
}

///|
fn take_bool(rest : Map[String, Json], key : String) -> Bool? {
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
fn take_int(rest : Map[String, Json], key : String) -> Int? {
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
fn take_json(rest : Map[String, Json], key : String) -> Json? {
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
fn[T] take_obj(
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
fn[T] take_arr(
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
fn take_str_arr(rest : Map[String, Json], key : String) -> Array[String]? {
  take_arr(rest, key, j => {
    match j {
      String(s) => Some(s)
      _ => None
    }
  })
}

///|
/// Start an output object with its `type` tag.
fn out_of(type_ : String) -> Map[String, Json] {
  let o : Map[String, Json] = Map([])
  o["type"] = Json::string(type_)
  o
}

///|
fn put_str(o : Map[String, Json], key : String, v : String?) -> Unit {
  if v is Some(s) {
    o[key] = Json::string(s)
  }
}

///|
fn put_bool(o : Map[String, Json], key : String, v : Bool?) -> Unit {
  if v is Some(b) {
    o[key] = Json::boolean(b)
  }
}

///|
fn put_int(o : Map[String, Json], key : String, v : Int?) -> Unit {
  if v is Some(i) {
    o[key] = Json::number(i.to_double())
  }
}

///|
fn put_json(o : Map[String, Json], key : String, v : Json?) -> Unit {
  if v is Some(j) {
    o[key] = j
  }
}

///|
fn[T] put_obj(
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
fn[T] put_arr(
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
fn put_str_arr(o : Map[String, Json], key : String, v : Array[String]?) -> Unit {
  put_arr(o, key, v, Json::string)
}

///|
/// Merge the unmodelled fields back in.
///
/// Modelled fields win on a collision, which can only happen if a caller edited
/// `extra` by hand to shadow one -- in which case the typed field is the one
/// they can see in their editor and the one they meant.
fn merge_extra(o : Map[String, Json], extra : Map[String, Json]) -> Json {
  for key, value in extra {
    if !o.contains(key) {
      o[key] = value
    }
  }
  Json::object(o)
}
