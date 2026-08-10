// A demo CLI.
//
// Its real job is to exercise `transport_http`, which is the one package no
// unit test covers and cannot: everything above it is tested against a scripted
// transport, and everything below it is moonbitlang/async's problem. This is
// how the seam between them gets checked by a person.
//
//   SLACK_BOT_TOKEN=xoxb-... moon run --target native ext/cmd/main -- auth.test
//   SLACK_BOT_TOKEN=xoxb-... moon run --target native ext/cmd/main -- \
//       chat.postMessage channel=C0123456789 text='hello from MoonBit'
//   SLACK_BOT_TOKEN=xoxb-... moon run --target native ext/cmd/main -- \
//       --paginate channels conversations.list types=public_channel
//
// Never runs in CI: it needs a real token and a real workspace.

///|
/// Exit with a code. `@env` has no `exit`, and `panic()` would print a MoonBit
/// backtrace at a person who mistyped an argument.
extern "c" fn c_exit(code : Int) -> Unit = "exit"

///|
fn usage() -> Unit {
  println(
    (
      #|slack -- a demo client for marianoguerra/slack
      #|
      #|  slack [--paginate KEY] [--limit N] METHOD [key=value ...]
      #|
      #|  METHOD      any Slack Web API method name, e.g. auth.test
      #|  key=value   a request parameter; repeat for more
      #|
      #|  --paginate KEY   walk every page and print the items under KEY
      #|                   (channels for conversations.list, members for
      #|                   users.list, messages for conversations.history)
      #|  --limit N        page size for --paginate (default 200)
      #|
      #|The token is read from SLACK_BOT_TOKEN.
    ),
  )
}

///|
struct Args {
  api_method : String
  params : @api.Params
  paginate_key : String?
  limit : Int
}

///|
fn parse_args(argv : Array[String]) -> Args? {
  let params = @api.Params::new()
  let mut api_method = ""
  let mut paginate_key = None
  let mut limit = 200
  let mut i = 0
  while i < argv.length() {
    let arg = argv[i]
    if arg == "--paginate" && i + 1 < argv.length() {
      paginate_key = Some(argv[i + 1])
      i += 2
    } else if arg == "--limit" && i + 1 < argv.length() {
      limit = @string.parse_int(argv[i + 1]) catch { _ => 200 }
      i += 2
    } else if api_method == "" && !arg.has_prefix("-") {
      api_method = arg
      i += 1
    } else if arg.find("=") is Some(eq) {
      params.put_str(arg[:eq].to_owned(), Some(arg[eq + 1:].to_owned()))
      i += 1
    } else {
      println("unrecognised argument: \{arg}")
      return None
    }
  }
  if api_method == "" {
    return None
  }
  Some({ api_method, params, paginate_key, limit })
}

///|
async fn run(args : Args, token : String) -> Unit {
  let transport = @transport_http.HttpTransport::new()
  let client = @client.Client::new(transport, token)
  // A method Slack's metadata does not list is not refused -- it may simply be
  // newer than this library -- but it is worth saying out loud, because a typo
  // looks exactly the same from here.
  if !@methods.is_known(args.api_method) {
    println(
      "note: \{args.api_method} is not in this library's method table; calling it anyway",
    )
  }
  match args.paginate_key {
    Some(key) => {
      let items = client.paginate_collect(
        args.api_method,
        args.params,
        key,
        page_size=args.limit,
      )
      println("\{items.length()} items under '\{key}'")
      for item in items {
        println(item.stringify())
      }
    }
    None => {
      let response = client.call(args.api_method, args.params)
      println(redact(response.raw).stringify(indent=2))
      let meta = response.response_metadata
      if !meta.scopes.is_empty() {
        println("scopes: \{meta.scopes.join(", ")}")
      }
      for diagnostic in meta.diagnostics() {
        println("[\{diagnostic.0}] \{diagnostic.1}")
      }
    }
  }
}

///|
/// Replace the value of any field whose name mentions a token or an
/// authorization with a placeholder.
///
/// Not paranoia. `api.test` echoes back every argument it received INCLUDING
/// the token -- even though this library sends it in the `Authorization`
/// header and never in the body, Slack reflects it anyway. So a CLI that
/// pretty-prints a response verbatim will print the caller's credentials to
/// the terminal, into a scrollback buffer and into whatever captured stdout.
/// node-slack-sdk redacts the same way in its debug logging, for the same
/// reason.
fn redact(value : Json) -> Json {
  match value {
    Object(o) => {
      let out : Map[String, Json] = Map([])
      for key, v in o {
        let lower = key.to_lower()
        if lower.contains("token") || lower.contains("authorization") {
          out[key] = Json::string("[[REDACTED]]")
        } else {
          out[key] = redact(v)
        }
      }
      Json::object(out)
    }
    Array(items) => Json::array(items.map(redact))
    other => other
  }
}

///|
/// What went wrong, in as much detail as the response carries.
///
/// A bare `missing_scope` tells you nothing actionable; the java-slack-sdk
/// phrasing names the scope that was needed and the ones the token actually
/// has, which is the whole content of that error.
fn describe(error : @api.SlackError) -> String {
  match error {
    PlatformError(result~) => {
      let lines = [error.describe_error_java()]
      let scopes = result.response_metadata.scopes
      if !scopes.is_empty() {
        lines.push("token scopes: \{scopes.join(", ")}")
      }
      let accepted = result.response_metadata.accepted_scopes
      if !accepted.is_empty() {
        lines.push("accepted scopes: \{accepted.join(", ")}")
      }
      for diagnostic in result.response_metadata.diagnostics() {
        lines.push("[\{diagnostic.0}] \{diagnostic.1}")
      }
      lines.join("\n")
    }
    _ => error.describe_error()
  }
}

///|
async fn main {
  let argv = @env.args()
  let rest = if argv.length() > 1 { argv[1:].to_owned() } else { [] }
  guard parse_args(rest) is Some(args) else {
    usage()
    c_exit(2)
    return
  }
  guard @env.get_env_var("SLACK_BOT_TOKEN") is Some(token) && token != "" else {
    println("SLACK_BOT_TOKEN is not set")
    c_exit(2)
    return
  }
  run(args, token) catch {
    e => {
      println("error: \{describe(@api.to_slack_error(e))}")
      c_exit(1)
    }
  }
}
