// The library against a real Slack workspace.
//
//   SLACK_BOT_TOKEN=xoxb-... SLACK_TEST_CHANNEL='#slack-integration' \
//     moon run --target native ext/cmd/integration
//
// Every other test in this repo runs against recorded fixtures or a scripted
// transport. This one runs against Slack, which is the only way to check the
// two things fixtures cannot:
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
/// What happened to one check.
///
/// Only what the summary needs. The detail -- why a check was skipped, how it
/// failed -- is printed as it happens, next to the check it belongs to, rather
/// than saved up and reprinted at the end where it would have lost its context.
enum Outcome {
  Pass
  Skip
  Fail(String)
}

///|
struct Report {
  outcomes : Array[Outcome]
}

///|
fn Report::new() -> Report {
  { outcomes: [] }
}

///|
fn Report::pass(self : Self, name : String) -> Unit {
  self.outcomes.push(Pass)
  println("  ok    \{name}")
}

///|
fn Report::skip(self : Self, name : String, why : String) -> Unit {
  self.outcomes.push(Skip)
  println("  skip  \{name} -- \{why}")
}

///|
fn Report::fail(self : Self, name : String, why : String) -> Unit {
  self.outcomes.push(Fail(name))
  println("  FAIL  \{name}")
  for line in why.split("\n") {
    println("        \{line}")
  }
}

///|
/// Record an outcome from a call that may legitimately be refused for want of
/// a scope.
///
/// A missing scope is a skip, not a failure: the harness should say what it
/// could not check rather than turning a narrow token into a wall of red.
/// Anything else Slack refuses IS a failure -- that is the point of running it.
async fn Report::check(
  self : Self,
  name : String,
  body : async () -> Unit,
) -> Unit {
  try {
    body()
    self.pass(name)
  } catch {
    e =>
      match @api.to_slack_error(e) {
        PlatformError(result~) =>
          if result.error is Some("missing_scope") {
            let needed = result.needed.unwrap_or("?")
            self.skip(name, "needs scope: \{needed}")
          } else if result.error is Some("not_in_channel") {
            self.skip(name, "the bot is not in the channel; /invite it")
          } else {
            self.fail(name, describe(@api.to_slack_error(e)))
          }
        other => self.fail(name, describe(other))
      }
  }
}

///|
fn describe(error : @api.SlackError) -> String {
  match error {
    PlatformError(result~) => {
      let lines = [error.describe_error_java()]
      for diagnostic in result.response_metadata.diagnostics() {
        lines.push("[\{diagnostic.0}] \{diagnostic.1}")
      }
      lines.join("\n")
    }
    _ => error.describe_error()
  }
}

///|
/// The message this harness posts.
///
/// Deliberately varied: a header, a section with fields, a context line, an
/// actions row with two buttons and a divider. Between them they exercise
/// plain_text, mrkdwn, nested elements and the `style` field -- and they are
/// what gets read back and round-tripped.
fn test_blocks() -> Array[@blocks.LayoutBlock] {
  [
    @blocks.header("slack-mb integration test"),
    @blocks.section(
      text=@blocks.TextObject::mrkdwn("Posted by the MoonBit client."),
      fields=[
        @blocks.TextObject::mrkdwn("*Encoder*\nchecked against Slack"),
        @blocks.TextObject::mrkdwn("*Blocks*\nround-tripped"),
      ],
    ),
    @blocks.divider(),
    @blocks.actions([
      @blocks.button(
        "Primary",
        action_id="probe_primary",
        style="primary",
        value="1",
      ),
      @blocks.button(
        "Danger",
        action_id="probe_danger",
        style="danger",
        value="2",
      ),
    ]),
    @blocks.context([
      @blocks.context_text("This message deletes itself. :wave:"),
    ]),
  ]
}

///|
async fn run(
  client : @client.Client,
  channel : String,
  cleanup_ts? : String,
) -> Int {
  let report = Report::new()

  // --- identity ------------------------------------------------------------
  println("identity")
  let mut scopes = []
  report.check("auth.test", () => {
    let response = client.auth_test()
    guard response.get_str("team") is Some(team) else {
      raise Failed("auth.test returned no team")
    }
    guard response.get_str("user") is Some(user) else {
      raise Failed("auth.test returned no user")
    }
    scopes = response.response_metadata.scopes
    println("        \{user} in \{team}")
    if !scopes.is_empty() {
      println("        scopes: \{scopes.join(", ")}")
    }
  })

  // --- the encoder, against Slack's own parser -----------------------------
  //
  // api.test echoes its arguments back, so this compares what Slack DECODED
  // with what was sent. Nothing else in this repo can check that: every other
  // encoding test compares against another SDK's expectations.
  println("form encoding (api.test echoes what Slack decoded)")
  let awkward = [
    ("plain", "hello"),
    // Multi-byte UTF-8. Fails if the encoder walks UTF-16 code units.
    ("accented", "São Paulo"),
    // The separator and the assignment character, inside a value.
    ("ampersand", "a&b=c"),
    // The one that catches `+`-for-space: if space were encoded as `+`, Slack
    // would decode this as two spaces.
    ("plus", "1+1 = 2"),
    // Outside the BMP: one code point, four UTF-8 bytes, two UTF-16 units.
    ("astral", "🎉 done"),
    ("quotes", "say \"hi\" & 'bye'"),
    ("slashes", "a/b\\c"),
    ("percent", "100% sure"),
    ("newline", "one\ntwo"),
  ]
  report.check("every awkward value survives the round trip", () => {
    let params = @api.Params::new()
    for pair in awkward {
      params.put_str(pair.0, Some(pair.1))
    }
    let response = client.call(@methods.api_test, params)
    guard response.get("args") is Some(Object(args)) else {
      raise Failed("api.test returned no args object")
    }
    for pair in awkward {
      match args.get(pair.0) {
        Some(String(echoed)) =>
          if echoed != pair.1 {
            raise Failed(
              "\{pair.0}: sent \{pair.1.escape()}, Slack decoded \{echoed.escape()}",
            )
          }
        _ => raise Failed("\{pair.0}: Slack did not echo it back")
      }
    }
  })

  // --- pagination against real data ----------------------------------------
  println("pagination")
  report.check("conversations.list walks real cursors", () => {
    // A page size of 2 forces several round trips even in a small workspace,
    // which is the point: one page would not exercise the cursor at all.
    let channels = client.conversations_list_all(
      types=["public_channel"],
      page_size=2,
      max_pages=5,
    )
    println("        \{channels.length()} channels over up to 5 pages of 2")
    if channels.is_empty() {
      raise Failed("no channels came back")
    }
  })
  report.check("users.list walks real cursors", () => {
    let members = client.users_list_all(page_size=2, max_pages=5)
    println("        \{members.length()} members over up to 5 pages of 2")
    if members.is_empty() {
      raise Failed("no members came back")
    }
  })

  // --- errors --------------------------------------------------------------
  println("errors")
  report.check("a bad channel is channel_not_found, not a crash", () => {
    try {
      client.chat_post_message(channel="C00000000000", text="should not arrive")
      |> ignore
      raise Failed("posting to a nonexistent channel should have failed")
    } catch {
      e =>
        match @api.to_slack_error(e) {
          PlatformError(result~) =>
            if result.error is Some("channel_not_found") ||
              result.error is Some("missing_scope") {
              ()
            } else {
              raise Failed(
                "expected channel_not_found, got \{result.error.unwrap_or("?")}",
              )
            }
          other => raise Failed("expected a platform error, got \{other}")
        }
    }
  })
  report.check("malformed blocks report which block, via response_metadata", () => {
    let params = @api.Params::new()
    params.put_str("channel", Some(channel))
    params.put_str("text", Some("fallback"))
    // `sections` is not a block type. Slack answers with a json-pointer at the
    // offending block inside response_metadata.messages -- the field this
    // library surfaces as `diagnostics()`.
    params.put_json("blocks", Some([{ "type": "sections", "text": "x" }]))
    try {
      client.call(@methods.chat_post_message, params) |> ignore
      raise Failed("invalid blocks should have been refused")
    } catch {
      e =>
        match @api.to_slack_error(e) {
          PlatformError(result~) => {
            let diagnostics = result.response_metadata.diagnostics()
            if diagnostics.is_empty() {
              // Slack does not always attach one; the refusal itself is the
              // check, and this only reports what it did say.
              println("        \{result.error.unwrap_or("?")} (no diagnostics)")
            } else {
              for diagnostic in diagnostics {
                println("        [\{diagnostic.0}] \{diagnostic.1}")
              }
            }
          }
          other => raise Failed("expected a platform error, got \{other}")
        }
    }
  })

  // --- the write path, with typed blocks -----------------------------------
  println("messages in \{channel}")
  let mut posted_ts = None
  // The channel as Slack resolved it.
  //
  // `chat.postMessage` accepts a channel NAME (`#slack-integration`);
  // `chat.update`, `chat.delete` and `conversations.history` do not -- they
  // answer `channel_not_found` for the same string. The post response carries
  // the resolved id, so everything downstream uses that. Learned the hard way,
  // by leaving a message stranded in a channel this harness could no longer
  // name.
  let mut resolved_channel = channel
  report.check("chat.postMessage with typed blocks", () => {
    let response = client.chat_post_message(
      channel~,
      text="slack-mb integration test",
      blocks=test_blocks(),
    )
    guard response.get_str("ts") is Some(ts) else {
      raise Failed("chat.postMessage returned no ts")
    }
    if response.get_str("channel") is Some(id) {
      resolved_channel = id
    }
    posted_ts = Some(ts)
    println("        ts \{ts} in \{resolved_channel}")
  })
  match posted_ts {
    None =>
      report.skip(
        "the rest of the message checks", "nothing was posted, so there is nothing to read back",
      )
    Some(ts) => {
      // The assertion this whole harness exists for. Slack normalises what you
      // send -- it assigns block_ids and may add fields -- so comparing with
      // what was sent would be wrong. What must hold is the ROUND TRIP on
      // Slack's own output: parse what came back, write it out, get the same
      // bytes. A block field Slack added since the corpus was recorded would
      // fail here and nowhere else.
      report.check("blocks Slack sent back round-trip byte for byte", () => {
        let history = client.conversations_history(
          channel=resolved_channel,
          latest=ts,
          oldest=ts,
          inclusive=true,
          limit=1,
        )
        guard history.get("messages") is Some(Array(messages)) &&
          messages.length() > 0 else {
          raise Failed("conversations.history returned no messages")
        }
        guard @blocks.parse_message_blocks(messages[0]) is Some(parsed) else {
          raise Failed("the message Slack returned has no blocks array")
        }
        guard messages[0] is Object(message) &&
          message.get("blocks") is Some(original) else {
          raise Failed("could not re-read the blocks field")
        }
        let rewritten = @blocks.blocks_to_json(parsed)
        if rewritten != original {
          raise Failed(
            "round trip changed the payload\n  sent back by Slack: \{original.stringify()}\n  rewritten by us:    \{rewritten.stringify()}",
          )
        }
        println("        \{parsed.length()} blocks, all recognised:")
        for block in parsed {
          println("          \{block.type_name()}")
        }
        // And nothing landed in Unknown, which would mean Slack shipped a block
        // type newer than this library.
        for block in parsed {
          if block is Unknown(type_=t, ..) {
            raise Failed("unmodelled block type from live Slack: '\{t}'")
          }
        }
      })
      report.check("chat.update replaces the blocks", () => {
        client.chat_update(
          channel=resolved_channel,
          ts~,
          text="slack-mb integration test (updated)",
          blocks=[
            @blocks.section_text(
              ":white_check_mark: *Updated* by `chat.update`.",
            ),
          ],
        )
        |> ignore
      })
      report.check("reactions.add", () => {
        client.reactions_add(
          channel=resolved_channel,
          timestamp=ts,
          name="white_check_mark",
        )
        |> ignore
      })
      report.check("chat.delete cleans up", () => {
        client.chat_delete(channel=resolved_channel, ts~) |> ignore
      })
      // A message an earlier run could not clean up, now that the channel id
      // is known. Passed in as SLACK_CLEANUP_TS.
      if cleanup_ts is Some(stray) {
        report.check("an earlier run's message is deleted too", () => {
          client.chat_delete(channel=resolved_channel, ts=stray) |> ignore
        })
      }
    }
  }

  // --- summary -------------------------------------------------------------
  let mut passed = 0
  let mut skipped = 0
  let failures = []
  for outcome in report.outcomes {
    match outcome {
      Pass => passed += 1
      Skip => skipped += 1
      Fail(name) => failures.push(name)
    }
  }
  println("")
  println("\{passed} passed, \{skipped} skipped, \{failures.length()} failed")
  if !failures.is_empty() {
    println("failed: \{failures.join(", ")}")
    return 1
  }
  0
}

///|
suberror Failed {
  Failed(String)
}

///|
pub impl Show for Failed with fn output(self, logger) {
  let Failed(message) = self
  logger.write_string(message)
}

///|
extern "c" fn c_exit(code : Int) -> Unit = "exit"

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
  println("slack-mb integration test against \{channel}")
  // `SLACK_CLEANUP_TS` deletes a message left behind by an earlier run, which
  // is what a run that could not resolve the channel id leaves you with.
  let cleanup_ts = @env.get_env_var("SLACK_CLEANUP_TS")
  println("")
  let client = @client.Client::new(@transport_http.HttpTransport::new(), token)
  let code = run(client, channel, cleanup_ts?) catch {
    e => {
      println("harness error: \{e}")
      2
    }
  }
  if code != 0 {
    c_exit(code)
  }
}
