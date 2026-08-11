// The mock's output, against the shapes Slack was recorded producing.

///|
/// Fields the mock emits that its method's recorded sample does not have.
///
/// Every entry here is the check being switched off for one path, so every
/// entry carries the reason it is not a mock bug. The list should stay short:
/// its growth is the signal that the corpus has aged, not that the rule is
/// wrong.
///
/// The three below are all the same kind of thing -- java-slack-sdk's samples
/// are unions of what its maintainers happened to record, and a method they
/// exercised on one kind of object does not carry the fields another kind has.
let allow_unknown : Map[String, Array[String]] = {
  // Recorded on a public channel, where there is no counterpart user. Slack
  // really does return `user` for a DM here; `conversations.list`'s own sample
  // has all three fields, on the same object.
  "conversations.info": [
    "$.channel.user", "$.channel.is_user_deleted", "$.channel.priority",
  ],
  // The sample's `message` has no `ts`, which cannot be right -- an updated
  // message has one, and `chat.postMessage`'s sample carries it. Scrubbed away
  // rather than absent, most likely.
  "chat.update": ["$.message.ts"],
  // The sample's `items` were recorded on FILE pins only, so it has `file` and
  // `comment` and no `message`. A pinned message is the far commoner case and
  // is what `pins.add` in the same corpus pins.
  "pins.list": ["$.items[].message", "$.items[].channel"],
  // `always_active` is on the profile in `users.info`, `users.list` AND
  // `users.profile.get`, and missing from these two samples. A gap in what was
  // recorded rather than a field Slack does not send -- the alternative is to
  // stop emitting it, which would lose it from the three methods that do
  // document it.
  "users.lookupByEmail": ["$.user.profile.always_active"],
  "users.profile.set": ["$.profile.always_active"],
  // The sample carries `ok` and the error branch and nothing else, so whoever
  // recorded it only ever saw this method fail. `revoked` is the documented
  // success field -- it is the entire point of calling `auth.revoke`, and it is
  // what `dry_run` reports without doing.
  "auth.revoke": ["$.revoked"],
}

///|
/// Keys that only ever appear on a REFUSAL.
///
/// The samples are unions of every observed response, so each one carries the
/// error branch as well as the success branch -- which is why every file in the
/// corpus has `"ok": false`. A successful answer never has these, and counting
/// them against the mock's coverage would penalise it for being correct.
let refusal_keys : Array[String] = [
  "error", "needed", "provided", "warning", "warnings", "arg", "callstack",
]

///|
/// The floor under how much of each method's recorded shape the mock covers.
///
/// Measured over the response's TOP-LEVEL keys, not over every leaf. Leaves are
/// the wrong denominator by a wide margin: `conversations.history`'s sample has
/// seven thousand of them, because it is the union of every message shape its
/// maintainers ever recorded -- every file variant, every attachment field,
/// every bot profile. No real response has more than a fraction of that, so a
/// leaf-based ratio would say the mock covers 2% of Slack while telling you
/// nothing about whether `conversations.history` answers with `messages`.
///
/// Top-level keys are the question worth asking: is the response MADE of the
/// right things. The leaf count is still printed, as information.
///
/// What this guards against is the whole check going hollow -- a mock that
/// answered `{"ok": true}` and nothing else would satisfy the unknown-field
/// assertion perfectly.
let coverage_floor : Double = 0.6

///|
/// Every method's answer, compared against its recorded sample.
test "every field the mock emits exists in the corpus, at the same type" {
  let ws = @mock.Workspace::demo()
  let probes = probe_all(ws)
  let mut compared = 0
  let mut skipped_large = 0
  for probe in probes {
    guard @fixtures.method_fixture(probe.api_method) is Some(fixture) else {
      fail(
        "no recorded fixture for \{probe.api_method}; ext/fixtures should have one for every typed method",
      )
    }
    // The eight biggest samples are gitignored. Skipping LOUDLY, because a
    // silent skip and a pass look identical in a CI log -- the same rule
    // ext/test/corpus_large follows.
    if fixture.tier == "large" && !@fixtures.tier_present("large") {
      skipped_large += 1
      continue
    }
    let reference = @fixtures.read_fixture(fixture)
    let unknown = @shape.shape_diff(probe.body, reference, "", skip_keys=[
      "blocks",
    ])
    let allowed = allow_unknown.get(probe.api_method).unwrap_or([])
    let unexpected = unknown.filter(path => !allowed.contains(path))
    assert_eq(
      unexpected,
      [],
      msg="\{probe.api_method} emits fields \{fixture.path} does not: \{unexpected.join(", ")}",
    )
    compared += 1
  }
  if skipped_large > 0 {
    println(
      "SKIP: \{skipped_large} large-tier methods went unchecked; run `just fixtures` to fetch them",
    )
  }
  // A guard against the loop quietly finding nothing, which is what a broken
  // `method_fixture` would look like.
  assert_true(compared >= 50, msg="only \{compared} methods were compared")
}

///|
/// How much of each recorded shape the mock actually fills in.
///
/// Reported rather than asserted per method, with one floor over the whole run:
/// see `coverage_floor`.
test "the mock covers a meaningful share of the recorded fields" {
  let ws = @mock.Workspace::demo()
  let probes = probe_all(ws)
  let mut emitted = 0
  let mut available = 0
  let mut leaves_emitted = 0
  let mut leaves_available = 0
  let thin : Array[String] = []
  for probe in probes {
    guard @fixtures.method_fixture(probe.api_method) is Some(fixture) else {
      continue
    }
    if fixture.tier == "large" && !@fixtures.tier_present("large") {
      continue
    }
    let reference = @fixtures.read_fixture(fixture)
    let mine = top_level_keys(probe.body)
    let theirs = top_level_keys(reference).filter(k => !refusal_keys.contains(k))
    let shared = theirs.filter(key => mine.contains(key))
    emitted += shared.length()
    available += theirs.length()
    leaves_emitted += @shape.leaf_paths(probe.body, "").length()
    leaves_available += @shape.leaf_paths(reference, "").length()
    // Named individually when a method is especially bare, so a regression in
    // one handler is legible rather than averaged away.
    if theirs.length() >= 3 &&
      shared.length().to_double() / theirs.length().to_double() < 0.6 {
      let absent = theirs.filter(key => !mine.contains(key))
      thin.push("\{probe.api_method} (no \{absent.join("/")})")
    }
  }
  println(
    "corpus coverage: \{emitted}/\{available} top-level response fields; \{leaves_emitted} leaves emitted against \{leaves_available} in the samples' unions",
  )
  if !thin.is_empty() {
    println("thinnest methods: \{thin.join(", ")}")
  }
  assert_true(available > 0, msg="no reference fields were read at all")
  assert_true(
    emitted.to_double() / available.to_double() >= coverage_floor,
    msg="the mock fills only \{emitted}/\{available} top-level fields, below the \{coverage_floor} floor",
  )
}

///|
/// The keys of a response object, ignoring what is nested inside them.
fn top_level_keys(value : Json) -> Array[String] {
  let out : Array[String] = []
  if value is Object(fields) {
    for key, _ in fields {
      out.push(key)
    }
  }
  out
}

///|
/// The round-trip property, applied to the mock's own output.
///
/// `ext/test/corpus` holds 2,548 real blocks to this. The mock is held to it
/// too, because a renderer that helpfully normalised what it was given -- sorted
/// keys, dropped a field it did not model -- would pass every other check here
/// and quietly break the one guarantee this library is built around.
test "every blocks array the mock emits round-trips byte for byte" {
  let ws = @mock.Workspace::demo()
  let probes = probe_all(ws)
  let mut checked = 0
  for probe in probes {
    for array in @fixtures.collect_block_arrays(probe.body) {
      guard @blocks.parse_blocks(array) is Some(parsed) else {
        fail("\{probe.api_method}: a blocks array did not parse")
      }
      assert_eq(
        @blocks.blocks_to_json(parsed),
        array,
        msg="\{probe.api_method}: a blocks array did not round-trip",
      )
      // Nothing may land in `Unknown`: these blocks came out of @blocks in the
      // first place, so one that no longer parses means the model regressed.
      for block in parsed {
        if block is Unknown(type_=t, ..) {
          fail(
            "\{probe.api_method}: the mock emitted an unmodelled block '\{t}'",
          )
        }
      }
      checked += parsed.length()
    }
  }
  // The floor guards against the probes quietly ceasing to send blocks, which
  // would make this test pass by finding nothing.
  assert_true(checked >= 8, msg="only \{checked} blocks were round-tripped")
}

///|
/// The drift gate: the mock's handler list against the client's typed methods.
///
/// Both inputs are generated files, committed, and already CI-gated for
/// freshness (`just info-check` and `just gen-check`), which is what makes
/// reading them safe -- the same argument `ext/test/coverage` makes for reading
/// `ext/metadata/*.txt`.
///
/// Adding a typed method to `@client` then fails this test until a handler
/// exists in `@mock`, which is the whole point: a mock that silently lags the
/// client is a mock that passes tests it should fail.
test "the mock implements exactly the client's typed methods" {
  let wire = method_constants()
  let expected : Array[String] = []
  for name in typed_client_methods() {
    guard wire.get(name) is Some(api_method) else {
      fail(
        "Client::\{name} has no matching constant in slack/methods/generated_methods.mbt",
      )
    }
    if !expected.contains(api_method) {
      expected.push(api_method)
    }
  }
  expected.sort()
  let actual = @mock.implemented_methods.copy()
  actual.sort()
  let missing = expected.filter(m => !actual.contains(m))
  let extra = actual.filter(m => !expected.contains(m))
  assert_eq(
    missing,
    [],
    msg="@client has typed methods the mock does not implement: \{missing.join(", ")}",
  )
  assert_eq(
    extra,
    [],
    msg="the mock implements methods @client has no typed call for: \{extra.join(", ")}",
  )
  assert_true(
    expected.length() >= 60,
    msg="only \{expected.length()} methods found; the scrape probably broke",
  )
}

///|
/// The typed methods on `Client`, from its generated interface.
///
/// Drops the three generic entry points and the `_all` paginating wrappers,
/// which are conveniences over a method rather than methods of their own.
fn typed_client_methods() -> Array[String] raise {
  let text = read_repo_file("slack/client/pkg.generated.mbti")
  let names : Array[String] = []
  for line in text.split("\n") {
    let line = line.to_owned()
    guard line.has_prefix("pub async fn Client::") else { continue }
    let rest = line["pub async fn Client::".length():].to_owned()
    guard rest.split_once("(") is Some((name, _)) else { continue }
    let name = name.to_owned()
    if ["call", "paginate", "paginate_collect"].contains(name) {
      continue
    }
    if name.has_suffix("_all") {
      continue
    }
    names.push(name)
  }
  names
}

///|
/// `snake_name -> "wire.name"`, from the generated method table.
///
/// No snake-casing logic here on purpose: the generator already decided how
/// each wire name spells itself, and a second rule would disagree with it the
/// first time Slack ships a method with an unusual name.
fn method_constants() -> Map[String, String] raise {
  let text = read_repo_file("slack/methods/generated_methods.mbt")
  let out : Map[String, String] = Map([])
  for line in text.split("\n") {
    let line = line.to_owned()
    guard line.has_prefix("pub let ") else { continue }
    guard line.split_once(" : String = \"") is Some((head, tail)) else {
      continue
    }
    let name = head.to_owned()["pub let ".length():].to_owned()
    guard tail.to_owned().split_once("\"") is Some((wire, _)) else { continue }
    out[name] = wire.to_owned()
  }
  out
}

///|
/// Read a file by its path from the repository root.
///
/// Probing for the root, for the reason `@fixtures.fixtures_root` does: `moon
/// test` covers the whole workspace from any directory, so a fixed relative
/// path would be green in one place and red in another.
fn read_repo_file(relative : String) -> String raise {
  for prefix in ["", "../", "../../"] {
    let path = prefix + relative
    if @fs.path_exists(path) {
      return @fs.read_file_to_string(path) catch {
        _ => fail("could not read \{path}")
      }
    }
  }
  fail("could not find \{relative} from the working directory")
}
