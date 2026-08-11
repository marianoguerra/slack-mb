// The library against a real Slack workspace.
//
//   SLACK_BOT_TOKEN=xoxb-... SLACK_TEST_CHANNEL='#slack-integration' \
//     moon run --target native ext/cmd/integration
//
// The scenario itself lives in ext/scenario, because it is also what
// ext/test/mockrun runs against marianoguerra/slack/mock in CI -- one scenario,
// two transports, which is what keeps the mock honest. What is left here is the
// half that needs a token: the environment, the real transport, and the exit
// code.
//
// Every other test in this repo runs against recorded fixtures, a scripted
// transport or the mock. This one runs against Slack, which is the only way to
// check the two things none of those can:
//
//   * that the form encoder agrees with SLACK's parser rather than with
//     node-slack-sdk's test expectations, and
//   * that the Block Kit round-trip property still holds for blocks Slack
//     generates TODAY -- the vendored corpus was recorded at some point in the
//     past, and a field added since would show up here first.
//
// It skips, loudly, whatever the token's scopes do not allow, so it is useful
// with a minimal token and more useful with a broad one. It cleans up after
// itself: every message it posts, it deletes.

///|
extern "c" fn c_exit(code : Int) -> Unit = "exit"

///|
/// Where a `--record` run writes its scrubbed recording.
///
/// The file ext/test/mockrun replays the mock against. Recording is opt-in and
/// manual on purpose: it needs a token, and a golden that regenerated itself on
/// every run would never fail.
let default_recording : String = "ext/recordings/scenario.json"

///|
async fn main {
  guard @env.get_env_var("SLACK_BOT_TOKEN") is Some(token) && token != "" else {
    println("SLACK_BOT_TOKEN is not set")
    c_exit(2)
    return
  }
  let channel = @env.get_env_var("SLACK_TEST_CHANNEL").unwrap_or(
    "#slack-integration",
  )
  // `SLACK_CLEANUP_TS` deletes a message left behind by an earlier run, which
  // is what a run that could not resolve the channel id leaves you with.
  let cleanup_ts = @env.get_env_var("SLACK_CLEANUP_TS")
  let record_to = recording_path()
  println("slack-mb integration test against \{channel}")
  if record_to is Some(path) {
    println("recording to \{path}")
  }
  println("")
  let http = @transport.HttpTransport::new()
  let recorder = @scenario.RecordingTransport::new(http)
  // The recorder is always in the chain; only writing it out is conditional.
  // A wrapper that was sometimes absent would mean the recorded run and the
  // ordinary run went through different code.
  let client = @client.Client::new(recorder, token)
  let report = @scenario.run(client, channel~, cleanup_ts?) catch {
    e => {
      println("harness error: \{e}")
      c_exit(2)
      return
    }
  }
  report.print_summary()
  if record_to is Some(path) {
    write_recording(path, recorder)
  }
  let code = report.exit_code()
  if code != 0 {
    c_exit(code)
  }
}

///|
/// `--record [path]`, or `SLACK_RECORD_FILE`.
fn recording_path() -> String? {
  let args = @env.args()
  for i in 0..<args.length() {
    if args[i] == "--record" {
      return if i + 1 < args.length() && !args[i + 1].has_prefix("-") {
        Some(args[i + 1])
      } else {
        Some(default_recording)
      }
    }
  }
  match @env.get_env_var("SLACK_RECORD_FILE") {
    Some(path) if path != "" => Some(path)
    _ => None
  }
}

///|
/// Write the scrubbed recording, and say what happened either way.
///
/// A failure here is reported and does not change the exit code: the run
/// itself passed or failed on its own merits, and losing the recording is a
/// separate, lesser problem.
fn write_recording(
  path : String,
  recorder : @scenario.RecordingTransport,
) -> Unit {
  let json = recorder.to_json()
  // `IOError` has no `Show`, so the path is all the detail there is to give.
  // The usual cause is the directory not existing; `mkdir -p` fixes it.
  @fs.write_string_to_file(path, json.stringify(indent=1)) catch {
    _ => {
      println("could not write \{path} -- does its directory exist?")
      return
    }
  }
  println("wrote \{recorder.exchanges().length()} exchanges to \{path}")
}
