// A port of java-slack-sdk's `MethodsTest#verifyTheCoverage`.
//
// Upstream hard-codes the scraped method list as a 25 KB string literal inside
// the test. Here it is a text file in ext/metadata/, so refreshing the scrape
// is a one-file edit and the failure message can name what drifted instead of
// pointing at a diff in a Java source file.
//
// This is a normal test rather than a CI-only script on purpose: whether the
// library covers Slack's documented surface is a product question, and a
// product question should fail on a developer's machine too.

///|
/// Metadata paths, relative to the repo root and to ext/.
///
/// `moon test` covers the whole workspace from whichever directory it was
/// invoked in, so a test that reads a file cannot assume one of them. Probing
/// costs two `path_exists` calls and removes the entire class of "green here,
/// red in CI" that a fixed path would introduce.
fn metadata_path(name : String) -> String {
  for prefix in ["ext/metadata/", "metadata/", "../metadata/"] {
    let candidate = prefix + name
    if @fs.path_exists(candidate) {
      return candidate
    }
  }
  abort(
    "could not find \{name}; looked under ext/metadata/, metadata/ and ../metadata/ relative to the working directory",
  )
}

///|
fn lines_of(name : String) -> Array[String] {
  let text = @fs.read_file_to_string(metadata_path(name)) catch {
    _ => abort("could not read \{name}")
  }
  let out = []
  for line in text.split("\n") {
    let trimmed = line.trim().to_owned()
    if !trimmed.is_empty() {
      out.push(trimmed)
    }
  }
  out
}

///|
/// The methods this library is expected to know: everything Slack documents,
/// minus the families java-slack-sdk deliberately skips (Salesforce channels,
/// the automation-platform datastore and function-distribution APIs, the
/// session-token-only audit-anomaly endpoints, and assistant search).
fn expected_methods() -> Array[String] {
  let excluded = lines_of("excluded_methods.txt")
  let out = []
  for name in lines_of("documented_methods.txt") {
    if !excluded.contains(name) {
      out.push(name)
    }
  }
  out
}

///|
/// java-slack-sdk: `fail(method + " is not supported yet!")`.
test "every documented method has a constant" {
  let missing = []
  for name in expected_methods() {
    if !@methods.is_known(name) {
      missing.push(name)
    }
  }
  assert_eq(
    missing,
    [],
    msg="not supported yet: \{missing.join(", ")}. Refresh ext/metadata/rate_limit_tiers.json and run `just gen`.",
  )
}

///|
/// java-slack-sdk: `fail(method + "'s Rate Limit Tier is not added yet!")`.
///
/// A separate assertion from the one above because the two failures have
/// different fixes: a missing constant means the tier file is stale, while a
/// constant with no tier would mean the generator emitted one loop and not the
/// other.
test "every documented method has a rate-limit tier" {
  let untiered = []
  for name in expected_methods() {
    if @methods.tier_of(name) is None {
      untiered.push(name)
    }
  }
  assert_eq(untiered, [], msg="no rate-limit tier: \{untiered.join(", ")}")
}

///|
/// The two metadata files must actually describe the surface they claim to.
/// Without this, a truncated scrape would make the assertions above pass by
/// asking for nothing.
test "the metadata files are the size they should be" {
  let documented = lines_of("documented_methods.txt")
  let excluded = lines_of("excluded_methods.txt")
  assert_eq(documented.length(), 309)
  assert_eq(excluded.length(), 30)
  assert_eq(expected_methods().length(), 279)
  // Every exclusion names a method Slack actually documents. An exclusion that
  // matches nothing is a typo silently widening coverage.
  for name in excluded {
    assert_true(
      documented.contains(name),
      msg="\{name} is excluded but not documented -- typo, or Slack removed it",
    )
  }
}

///|
/// The tier table is allowed to know MORE than the doc scrape: it carries the
/// legacy `channels.*` / `groups.*` / `im.*` / `mpim.*` families that Slack no
/// longer lists but still serves. Extra coverage is not an error; missing
/// coverage is. This test records the size of that gap so that it changing is a
/// deliberate act.
test "the tier table covers more than the documented surface" {
  let documented = lines_of("documented_methods.txt")
  let extra = []
  for name in @methods.method_names {
    if !documented.contains(name) {
      extra.push(name)
    }
  }
  assert_eq(extra.length(), 47)
  // Spot-check the reason: these are the legacy conversation families.
  for legacy in ["channels.list", "groups.list", "im.open", "mpim.open"] {
    assert_true(@methods.is_known(legacy), msg=legacy)
    assert_false(documented.contains(legacy), msg=legacy)
  }
}
