// @model against the payloads it was derived from.
//
// Same argument as ext/test/corpus, which does this for Block Kit: these are
// 565 responses nobody picked, recorded live by java-slack-sdk's maintainers,
// scrubbed to type-representative placeholders and merged so that each file is
// the union of every shape its method has been observed to return. A model
// tested against payloads its author wrote is a model tested against its
// author's beliefs.
//
// Three properties, in order of how much they would hurt to lose:
//
//   1. `to_json(from_json(x)) == x`. Nothing is dropped. Without this, `extra`
//      is a promise rather than a mechanism.
//   2. No modelled field is ever left in `extra`. If it is, the corpus is
//      sending a type model.json does not claim, and the field reads `None`
//      forever on a struct whose author believes it is there.
//   3. A coverage floor, so 1 and 2 cannot be satisfied by modelling nothing.
//
// Where each entity lives comes from ext/metadata/model.json rather than from a
// second copy here, so the metadata stays the single source of truth and an
// entity added there fails this test until it is registered below.

///|
/// An entity, reduced to the one thing the walk needs: parse a payload and
/// report both what it serialises back to and what it could not model.
///
/// `None` means the entity refused the payload, which for this corpus means
/// "not one of those" -- `$.channel` holding a string, a `$.user` with no `id`.
struct Entity {
  name : String
  parse : (Json) -> (Json, Map[String, Json])?
}

///|
/// The one place a new entity has to be registered by hand.
let entities : Array[Entity] = [
  {
    name: "User",
    parse: j => @model.User::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "Profile",
    parse: j => @model.Profile::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "Channel",
    parse: j => @model.Channel::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "ChannelText",
    parse: j => {
      @model.ChannelText::from_json(j).map(x => (x.to_json(), x.extra))
    },
  },
  {
    name: "Message",
    parse: j => @model.Message::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "Edited",
    parse: j => @model.Edited::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "Reaction",
    parse: j => @model.Reaction::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "BotProfile",
    parse: j => @model.BotProfile::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "Team",
    parse: j => @model.Team::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "Usergroup",
    parse: j => @model.Usergroup::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "View",
    parse: j => @model.View::from_json(j).map(x => (x.to_json(), x.extra)),
  },
  {
    name: "File",
    parse: j => @model.File::from_json(j).map(x => (x.to_json(), x.extra)),
  },
]

///|
/// Modelled fields the corpus is allowed to send at another type, with the
/// reason each one is the corpus being odd rather than the metadata being
/// wrong.
///
/// Every entry is property 2 switched off for one field. The list should stay
/// short: its growth is the signal that the corpus has aged.
let allow_unmodelled : Map[String, Array[String]] = {
  // `purpose` is an object on 26 of the 27 occurrences that carry it, and a
  // bare string on one. Modelling the object is right, and the string case is
  // exactly what take-and-remove exists for: it stays in `extra` and
  // round-trips untouched.
  "Channel": ["purpose"],
}

///|
/// Where the metadata lives, from wherever `moon test` was invoked.
///
/// `moon test` runs the whole workspace from any directory, which is why this
/// probes instead of assuming -- the same reason @fixtures does.
fn model_metadata() -> Json raise {
  let candidates = [
    "ext/metadata/model.json", "metadata/model.json", "../metadata/model.json",
  ]
  for path in candidates {
    if @fs.path_exists(path) {
      return @json.parse(@fs.read_file_to_string(path))
    }
  }
  fail("could not find model.json from the test's working directory")
}

///|
/// Entity name -> the paths it was observed at, and the fields it models.
fn metadata_tables() -> (Map[String, Array[String]], Map[String, Array[String]]) raise {
  guard model_metadata() is Object(root) else {
    fail("model.json is not an object")
  }
  guard root.get("entities") is Some(Array(list)) else {
    fail("model.json has no entities")
  }
  let paths : Map[String, Array[String]] = Map([])
  let fields : Map[String, Array[String]] = Map([])
  for entry in list {
    guard entry is Object(e) else { fail("an entity is not an object") }
    guard e.get("name") is Some(String(name)) else {
      fail("an entity has no name")
    }
    let ps = []
    if e.get("paths") is Some(Array(items)) {
      for p in items {
        if p is String(s) {
          ps.push(s)
        }
      }
    }
    let fs = []
    if e.get("fields") is Some(Array(items)) {
      for f in items {
        if f is Object(fo) && fo.get("name") is Some(String(n)) {
          fs.push(n)
        }
      }
    }
    paths[name] = ps
    fields[name] = fs
  }
  (paths, fields)
}

///|
/// Glob match where `*` stands for any run of characters, dots included.
///
/// The semantics model.json's paths were written under. `*` spanning a dot is
/// deliberate: `$.*.bot_profile` means "a bot_profile anywhere below the root",
/// which is where the corpus puts them.
fn glob(pattern : String, path : String) -> Bool {
  fn go(p : Int, s : Int) -> Bool {
    if p == pattern.length() {
      return s == path.length()
    }
    if pattern[p] == '*' {
      for i = s; i <= path.length(); i = i + 1 {
        if go(p + 1, i) {
          return true
        }
      }
      return false
    }
    if s < path.length() && pattern[p] == path[s] {
      return go(p + 1, s + 1)
    }
    false
  }

  go(0, 0)
}

///|
/// Every object in a payload sitting at one of an entity's paths.
///
/// First match wins, in the order the metadata lists the entities, which is how
/// an object nested inside another is attributed once rather than twice.
fn occurrences(
  json : Json,
  paths : Map[String, Array[String]],
) -> Array[(String, Map[String, Json])] {
  let out = []
  fn walk(node : Json, path : String) -> Unit {
    match node {
      Object(o) => {
        for name, patterns in paths {
          let mut hit = false
          for pattern in patterns {
            if glob(pattern, path) {
              hit = true
              break
            }
          }
          if hit {
            out.push((name, o))
            break
          }
        }
        for key, value in o {
          walk(value, path + "." + key)
        }
      }
      Array(items) =>
        for item in items {
          walk(item, path + "[]")
        }
      _ => ()
    }
  }

  walk(json, "$")
  out
}

///|
fn parser_table() -> Map[String, (Json) -> (Json, Map[String, Json])?] {
  let table : Map[String, (Json) -> (Json, Map[String, Json])?] = Map([])
  for entity in entities {
    table[entity.name] = entity.parse
  }
  table
}

///|
/// Property 1, and the only one that cannot be recovered from after the fact.
test "every modelled entity in the corpus round-trips byte for byte" {
  let (paths, _) = metadata_tables()
  let parsers = parser_table()
  let mut checked = 0
  for fixture in @fixtures.fixtures("small") {
    let json = @fixtures.read_fixture(fixture)
    for hit in occurrences(json, paths) {
      let (name, o) = hit
      guard parsers.get(name) is Some(parse) else {
        fail("model.json has entity '\{name}' with no parser in this test")
      }
      let original = Json::object(o)
      if parse(original) is Some((back, _)) {
        checked = checked + 1
        assert_eq(back, original, msg="\{name} in \{fixture.path}")
      }
    }
  }
  println("model round trip: \{checked} entity occurrences in the small tier")
  // A floor, so a walk that silently stopped finding anything cannot pass.
  assert_true(
    checked > 250,
    msg="only \{checked} entity occurrences round-tripped; the walk is not finding them",
  )
}

///|
/// The same property over the 17 fixtures too large to commit.
///
/// This is where the depth is, and it is the tier that matters most to @model:
/// `conversations.history.json` and `chat.postMessage.json` are 2 MB each and
/// hold almost every `Message` the corpus has, nested three deep through
/// `root`, `attachments` and `files`.
///
/// Gitignored and fetched with `just fixtures`, so this SKIPS on a fresh clone
/// -- out loud, because a silent skip and a pass look identical in CI output.
test "every modelled entity in the large fixtures round-trips too" {
  if !@fixtures.tier_present("large") {
    println(
      "SKIP: the large fixtures are not on disk. Fetch them with `just fixtures` (ext/scripts/fetch-large-fixtures.sh).",
    )
    return
  }
  let (paths, _) = metadata_tables()
  let parsers = parser_table()
  let mut checked = 0
  for fixture in @fixtures.fixtures("large") {
    let json = @fixtures.read_fixture(fixture)
    for hit in occurrences(json, paths) {
      let (name, o) = hit
      guard parsers.get(name) is Some(parse) else { continue }
      let original = Json::object(o)
      if parse(original) is Some((back, _)) {
        checked = checked + 1
        assert_eq(back, original, msg="\{name} in \{fixture.path}")
      }
    }
  }
  println("model round trip: \{checked} entity occurrences in the large tier")
  // 327 at the time of vendoring, across the 12 large fixtures that carry an
  // entity at all.
  assert_true(
    checked > 300,
    msg="only \{checked} entity occurrences in the large tier; the walk is not finding them",
  )
}

///|
/// Property 2: a field model.json claims must never end up in `extra`.
///
/// This is the check that catches a corpus refresh in which Slack changed a
/// field's type. The parser would quietly stop taking it, the struct field
/// would read `None` forever, and property 1 would still pass.
test "no modelled field is left behind in extra" {
  let (paths, fields) = metadata_tables()
  let parsers = parser_table()
  let modelled : Map[String, Map[String, Bool]] = Map([])
  for name, list in fields {
    let set : Map[String, Bool] = Map([])
    for f in list {
      set[f] = true
    }
    modelled[name] = set
  }
  let complaints = []
  for fixture in @fixtures.fixtures("small") {
    let json = @fixtures.read_fixture(fixture)
    for hit in occurrences(json, paths) {
      let (name, o) = hit
      guard parsers.get(name) is Some(parse) else { continue }
      guard parse(Json::object(o)) is Some((_, extra)) else { continue }
      guard modelled.get(name) is Some(known) else { continue }
      let allowed = allow_unmodelled.get(name).unwrap_or([])
      for key, _ in extra {
        if known.get(key) is Some(_) && !allowed.contains(key) {
          complaints.push("\{name}.\{key} in \{fixture.path}")
        }
      }
    }
  }
  assert_eq(
    complaints.length(),
    0,
    msg="modelled fields the corpus sends at another type: \{complaints.join(", ")}",
  )
}

///|
/// Property 3: a floor on how much of each entity is actually modelled.
///
/// Without it, the two properties above are satisfiable by a struct with no
/// fields at all. 60% is where the current metadata comfortably sits; raising
/// the floor is a normal part of modelling more, lowering it needs a reason.
test "each entity models most of what the corpus sends it" {
  let (paths, fields) = metadata_tables()
  let observed : Map[String, Map[String, Bool]] = Map([])
  for fixture in @fixtures.fixtures("small") {
    let json = @fixtures.read_fixture(fixture)
    for hit in occurrences(json, paths) {
      let (name, o) = hit
      let set = match observed.get(name) {
        Some(s) => s
        None => {
          let s : Map[String, Bool] = Map([])
          observed[name] = s
          s
        }
      }
      for key, _ in o {
        set[key] = true
      }
    }
  }
  let report = []
  for entity in entities {
    let seen = observed.get(entity.name).map(s => s.length()).unwrap_or(0)
    let has = fields.get(entity.name).map(f => f.length()).unwrap_or(0)
    report.push("\{entity.name} \{has}/\{seen}")
    // `File` is the deliberate exception: 162 fields in the corpus, most of
    // them thumbnail dimensions in a dozen sizes. See model.json.
    if entity.name != "File" && seen > 0 {
      assert_true(
        has * 100 >= seen * 60,
        msg="\{entity.name} models \{has} of the \{seen} fields the corpus sends it",
      )
    }
  }
  println("model coverage (modelled/observed): \{report.join(", ")}")
}
