// Generates slack/model/generated_model.mbt from ext/metadata/model.json.
//
// One struct per Slack entity, plus the `from_json` and `to_json` that carry
// the take-and-remove discipline @jsonx documents. 331 fields is too many to
// hand-write and far too many to keep in step with the corpus by hand, which is
// the same argument that made the method table generated.
//
// Run it through ext/scripts/gen.sh, which redirects stdout and reformats;
// `gen.sh --check` fails CI when the checked-in file has drifted.

///|
/// Where the model metadata lives, relative to the repo root and to ext/.
///
/// Two candidates because `moon run` resolves relative paths against the
/// directory it was invoked from, and this is invoked from both.
let metadata_candidates : Array[String] = [
  "ext/metadata/model.json", "metadata/model.json",
]

///|
fn read_metadata() -> String raise {
  for path in metadata_candidates {
    if @fs.path_exists(path) {
      return @fs.read_file_to_string(path)
    }
  }
  fail(
    "could not find model.json; looked for \{metadata_candidates.join(", ")} relative to the current directory",
  )
}

///|
/// A field, as the metadata describes it and as the generated code needs it.
struct Field {
  /// The JSON key Slack sends.
  key : String
  /// The MoonBit identifier, which differs when the key is a keyword.
  ident : String
  /// One of the `type` values model.json is allowed to use.
  kind : String
}

///|
/// MoonBit keywords that Slack also uses as field names.
///
/// Only `type` today, on `Message` and `View`. The convention is @client's:
/// a trailing underscore, as in `bookmarks_add(type_=...)`.
fn mangle(key : String) -> String {
  match key {
    "type" => "type_"
    "trait" => "trait_"
    "enum" => "enum_"
    "struct" => "struct_"
    "match" => "match_"
    "fn" => "fn_"
    "let" => "let_"
    "mut" => "mut_"
    "loop" => "loop_"
    "test" => "test_"
    "raise" => "raise_"
    "guard" => "guard_"
    "async" => "async_"
    other => other
  }
}

///|
/// The MoonBit type a metadata `type` maps to, always optional.
fn field_type(kind : String) -> String raise {
  match kind {
    "str" => "String?"
    "bool" => "Bool?"
    "int" => "Int?"
    "int64" => "Int64?"
    "str[]" => "Array[String]?"
    "blocks" => "Array[@blocks.LayoutBlock]?"
    "text" => "@blocks.TextObject?"
    other =>
      if other.has_prefix("obj:") {
        "\{other[4:].to_owned()}?"
      } else if other.has_prefix("arr:") {
        "Array[\{other[4:].to_owned()}]?"
      } else {
        fail("unknown field type in model.json: '\{other}'")
      }
  }
}

///|
/// The call that TAKES a field out of the remaining object.
///
/// Every one of these removes the key on success and leaves it alone on
/// failure, which is what puts an unexpected type into `extra` instead of
/// dropping it. `take_blocks` and `take_text` are the two hand-written ones,
/// in slack/model/parse.mbt.
fn take_call(f : Field) -> String raise {
  match f.kind {
    "str" => "@jsonx.take_str(rest, \{quote(f.key)})"
    "bool" => "@jsonx.take_bool(rest, \{quote(f.key)})"
    "int" => "@jsonx.take_int(rest, \{quote(f.key)})"
    "int64" => "@jsonx.take_int64(rest, \{quote(f.key)})"
    "str[]" => "@jsonx.take_str_arr(rest, \{quote(f.key)})"
    "blocks" => "take_blocks(rest, \{quote(f.key)})"
    "text" => "take_text(rest, \{quote(f.key)})"
    other =>
      if other.has_prefix("obj:") {
        let entity = other[4:].to_owned()
        "@jsonx.take_obj(rest, \{quote(f.key)}, \{entity}::from_json)"
      } else if other.has_prefix("arr:") {
        let entity = other[4:].to_owned()
        "@jsonx.take_arr(rest, \{quote(f.key)}, \{entity}::from_json)"
      } else {
        fail("unknown field type in model.json: '\{other}'")
      }
  }
}

///|
/// The call that writes a field back.
fn put_call(f : Field) -> String raise {
  match f.kind {
    "str" => "@jsonx.put_str(o, \{quote(f.key)}, self.\{f.ident})"
    "bool" => "@jsonx.put_bool(o, \{quote(f.key)}, self.\{f.ident})"
    "int" => "@jsonx.put_int(o, \{quote(f.key)}, self.\{f.ident})"
    "int64" => "@jsonx.put_int64(o, \{quote(f.key)}, self.\{f.ident})"
    "str[]" => "@jsonx.put_str_arr(o, \{quote(f.key)}, self.\{f.ident})"
    "blocks" =>
      "@jsonx.put_obj(o, \{quote(f.key)}, self.\{f.ident}, @blocks.blocks_to_json)"
    "text" =>
      "@jsonx.put_obj(o, \{quote(f.key)}, self.\{f.ident}, @blocks.TextObject::to_json)"
    other =>
      if other.has_prefix("obj:") {
        let entity = other[4:].to_owned()
        "@jsonx.put_obj(o, \{quote(f.key)}, self.\{f.ident}, \{entity}::to_json)"
      } else if other.has_prefix("arr:") {
        let entity = other[4:].to_owned()
        "@jsonx.put_arr(o, \{quote(f.key)}, self.\{f.ident}, \{entity}::to_json)"
      } else {
        fail("unknown field type in model.json: '\{other}'")
      }
  }
}

///|
/// Break a space-separated line so the doc comment stays inside 80 columns.
///
/// `moon fmt` reflows code but not comments, so an entity observed at seven
/// paths would otherwise emit a line nothing can read.
fn wrap(text : String, width : Int) -> Array[String] {
  let lines = []
  let line = StringBuilder::new()
  let mut length = 0
  for word in text.split(" ") {
    let word = word.to_owned()
    if length > 0 && length + 1 + word.length() > width {
      lines.push(line.to_string())
      line.reset()
      length = 0
    }
    if length > 0 {
      line.write_string(" ")
      length = length + 1
    }
    line.write_string(word)
    length = length + word.length()
  }
  if length > 0 {
    lines.push(line.to_string())
  }
  lines
}

///|
/// Slack's field names and entity names are `[A-Za-z0-9_.$]` today, so this
/// only has to survive that -- and a name that needed escaping would produce a
/// file that does not compile, which is a loud enough failure.
fn quote(s : String) -> String {
  "\"" + s + "\""
}

///|
fn str_field(
  o : Map[String, Json],
  key : String,
  whose : String,
) -> String raise {
  guard o.get(key) is Some(String(s)) else {
    fail("\{whose}: '\{key}' is missing or not a string")
  }
  s
}

///|
fn main {
  let generated = generate() catch {
    e => {
      println("gen_model failed: \{e}")
      panic()
    }
  }
  println(generated)
}

///|
fn generate() -> String raise {
  let json = @json.parse(read_metadata())
  guard json is Object(root) else { fail("model.json is not a JSON object") }
  guard root.get("entities") is Some(Array(entities)) else {
    fail("model.json has no 'entities' array")
  }
  let out = StringBuilder::new()
  out.write_string(
    (
      #|// Generated by ext/tools/gen_model from ext/metadata/model.json.
      #|// DO NOT EDIT. Run `just gen` to regenerate; CI fails when this drifts.
      #|//
      #|// One struct per Slack entity, each with the `extra` that holds every field
      #|// this version does not model. Parsing is total in the sense @jsonx
      #|// describes: a field of an unexpected type is never taken, so it stays in
      #|// `extra` and comes back out of `to_json` unchanged. `ext/test/modelcorpus`
      #|// holds that property against every occurrence in the reference corpus.
      #|//
      #|// Which fields exist here, and at which type, is a fact about
      #|// ext/fixtures/java -- not a reading of Slack's documentation. Each struct
      #|// says where in the corpus it was observed.
      #|
    ),
  )
  for entity in entities {
    guard entity is Object(e) else { fail("an entity is not an object") }
    let name = str_field(e, "name", "entity")
    let doc = str_field(e, "doc", name)
    let id_rule = str_field(e, "id", name)
    guard e.get("paths") is Some(Array(paths)) else {
      fail("\{name}: no 'paths' array")
    }
    guard e.get("fields") is Some(Array(raw_fields)) else {
      fail("\{name}: no 'fields' array")
    }
    let fields = []
    for raw in raw_fields {
      guard raw is Object(f) else { fail("\{name}: a field is not an object") }
      let key = str_field(f, "name", name)
      fields.push({ key, ident: mangle(key), kind: str_field(f, "type", name) })
    }
    let where_ = []
    for p in paths {
      guard p is String(s) else { fail("\{name}: a path is not a string") }
      where_.push(s)
    }
    let has_id = id_rule == "required"
    if id_rule != "required" && id_rule != "none" {
      fail("\{name}: 'id' must be \"required\" or \"none\", not '\{id_rule}'")
    }

    // The struct.
    out.write_string("\n///|\n/// \{doc}\n///\n")
    out.write_string(
      "/// Anything Slack sends that is not below is in `extra`. Observed in the\n",
    )
    out.write_string("/// reference corpus at:\n")
    for line in wrap("\{where_.join(", ")}", 68) {
      out.write_string("/// \{line}\n")
    }
    out.write_string("pub(all) struct \{name} {\n")
    if has_id {
      out.write_string(
        "  /// Always sent, on every occurrence in the corpus. A payload without\n" +
        "  /// one is not this entity, and `from_json` answers `None`.\n",
      )
      out.write_string("  id : String\n")
    }
    for f in fields {
      out.write_string("  \{f.ident} : \{field_type(f.kind)}\n")
    }
    out.write_string(
      "  /// Every field this version does not model, verbatim.\n",
    )
    out.write_string("  extra : Map[String, Json]\n")
    out.write_string("} derive(Eq, @debug.Debug)\n")

    // from_json.
    out.write_string("\n///|\n")
    out.write_string("/// `None` when the value is not an object")
    if has_id {
      out.write_string(", or has no string `id`")
    }
    out.write_string(".\n")
    out.write_string("pub fn \{name}::from_json(json : Json) -> \{name}? {\n")
    out.write_string("  guard json is Object(o) else { return None }\n")
    out.write_string("  let rest = @jsonx.fields_of(o)\n")
    if has_id {
      out.write_string(
        "  guard @jsonx.take_str(rest, \"id\") is Some(id) else { return None }\n",
      )
    }
    for f in fields {
      out.write_string("  let \{f.ident} = \{take_call(f)}\n")
    }
    out.write_string("  Some({\n")
    if has_id {
      out.write_string("    id,\n")
    }
    for f in fields {
      out.write_string("    \{f.ident},\n")
    }
    out.write_string("    extra: rest,\n")
    out.write_string("  })\n}\n")

    // to_json.
    out.write_string("\n///|\n")
    out.write_string("pub fn \{name}::to_json(self : \{name}) -> Json {\n")
    out.write_string("  let o : Map[String, Json] = Map([])\n")
    if has_id {
      out.write_string("  o[\"id\"] = Json::string(self.id)\n")
    }
    for f in fields {
      out.write_string("  \{put_call(f)}\n")
    }
    out.write_string("  @jsonx.merge_extra(o, self.extra)\n}\n")
  }
  out.to_string()
}
