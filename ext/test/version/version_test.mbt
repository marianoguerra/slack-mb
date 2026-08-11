// The version, in the six places it lives, against the one that decides it.
//
// `slack/moon.mod` is the source of truth -- it is what mooncakes publishes
// under -- and the other five have to agree with it. Five of the six are import
// constraints or module versions, where disagreeing breaks resolution loudly.
// The sixth is `@api.user_agent`, which hardcodes the version in a string, and
// that one fails SILENTLY: nothing resolves against it, so a release that
// forgets it ships a library telling Slack it is a version it is not, for as
// long as nobody looks.
//
// It went unnoticed through 0.1.0 and 0.2.0 for exactly that reason. This is
// the check that would have caught it.

///|
/// Every file that carries the version, and how to find it there.
///
/// Adding a seventh site means adding it here, which is the point: the list in
/// README's "Releasing" section is prose and this one is executable.
struct Site {
  file : String
  /// The text immediately before the version.
  after : String
  /// What names this site in a failure message.
  what : String
}

///|
let sites : Array[Site] = [
  {
    file: "slack/api/request.mbt",
    after: "pub let user_agent : String = \"MoonBit-Slack-SDK; marianoguerra/slack/",
    what: "@api.user_agent",
  },
  {
    file: "http/moon.mod",
    after: "version = \"",
    what: "http/moon.mod version",
  },
  {
    file: "http/moon.mod",
    after: "\"marianoguerra/slack@",
    what: "http/moon.mod's marianoguerra/slack constraint",
  },
  { file: "ext/moon.mod", after: "version = \"", what: "ext/moon.mod version" },
  {
    file: "ext/moon.mod",
    after: "\"marianoguerra/slack@",
    what: "ext/moon.mod's marianoguerra/slack constraint",
  },
  {
    file: "ext/moon.mod",
    after: "\"marianoguerra/slack-http@",
    what: "ext/moon.mod's marianoguerra/slack-http constraint",
  },
]

///|
/// The published version: `slack/moon.mod`'s, which mooncakes goes by.
test "every version site agrees with slack/moon.mod" {
  let published = version_after(
    read_repo_file("slack/moon.mod"),
    "version = \"",
    "slack/moon.mod",
  )
  // A sanity check on the scrape itself, so a parse that silently found "" or
  // a stray match cannot make the rest of this vacuous.
  assert_eq(
    published.split(".").collect().length(),
    3,
    msg="slack/moon.mod's version does not look like one: '\{published}'",
  )
  let disagree = []
  for site in sites {
    let found = version_after(read_repo_file(site.file), site.after, site.what)
    if found != published {
      disagree.push(
        "\{site.what} says \{found}, slack/moon.mod says \{published}",
      )
    }
  }
  assert_eq(
    disagree,
    [],
    msg="version sites out of step: \{disagree.join("; ")}",
  )
}

///|
/// The one that fails silently, stated on its own so the failure names it.
///
/// `@api.user_agent` reaches Slack on every single request. Nothing resolves
/// against it and no other test compares it to anything, so a stale one is
/// invisible until someone reads a support ticket.
test "the user agent reports the version this library actually is" {
  let published = version_after(
    read_repo_file("slack/moon.mod"),
    "version = \"",
    "slack/moon.mod",
  )
  assert_eq(
    @api.user_agent,
    "MoonBit-Slack-SDK; marianoguerra/slack/\{published}",
    msg="slack/api/request.mbt was not bumped with slack/moon.mod",
  )
}

///|
/// The version following a marker, up to the closing quote.
fn version_after(text : String, after : String, what : String) -> String raise {
  guard text.find(after) is Some(at) else {
    fail("\{what}: could not find '\{after}'")
  }
  let rest = text[at + after.length():].to_owned()
  guard rest.split_once("\"") is Some((version, _)) else {
    fail("\{what}: no closing quote after '\{after}'")
  }
  version.to_owned()
}

///|
/// Probing for the repo root, for the reason `@fixtures.fixtures_root` does:
/// `moon test` covers the whole workspace from any directory, so a fixed
/// relative path would be green in one place and red in another.
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
