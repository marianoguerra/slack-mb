// The acceptance gate for the Block Kit model and the response envelope.
//
// Every other test in this repo was written by someone who had already decided
// what to check. This one runs over 548 real Slack payloads that nobody picked:
// java-slack-sdk's `json-logs/samples`, which its maintainers built by recording
// live responses, scrubbing the values, and merging every observed shape of each
// method into a single file. That last part is what makes them valuable and
// awkward at once -- fields appear on blocks that have no business carrying
// them, and values appear with the "wrong" type -- which is exactly the input a
// parser is never tested against and always meets in production.
//
// The property that matters is the round trip: `to_json(from_json(x)) == x`.
// It is what proves that nothing was dropped, which no amount of "does it
// parse" testing can.

///|
test "every fixture is valid JSON and parses as a response envelope" {
  let all = @fixtures.fixtures("small")
  assert_true(all.length() > 500, msg="only \{all.length()} fixtures found")
  for fixture in all {
    let json = @fixtures.read_fixture(fixture)
    // `of_json` never raises by design; what is checked is that it agrees with
    // the payload rather than falling back to its not-an-object branch.
    let response = @api.ApiResponse::of_json(json)
    if json is Object(_) {
      assert_eq(response.raw, json, msg=fixture.path)
    }
  }
}

///|
test "every blocks array in the corpus parses" {
  let mut arrays = 0
  let mut blocks = 0
  for fixture in @fixtures.fixtures("small") {
    for array in @fixtures.collect_block_arrays(@fixtures.read_fixture(fixture)) {
      arrays += 1
      guard @blocks.parse_blocks(array) is Some(parsed) else {
        fail("\{fixture.path}: a blocks array did not parse as an array")
      }
      blocks += blocks_count(parsed)
    }
  }
  // A guard against the whole test quietly finding nothing -- which is what a
  // broken `collect_block_arrays` would look like. 29 arrays and 156 blocks at
  // the time of vendoring; the floors are deliberately below that so a refresh
  // that adds fixtures does not fail, while a refresh that loses them does.
  //
  // Most of the corpus's Block Kit lives in the LARGE tier -- chat.postMessage
  // and conversations.history are 2 MB each -- so ext/test/corpus_large is where
  // the volume is. This tier is the breadth: 548 files across every method.
  assert_true(arrays >= 25, msg="only \{arrays} blocks arrays found")
  assert_true(blocks >= 140, msg="only \{blocks} blocks found")
}

///|
fn blocks_count(parsed : Array[@blocks.LayoutBlock]) -> Int {
  parsed.length()
}

///|
/// The property the `extra` maps exist for.
///
/// Slack's payloads carry fields this version does not model -- some newer than
/// it, some undocumented, some artefacts of the fixtures being unions of every
/// observed shape. A model that dropped them would still parse every fixture
/// and would still be wrong: an app that reads a message and writes it back
/// would silently strip fields it never knew about.
test "every block in the corpus round-trips byte for byte" {
  let mut checked = 0
  for fixture in @fixtures.fixtures("small") {
    for array in @fixtures.collect_block_arrays(@fixtures.read_fixture(fixture)) {
      guard @blocks.parse_blocks(array) is Some(parsed) else { continue }
      let round_tripped = @blocks.blocks_to_json(parsed)
      assert_eq(round_tripped, array, msg=fixture.path)
      checked += parsed.length()
    }
  }
  assert_true(checked >= 140, msg="only \{checked} blocks round-tripped")
}

///|
/// A census, so that a block type Slack ships next month shows up as a named
/// failure here rather than as silence.
///
/// One thing is deliberately in the allow-list: `""`, which is a real value
/// rather than a missing field. Slack's scrubber replaces some `type` fields
/// with the empty string, and a block with no type is unmodelled by definition.
test "the corpus contains no unmodelled block types outside the allow-list" {
  let unmodelled : Map[String, Int] = Map([])
  let seen : Map[String, Int] = Map([])
  for fixture in @fixtures.fixtures("small") {
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
  let names = []
  for name, _ in unmodelled {
    names.push(name)
  }
  names.sort()
  for name in names {
    assert_true(
      unmodelled_block_allow_list.contains(name),
      msg="unmodelled block type '\{name}' -- model it, or add it to the allow-list with a reason",
    )
  }
  // ...and the modelled ones really are being exercised.
  for
    expected in [
      "section", "actions", "context", "divider", "image", "input", "rich_text",
      "video",
    ] {
    assert_true(
      seen.get_or_default(expected, 0) > 0,
      msg="the corpus exercises no \{expected} block",
    )
  }
}

///|
/// Same census, one level down. An element type landing in `Unknown` is not
/// wrong -- it round-trips -- but it is a gap worth knowing about.
test "the corpus contains no unmodelled element types" {
  let unmodelled : Map[String, Int] = Map([])
  for fixture in @fixtures.fixtures("small") {
    for array in @fixtures.collect_block_arrays(@fixtures.read_fixture(fixture)) {
      guard @blocks.parse_blocks(array) is Some(parsed) else { continue }
      for block in parsed {
        for element in elements_of_block(block) {
          if element is Unknown(type_=t, ..) {
            unmodelled[t] = unmodelled.get_or_default(t, 0) + 1
          }
        }
      }
    }
  }
  let names = []
  for name, _ in unmodelled {
    names.push(name)
  }
  names.sort()
  for name in names {
    assert_true(
      unmodelled_element_allow_list.contains(name),
      msg="unmodelled element type '\{name}' -- model it, or add it to the allow-list with a reason",
    )
  }
}

///|
/// Block types allowed to land in `Unknown`. See the census test for why each
/// one is here.
let unmodelled_block_allow_list : Array[String] = [""]

///|
/// Element types allowed to land in `Unknown`. Only the scrubber's empty type;
/// every element type in the corpus is modelled.
let unmodelled_element_allow_list : Array[String] = [""]

///|
fn elements_of_block(
  block : @blocks.LayoutBlock,
) -> Array[@blocks.BlockElement] {
  match block {
    Actions(b) =>
      match b.elements {
        Some(list) => list
        None => []
      }
    Context(b) =>
      match b.elements {
        Some(list) => list
        None => []
      }
    Input(b) =>
      match b.element {
        Some(e) => [e]
        None => []
      }
    Section(b) =>
      match b.accessory {
        Some(e) => [e]
        None => []
      }
    _ => []
  }
}
