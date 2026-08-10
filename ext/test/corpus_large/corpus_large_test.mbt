// The same properties as ext/test/corpus, over the 17 fixtures too large to
// commit.
//
// This is where the Block Kit volume actually is: `chat.postMessage.json` and
// `conversations.history.json` are 2 MB each and between them hold 2,392 of the
// corpus's 2,548 blocks. The small tier is breadth -- 548 files, one per method
// -- and this is depth.
//
// Gitignored and fetched with `just fixtures`, so these tests SKIP on a fresh
// clone. They say so out loud: a silent skip and a pass look identical in CI
// output, and a corpus test that quietly checked nothing would be worse than no
// corpus test at all.

///|
fn skip_notice() -> Unit {
  println(
    "SKIP: the large fixtures are not on disk. Fetch them with `just fixtures` (ext/scripts/fetch-large-fixtures.sh).",
  )
}

///|
/// The property the `extra` maps exist for, over 2,392 real blocks.
test "every block in the large fixtures round-trips byte for byte" {
  if !@fixtures.tier_present("large") {
    skip_notice()
    return
  }
  let mut checked = 0
  let mut arrays = 0
  for fixture in @fixtures.fixtures("large") {
    for array in @fixtures.collect_block_arrays(@fixtures.read_fixture(fixture)) {
      arrays += 1
      guard @blocks.parse_blocks(array) is Some(parsed) else {
        fail("\{fixture.path}: a blocks array did not parse as an array")
      }
      assert_eq(@blocks.blocks_to_json(parsed), array, msg=fixture.path)
      checked += parsed.length()
    }
  }
  // 183 arrays and 2,392 blocks at the time of vendoring.
  assert_true(arrays >= 150, msg="only \{arrays} blocks arrays found")
  assert_true(checked >= 2000, msg="only \{checked} blocks round-tripped")
}

///|
/// `share_shortcut` is the only unmodelled block type here: an internal block
/// Slack uses for workflow sharing, absent from the Block Kit reference. It
/// round-trips as `Unknown`, which is the whole point of having that variant.
test "the large fixtures contain no unmodelled types outside the allow-list" {
  if !@fixtures.tier_present("large") {
    skip_notice()
    return
  }
  let unmodelled : Map[String, Int] = Map([])
  let seen : Map[String, Int] = Map([])
  for fixture in @fixtures.fixtures("large") {
    for array in @fixtures.collect_block_arrays(@fixtures.read_fixture(fixture)) {
      guard @blocks.parse_blocks(array) is Some(parsed) else { continue }
      for block in parsed {
        let name = block.type_name()
        seen[name] = seen.get_or_default(name, 0) + 1
        if block is Unknown(..) {
          unmodelled[name] = unmodelled.get_or_default(name, 0) + 1
        }
      }
    }
  }
  for name, count in unmodelled {
    assert_true(
      name == "" || name == "share_shortcut",
      msg="unmodelled block type '\{name}' (\{count} occurrences) -- model it, or add it to the allow-list with a reason",
    )
  }
  // Rich text is the type that matters most here: Slack rewrites every ordinary
  // message into one, so it is the block a real app meets constantly.
  assert_true(
    seen.get_or_default("rich_text", 0) > 0,
    msg="the large fixtures exercise no rich_text block",
  )
  assert_true(
    seen.get_or_default("section", 0) > 1000,
    msg="expected the section-heavy fixtures; found \{seen.get_or_default("section", 0)}",
  )
}
