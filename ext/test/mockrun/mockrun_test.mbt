// The shared scenario, against marianoguerra/slack/mock.

///|
/// A demo workspace and a client pointed at it, with the recorder in between.
///
/// The recorder is always in the chain, exactly as ext/cmd/integration has it,
/// so the mock run and the real run go through the same code rather than
/// differing in a wrapper.
fn harness() -> (@mock.Workspace, @scenario.RecordingTransport, @client.Client) {
  let ws = @mock.Workspace::demo()
  let recorder = @scenario.RecordingTransport::new(ws.transport())
  (ws, recorder, @client.Client::new(recorder, @mock.demo_token))
}

///|
/// The scenario ext/cmd/integration runs against Slack, run against the mock.
///
/// What this buys is a mock whose fidelity is defined by something other than
/// the mock's own tests -- and, once a recording exists, a real answer to
/// "would this scenario have passed against Slack?".
///
/// The SKIP assertion is the sharp one. Against real Slack a narrow token skips
/// checks, and `Report::check` turns `missing_scope` into a skip on purpose.
/// The mock grants every scope, so a skip here means the mock refused something
/// real Slack would have allowed -- a mock bug, not a scope problem.
async test "the integration scenario passes against the mock" {
  let (_, _, client) = harness()
  let report = @scenario.run(client, channel="#general")
  assert_eq(report.failures(), [], msg=report.failure_report())
  assert_eq(report.skipped(), 0, msg=report.skip_report())
  assert_true(report.passed() >= 9, msg="only \{report.passed()} checks ran")
}

///|
/// The scenario deletes what it posts. Against Slack that is politeness;
/// against the mock it is checkable, and a mock whose delete did not delete
/// would make the real run leave litter nobody noticed.
async test "the scenario leaves the workspace as it found it" {
  let (ws, _, client) = harness()
  let general = ws.demo_id("general")
  let before = ws.messages(general).length()
  @scenario.run(client, channel="#general") |> ignore
  assert_eq(ws.messages(general).length(), before)
}

///|
/// The scenario resolves `#general` to an id on the first post and uses the id
/// after that. If it did not, `chat.update` and `conversations.history` would
/// answer `channel_not_found` -- which is the asymmetry the mock reproduces and
/// the bug this arrangement exists to catch.
async test "the scenario never sends a channel name where Slack refuses one" {
  let (ws, _, client) = harness()
  @scenario.run(client, channel="#general") |> ignore
  for record in ws.calls() {
    let by_name = record.field("channel") is Some(spec) && spec.has_prefix("#")
    if by_name {
      assert_true(
        ["chat.postMessage", "chat.postEphemeral", "chat.meMessage"].contains(
          record.api_method,
        ),
        msg="\{record.api_method} was sent a channel name, which Slack refuses",
      )
    }
  }
}

///|
/// Every exchange the run produced, scrubbed. Both the recording written by
/// `--record` and the one replayed here go through this, so the comparison is
/// between two values normalised the same way.
fn scrubbed(recorder : @scenario.RecordingTransport) -> Json {
  recorder.to_json()
}

///|
/// The replay diff.
///
/// Self-skips when there is no recording, so a fresh clone -- and CI, which has
/// no token -- is green. Record one with:
///
///   SLACK_BOT_TOKEN=xoxb-... moon run --target native ext/cmd/integration -- --record
async test "the mock's exchanges match the recorded real ones, once scrubbed" {
  guard recording_path() is Some(path) else {
    println(
      "SKIP: no recording at ext/recordings/scenario.json -- record one with `SLACK_BOT_TOKEN=... moon run --target native ext/cmd/integration -- --record`",
    )
    return
  }
  let text = @fs.read_file_to_string(path) catch {
    _ => {
      println("SKIP: could not read \{path}")
      return
    }
  }
  let recorded = @json.parse(text) catch {
    _ => fail("\{path} is not valid JSON")
  }
  let real = @scenario.exchanges_of_json(recorded)
  guard !real.is_empty() else {
    println("SKIP: \{path} holds no exchanges")
    return
  }
  let (_, recorder, client) = harness()
  @scenario.run(client, channel="#general") |> ignore
  let mine = @scenario.exchanges_of_json(scrubbed(recorder))

  // 1. The same methods, in the same order. The cheapest of the three checks
  //    and the one that localises the other two when it fails.
  assert_eq(
    mine.map(e => e.api_method()),
    real.map(e => e.api_method()),
    msg="the mock run called different methods than the recorded one",
  )

  // 2. The same shape, both ways round -- a key present on one side only fails
  //    whichever side it is on.
  for i in 0..<real.length() {
    let where_ = "\{real[i].api_method()} (#\{i})"
    let forward = @shape.shape_diff(mine[i].body(), real[i].body(), "")
    assert_eq(forward, [], msg="\{where_}: the mock sent fields Slack did not")
    let backward = @shape.shape_diff(real[i].body(), mine[i].body(), "")
    assert_eq(backward, [], msg="\{where_}: Slack sent fields the mock did not")
  }

  // 3. Value equality, but only on the paths the SCENARIO chose. A real
  //    workspace and demo() hold different people and different channel names,
  //    so byte equality is unachievable -- but a mock that got `ok`, the error
  //    code or the text of the message the scenario itself wrote is simply
  //    wrong.
  for i in 0..<real.length() {
    for path in @shape.compared_paths {
      let a = @shape.at_path(mine[i].body(), path)
      let b = @shape.at_path(real[i].body(), path)
      assert_eq(a, b, msg="\{real[i].api_method()} (#\{i}) differs at \{path}")
    }
  }
}

///|
/// The recording, wherever `moon test` was invoked from.
///
/// Probing rather than a fixed path, for the reason ext/test/fixtures probes:
/// `moon test` covers the whole workspace from any directory, so a fixed path
/// would be green in one place and red in another.
fn recording_path() -> String? {
  for prefix in ["ext/recordings/", "recordings/", "../recordings/"] {
    let path = prefix + "scenario.json"
    if @fs.path_exists(path) {
      return Some(path)
    }
  }
  None
}
