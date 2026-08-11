// The scenario itself.

///|
/// The integration scenario, against whatever is behind the client.
///
/// Unchanged from when it was ext/cmd/integration's `main`, except that it
/// returns the `Report` instead of computing an exit code -- so a test can
/// assert on it and a CLI can print it. Every check it makes is one no fixture
/// can: the form encoder against a real parser, the Block Kit round trip on
/// blocks the SERVER produced, and the refusals a caller actually meets.
pub async fn run(
  client : @client.Client,
  channel~ : String,
  cleanup_ts? : String,
) -> Report {
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
  report
}
