// What happened to each check.

///|
/// What happened to one check.
///
/// Only what the summary needs. The detail -- why a check was skipped, how it
/// failed -- is printed as it happens, next to the check it belongs to, rather
/// than saved up and reprinted at the end where it would have lost its context.
pub enum Outcome {
  Pass
  Skip
  Fail(String)
} derive(Eq, Debug)

///|
pub struct Report {
  outcomes : Array[Outcome]
  /// The names, parallel to `outcomes`, so a failure or a skip can say which
  /// check it was without the outcome carrying it twice.
  names : Array[String]
  /// Why each skip happened. Empty for a check that did not skip.
  reasons : Array[String]
}

///|
pub fn Report::new() -> Report {
  { outcomes: [], names: [], reasons: [] }
}

///|
pub fn Report::pass(self : Self, name : String) -> Unit {
  self.outcomes.push(Pass)
  self.names.push(name)
  self.reasons.push("")
  println("  ok    \{name}")
}

///|
pub fn Report::skip(self : Self, name : String, why : String) -> Unit {
  self.outcomes.push(Skip)
  self.names.push(name)
  self.reasons.push(why)
  println("  skip  \{name} -- \{why}")
}

///|
pub fn Report::fail(self : Self, name : String, why : String) -> Unit {
  self.outcomes.push(Fail(name))
  self.names.push(name)
  self.reasons.push(why)
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
///
/// Against the mock, every scope is granted, so a skip there means the mock
/// refused something real Slack would have allowed. ext/test/mockrun asserts
/// the skip count is zero for exactly that reason.
pub async fn Report::check(
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
pub fn describe(error : @api.SlackError) -> String {
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
pub fn Report::passed(self : Self) -> Int {
  let mut n = 0
  for outcome in self.outcomes {
    if outcome is Pass {
      n += 1
    }
  }
  n
}

///|
pub fn Report::skipped(self : Self) -> Int {
  let mut n = 0
  for outcome in self.outcomes {
    if outcome is Skip {
      n += 1
    }
  }
  n
}

///|
/// The names of the checks that failed, in order.
pub fn Report::failures(self : Self) -> Array[String] {
  let out = []
  for outcome in self.outcomes {
    if outcome is Fail(name) {
      out.push(name)
    }
  }
  out
}

///|
/// Every failure, with the reason under it. What a test puts in its `msg=`, so
/// that a CI log says what broke rather than `[] != ["chat.update"]`.
pub fn Report::failure_report(self : Self) -> String {
  let lines = []
  for i in 0..<self.outcomes.length() {
    if self.outcomes[i] is Fail(_) {
      lines.push("FAIL \{self.names[i]}")
      for line in self.reasons[i].split("\n") {
        lines.push("     \{line}")
      }
    }
  }
  if lines.is_empty() {
    "no failures"
  } else {
    "\n" + lines.join("\n")
  }
}

///|
/// Every skip, with the reason.
pub fn Report::skip_report(self : Self) -> String {
  let lines = []
  for i in 0..<self.outcomes.length() {
    if self.outcomes[i] is Skip {
      lines.push("SKIP \{self.names[i]} -- \{self.reasons[i]}")
    }
  }
  if lines.is_empty() {
    "no skips"
  } else {
    "\n" + lines.join("\n")
  }
}

///|
pub fn Report::print_summary(self : Self) -> Unit {
  let failures = self.failures()
  println("")
  println(
    "\{self.passed()} passed, \{self.skipped()} skipped, \{failures.length()} failed",
  )
  if !failures.is_empty() {
    println("failed: \{failures.join(", ")}")
  }
}

///|
/// `0` when nothing failed, `1` otherwise. What `main` exits with.
pub fn Report::exit_code(self : Self) -> Int {
  if self.failures().is_empty() {
    0
  } else {
    1
  }
}

///|
/// A check's own complaint, as distinct from something Slack refused.
///
/// `Report::check` turns a Slack refusal into a skip or a failure depending on
/// which refusal it was; this is what a check raises when the call SUCCEEDED
/// and the answer was wrong, which is always a failure.
pub suberror Failed {
  Failed(String)
}

///|
pub impl Show for Failed with fn output(self, logger) {
  let Failed(message) = self
  logger.write_string(message)
}
