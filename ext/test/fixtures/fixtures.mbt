// Reading the vendored reference corpus.
//
// Shared by test/corpus and test/corpus_large, which differ only in which tier
// of MANIFEST.json they read.

///|
/// One entry from ext/fixtures/MANIFEST.json.
pub(all) struct Fixture {
  /// Relative to the fixtures root.
  path : String
  bytes : Int
  /// `"small"` (committed) or `"large"` (fetched on demand, gitignored).
  tier : String
} derive(Eq, Debug)

///|
/// The fixtures root, wherever `moon test` happened to be invoked from.
///
/// `moon test` covers the whole workspace from any directory, so a fixed path
/// would be green in one place and red in another. Probing is two syscalls and
/// removes the whole class of problem.
pub fn fixtures_root() -> String {
  for prefix in ["ext/fixtures/", "fixtures/", "../fixtures/"] {
    if @fs.path_exists(prefix + "MANIFEST.json") {
      return prefix
    }
  }
  abort(
    "could not find fixtures/MANIFEST.json; run ext/scripts/vendor-fixtures.sh",
  )
}

///|
/// Every fixture in a tier.
///
/// Read from the manifest rather than by walking directories: a fixture that
/// vanishes then becomes a test failure instead of silent zero coverage, which
/// is the failure mode that makes a corpus test worthless.
pub fn fixtures(tier : String) -> Array[Fixture] {
  let root = fixtures_root()
  let text = @fs.read_file_to_string(root + "MANIFEST.json") catch {
    _ => abort("could not read \{root}MANIFEST.json")
  }
  let json = @json.parse(text) catch {
    _ => abort("MANIFEST.json is not valid JSON")
  }
  guard json is Object(o) && o.get("files") is Some(Array(entries)) else {
    abort("MANIFEST.json has no files array")
  }
  let out = []
  for entry in entries {
    guard entry is Object(f) else { continue }
    guard f.get("path") is Some(String(path)) else { continue }
    guard f.get("tier") is Some(String(t)) && t == tier else { continue }
    let bytes = match f.get("bytes") {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
    out.push({ path, bytes, tier: t })
  }
  out
}

///|
pub fn read_fixture(fixture : Fixture) -> Json {
  let path = fixtures_root() + fixture.path
  let text = @fs.read_file_to_string(path) catch {
    _ => abort("could not read \{path}")
  }
  @json.parse(text) catch {
    _ => abort("\{fixture.path} is not valid JSON")
  }
}

///|
/// Whether a tier's files are actually on disk.
///
/// The 17 large fixtures are gitignored, so a fresh clone does not have them.
/// The large-corpus test skips rather than fails -- but says so, because a
/// silent skip and a pass look identical in CI output.
pub fn tier_present(tier : String) -> Bool {
  let root = fixtures_root()
  let list = fixtures(tier)
  list.length() > 0 && @fs.path_exists(root + list[0].path)
}

///|
/// Collect every `blocks` array anywhere in a payload, however deeply nested.
///
/// Blocks turn up in more places than the obvious one: inside `message`, inside
/// `attachments[].blocks`, inside `view`, inside each item of
/// `conversations.history`, inside the `previous_message` of a `message_changed`
/// event. Walking for them beats enumerating the paths, and the point of a
/// corpus test is to find the payloads nobody enumerated.
pub fn collect_block_arrays(j : Json) -> Array[Json] {
  let out = []
  walk(j, out)
  out
}

///|
fn walk(j : Json, out : Array[Json]) -> Unit {
  match j {
    Object(o) =>
      for key, value in o {
        if key == "blocks" && value is Array(_) {
          out.push(value)
        }
        walk(value, out)
      }
    Array(items) =>
      for item in items {
        walk(item, out)
      }
    _ => ()
  }
}

///|
/// The recorded reference response for one Web API method.
///
/// Looks in whichever tier it lives in: most are under `java/api/`, but the
/// eight biggest -- `chat.postMessage`, `conversations.history` and friends --
/// are under `java/api-large/` and are gitignored, so a caller has to be ready
/// for `tier == "large"` and `tier_present("large") == false`.
///
/// Matched on the file name rather than by joining a directory, so that a
/// re-vendor which moves a fixture between tiers needs no change here.
pub fn method_fixture(api_method : String) -> Fixture? {
  let wanted = "/" + api_method + ".json"
  for tier in ["small", "large"] {
    for fixture in fixtures(tier) {
      if fixture.path.has_suffix(wanted) {
        return Some(fixture)
      }
    }
  }
  None
}
