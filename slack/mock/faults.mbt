// Making the mock fail on purpose.
//
// Everything @client does on the error path -- `RateLimitedError` and its
// `Retry-After`, `HttpError` on a 5xx, `PlatformError` on `ok: false`,
// `RequestError` when the socket gives out, and the non-JSON body that
// `ApiResponse::of_http` turns into an error rather than swallowing -- is
// reachable today only by scripting a `FakeTransport`. That works for a unit
// test of one call and not at all for "the third page of this walk fails",
// which is the case an app actually gets wrong.

///|
/// One scripted failure.
pub(all) enum Fault {
  /// `{"ok": false, "error": "<code>"}` with HTTP 200 -- the shape Slack
  /// refuses with, and what @client turns into `PlatformError`.
  ErrorCode(String)
  /// HTTP 429 with a `retry-after` header, in seconds.
  ///
  /// The only route to a 429 here. Pacing is @ratectl's job, computed from the
  /// method's tier against a clock the caller drives; a mock that throttled by
  /// itself would make every test that posts fifty messages slow, and would put
  /// two implementations of the same rule in one repository.
  RateLimited(Int)
  /// Any status with any body -- a 502 carrying a proxy's HTML error page is
  /// the real shape of the thing `HttpError` exists for.
  Http(status~ : Int, body~ : String, headers~ : Array[(String, String)])
  /// HTTP 200 whose body is not JSON. `ApiResponse::of_http` turns this into
  /// `{ok: false, error: <the raw text>}` rather than swallowing it, following
  /// node-slack-sdk, and this is what pins that.
  NotJson(String)
  /// The transport itself fails, which reaches the caller as `RequestError`.
  Disconnect(String)
} derive(Eq, Debug)

///|
/// The catch-all key: a fault queued under this fires for any method that has
/// no queue of its own.
pub let any_method : String = "*"

///|
/// Queue a fault for the next call to `api_method`.
///
/// FIFO per method, and `times` queues the same fault more than once -- "the
/// next two calls are rate limited" is one line rather than two. Use
/// `any_method` for a fault that should fire whatever is called next.
///
/// Faults are consumed BEFORE authentication and before any state change, so an
/// injected failure never leaves the workspace half-mutated. That is not what
/// Slack does -- a real 500 can arrive after the message was posted -- but a
/// mock whose faults corrupted its own state would be untrustworthy for the
/// tests that come after the fault, which are the interesting ones.
pub fn Workspace::inject(
  self : Self,
  api_method : String,
  fault : Fault,
  times? : Int = 1,
) -> Unit {
  let queue = match self.faults.get(api_method) {
    Some(q) => q
    None => {
      let q : Array[Fault] = []
      self.faults[api_method] = q
      q
    }
  }
  for _ in 0..<times {
    queue.push(fault)
  }
}

///|
/// Drop every queued fault. For a test that injected one and did not reach it.
pub fn Workspace::clear_faults(self : Self) -> Unit {
  self.faults.clear()
}

///|
/// How many faults are still queued, across every method.
///
/// Worth asserting is zero at the end of a test: a fault that never fired means
/// the call it was waiting for was never made, which is usually the bug.
pub fn Workspace::pending_faults(self : Self) -> Int {
  let mut total = 0
  for _, queue in self.faults {
    total += queue.length()
  }
  total
}

///|
/// Take the fault that applies to this method, if any.
fn Workspace::take_fault(self : Self, api_method : String) -> Fault? {
  if self.faults.get(api_method) is Some(queue) && !queue.is_empty() {
    return Some(queue.remove(0))
  }
  if self.faults.get(any_method) is Some(queue) && !queue.is_empty() {
    return Some(queue.remove(0))
  }
  None
}
