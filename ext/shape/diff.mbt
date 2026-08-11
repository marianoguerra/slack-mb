// Comparing two payloads by shape rather than by value.
//
// The rule that makes a mock comparable against a real server at all: ids,
// timestamps and URLs will never match, so compare the STRUCTURE -- which keys
// exist, at which JSON type -- and compare values only where the caller chose
// them.
//
// The same walk serves both conformance checks. ext/test/mockrun runs it
// against a recording of a real run; ext/test/mockshape runs it against the
// vendored corpus. Having one implementation means a tolerance added for one
// is a tolerance the other gets too, which is the point: two nearly-identical
// comparators would drift.

///|
/// Paths in `actual` that `expected` does not have, or has at another type.
///
/// One direction only. Run it both ways round when both sides are supposed to
/// be complete; run it one way when `expected` is a UNION of every observed
/// shape and `actual` is one real response, which is the corpus case.
///
/// `skip_keys` names keys whose SUBTREE is not descended into -- the key itself
/// must still exist on both sides, but what is inside it is somebody else's
/// problem. `["blocks"]` is the one use: Block Kit is held to a far stronger
/// property elsewhere (`ext/test/corpus` round-trips 2,548 real blocks, and
/// ext/test/mockshape round-trips every block the mock emits), and the per-method
/// samples are a poor oracle for it. `conversations.history`'s sample happens to
/// contain exactly one block -- an `actions` block -- so its union asserts that
/// `elements[].text` is always an object, which is true of a button and false of
/// the context element right next to it in any real message.
///
/// Empty means they agree.
pub fn shape_diff(
  actual : Json,
  expected : Json,
  path : String,
  skip_keys? : Array[String] = [],
) -> Array[String] {
  let out : Array[String] = []
  walk(
    actual,
    expected,
    if path.is_empty() {
      "$"
    } else {
      path
    },
    out,
    skip_keys,
  )
  out
}

///|
fn walk(
  actual : Json,
  expected : Json,
  path : String,
  out : Array[String],
  skip_keys : Array[String],
) -> Unit {
  // A null on either side matches anything. The scrubber writes some fields to
  // null, and Slack sends null where a value is genuinely absent rather than
  // omitting the key.
  if actual is Null || expected is Null {
    return
  }
  match (actual, expected) {
    (Object(a), Object(b)) => {
      // An EMPTY reference object says nothing about what belongs inside it,
      // exactly as an empty reference array says nothing about its element
      // type. The samples have several: `views.open`'s `view.state` is `{}`
      // because its real contents are a map of block id to action id to value,
      // and the scrubber that built the corpus had no placeholder for that.
      // Reading `{}` as "this object has no fields" would forbid the very
      // thing the field exists to carry.
      guard !b.is_empty() else { return }
      for key, value in a {
        match b.get(key) {
          Some(other) =>
            if !skip_keys.contains(key) {
              walk(value, other, "\{path}.\{key}", out, skip_keys)
            }
          None => out.push("\{path}.\{key}")
        }
      }
    }
    (Array(a), Array(b)) => {
      // The reference side holds one type-representative element that is the
      // union of everything ever observed, so every element of `actual` is
      // compared against that union rather than pairwise by index. An empty
      // reference array says nothing about the element type and passes.
      guard !b.is_empty() else { return }
      let union = fold_union(b)
      for item in a {
        walk(item, union, "\{path}[]", out, skip_keys)
      }
    }
    (String(_), String(_)) => ()
    (Number(_), Number(_)) => ()
    (True, True) | (True, False) | (False, True) | (False, False) => ()
    // A string against a number, in either direction, is a WARNING rather than
    // a mismatch, and this walk reports neither. The corpus genuinely carries
    // `"thumb_64_w": ""` -- a width, as an empty string -- because the scrubber
    // that produced it did not know the field was numeric. Treating that as a
    // failure would make the check unusable; ext/test/mockshape counts them
    // separately with `type_warnings`.
    (String(_), Number(_)) | (Number(_), String(_)) => ()
    _ => out.push("\{path} (type)")
  }
}

///|
/// Fold every element of a reference array into one value carrying the union of
/// their keys.
///
/// Objects merge key-wise and recursively; anything else takes the first
/// element, because there is nothing to merge.
fn fold_union(items : Array[Json]) -> Json {
  let mut merged = items[0]
  for i in 1..<items.length() {
    merged = merge(merged, items[i])
  }
  merged
}

///|
fn merge(a : Json, b : Json) -> Json {
  match (a, b) {
    (Object(x), Object(y)) => {
      let out : Map[String, Json] = Map([])
      for key, value in x {
        out[key] = value
      }
      for key, value in y {
        out[key] = match out.get(key) {
          Some(existing) => merge(existing, value)
          None => value
        }
      }
      Json::object(out)
    }
    (Array(x), Array(y)) => {
      let items : Array[Json] = []
      for item in x {
        items.push(item)
      }
      for item in y {
        items.push(item)
      }
      if items.is_empty() {
        Json::array([])
      } else {
        Json::array([fold_union(items)])
      }
    }
    // A null on one side loses to a real value on the other: the union should
    // describe the type when anything ever carried one.
    (Null, other) => other
    (other, Null) => other
    // Two DIFFERENT types at the same path, which is not a corruption of the
    // sample -- it is what a heterogeneous array really contains. A block's
    // `elements` array holds context elements, where `text` is a string, and
    // button elements, where `text` is a `{type, text}` object. Folding them
    // has to admit both.
    //
    // `null` is how that is said: the walk above treats a null on either side
    // as matching anything, so a path the union has seen at two types makes no
    // claim about type. Picking the first would fail every payload that
    // happened to use the other one.
    (x, y) => if same_kind(x, y) { x } else { Json::null() }
  }
}

///|
/// Whether two scalars are the same JSON type. `true` and `false` are one type.
fn same_kind(a : Json, b : Json) -> Bool {
  match (a, b) {
    (String(_), String(_)) => true
    (Number(_), Number(_)) => true
    (True, True) | (True, False) | (False, True) | (False, False) => true
    _ => false
  }
}

///|
/// Every leaf path in a payload. The denominator of the coverage report in
/// ext/test/mockshape.
pub fn leaf_paths(value : Json, path : String) -> Array[String] {
  let out : Array[String] = []
  collect_leaves(value, if path.is_empty() { "$" } else { path }, out)
  out
}

///|
fn collect_leaves(value : Json, path : String, out : Array[String]) -> Unit {
  match value {
    Object(fields) =>
      if fields.is_empty() {
        out.push(path)
      } else {
        for key, field in fields {
          collect_leaves(field, "\{path}.\{key}", out)
        }
      }
    Array(items) =>
      if items.is_empty() {
        out.push(path)
      } else {
        collect_leaves(fold_union(items), "\{path}[]", out)
      }
    _ => out.push(path)
  }
}

///|
/// Read a dotted path out of a payload. `$.message.text`, `$.args.plain`.
///
/// `$` is the root. A path that does not exist yields `None`, which compares
/// equal to another `None` -- so a path neither side has is agreement, not a
/// failure.
pub fn at_path(value : Json, path : String) -> Json? {
  let mut here = value
  for segment in path.split(".") {
    let key = segment.to_owned()
    if key == "$" || key.is_empty() {
      continue
    }
    guard here is Object(fields) else { return None }
    guard fields.get(key) is Some(next) else { return None }
    here = next
  }
  Some(here)
}

///|
/// The paths whose VALUES must match between a real run and a mock one.
///
/// Everything the scenario itself chose, and nothing else. A real workspace and
/// `demo()` hold different people in differently named channels, so byte
/// equality across the whole payload is unachievable and chasing it would
/// produce a golden that had to be re-recorded weekly. These are the values a
/// mock that got them wrong is simply wrong about.
pub let compared_paths : Array[String] = [
  "$.ok", "$.error", "$.needed", "$.message.text", "$.message.type", "$.message.blocks",
  "$.message.subtype", "$.args.plain", "$.args.accented", "$.args.ampersand", "$.args.plus",
  "$.args.astral", "$.args.quotes", "$.args.slashes", "$.args.percent", "$.args.newline",
]
