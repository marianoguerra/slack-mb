// Ported from node-slack-sdk's `WebClient.test.ts` pagination suite.
//
// node drives these through `nock`; here they run against the pure `Paginator`,
// which is the same state machine with the HTTP taken out. Everything node
// asserts about pagination is a property of that machine -- how many requests
// it makes, what it puts in them, when it stops -- so nothing is lost by
// removing the server, and the tests run in microseconds.

///|
fn page_response(next_cursor? : String) -> @api.ApiResponse {
  let meta : Map[String, Json] = Map([])
  if next_cursor is Some(cursor) {
    meta["next_cursor"] = Json::string(cursor)
  }
  @api.ApiResponse::of_json({
    "ok": true,
    "channels": [],
    "response_metadata": Json::object(meta),
  })
}

///|
fn form(params : @api.Params) -> String {
  @api.encode_form(params)
}

///|
/// node-slack-sdk's `defaultPageSize`.
test "the default page size is 200" {
  assert_eq(@client.default_page_size, 200)
  let p = @client.Paginator::new()
  guard p.next() is Some(params) else { fail("a fresh paginator has a page") }
  assert_eq(form(params), "limit=200")
}

///|
/// node: "should get the second page with the cursor from the first".
test "the cursor from one page is sent with the next" {
  let p = @client.Paginator::new()
  guard p.next() is Some(first) else { fail("expected a first page") }
  assert_eq(form(first), "limit=200")
  p.accept(page_response(next_cursor="CURSOR"))
  guard p.next() is Some(second) else { fail("expected a second page") }
  assert_eq(form(second), "limit=200&cursor=CURSOR")
  assert_eq(p.pages(), 1)
}

///|
/// node: "should honor the limit". A caller who asked for 10 gets 10 on every
/// page, not on every page but the first.
test "an explicit page size is honoured on every page" {
  let p = @client.Paginator::new(page_size=10)
  guard p.next() is Some(first) else { fail("expected a first page") }
  assert_eq(form(first), "limit=10")
  p.accept(page_response(next_cursor="C1"))
  guard p.next() is Some(second) else { fail("expected a second page") }
  assert_eq(form(second), "limit=10&cursor=C1")
}

///|
/// node: "should resume from a cursor". A job that walked 30,000 conversations
/// and died should not start again from the top.
test "a caller-supplied cursor is sent with the first request" {
  let p = @client.Paginator::new(cursor="PRE_CURSOR")
  guard p.next() is Some(first) else { fail("expected a first page") }
  assert_eq(form(first), "limit=200&cursor=PRE_CURSOR")
  p.accept(page_response(next_cursor="CURSOR"))
  guard p.next() is Some(second) else { fail("expected a second page") }
  assert_eq(form(second), "limit=200&cursor=CURSOR")
}

///|
/// An ABSENT `next_cursor` ends the walk.
test "no cursor means no more pages" {
  let p = @client.Paginator::new()
  p.accept(page_response())
  assert_true(p.is_finished())
  assert_eq(p.next(), None)
  assert_eq(p.pages(), 1)
}

///|
/// An EMPTY `next_cursor` also ends the walk -- and this is the one that
/// matters. Slack sends `"next_cursor": ""` on the last page, and a client that
/// treats it as a cursor asks for the same page forever.
test "an empty cursor ends the walk, it does not loop" {
  let p = @client.Paginator::new()
  p.accept(page_response(next_cursor="C1"))
  assert_false(p.is_finished())
  p.accept(page_response(next_cursor=""))
  assert_true(p.is_finished())
  assert_eq(p.next(), None)
  assert_eq(p.cursor(), None)
  assert_eq(p.pages(), 2)
}

///|
/// node's `shouldStop` predicate, in its three shapes: never stop, stop
/// immediately, stop on the second page. The counts are node's.
test "stopping early" {
  // Always continue: two pages of cursors, two requests, then the third page
  // ends it.
  let never = @client.Paginator::new()
  never.accept(page_response(next_cursor="C1"))
  assert_true(never.next() is Some(_))
  never.accept(page_response())
  assert_eq(never.next(), None)
  assert_eq(never.pages(), 2)

  // Stop immediately: one page, even though Slack offered another.
  let immediately = @client.Paginator::new()
  immediately.accept(page_response(next_cursor="C1"))
  immediately.stop()
  assert_eq(immediately.next(), None)
  assert_eq(immediately.pages(), 1)

  // Stop on the second: two pages, then no third request.
  let later = @client.Paginator::new()
  later.accept(page_response(next_cursor="C1"))
  assert_true(later.next() is Some(_))
  later.accept(page_response(next_cursor="C2"))
  later.stop()
  assert_eq(later.next(), None)
  assert_eq(later.pages(), 2)
}

///|
/// node: "should reduce". Its accumulator sums `v` across two pages to 3; here
/// the equivalent is concatenating the items, which is what
/// `paginate_collect` does.
test "items are collected out of each page" {
  let first = @api.ApiResponse::of_json({
    "ok": true,
    "channels": [{ "id": "C1" }, { "id": "C2" }],
  })
  let second = @api.ApiResponse::of_json({
    "ok": true,
    "channels": [{ "id": "C3" }],
  })
  let items = []
  for response in [first, second] {
    for item in @client.page_items(response, "channels") {
      items.push(item)
    }
  }
  assert_eq(items.length(), 3)
  assert_eq(items[2], { "id": "C3" })
}

///|
/// Slack has no single name for "the collection" -- `channels`, `members`,
/// `messages` -- so an absent or wrongly-typed key yields nothing rather than
/// raising. A filtered last page legitimately has none.
test "a missing collection key yields no items" {
  let response = @api.ApiResponse::of_json({ "ok": true, "channels": [] })
  assert_eq(@client.page_items(response, "channels").length(), 0)
  assert_eq(@client.page_items(response, "members").length(), 0)
  let odd = @api.ApiResponse::of_json({ "ok": true, "channels": "not an array" })
  assert_eq(@client.page_items(odd, "channels").length(), 0)
}

///|
/// The paginator's parameters win over the caller's, so a caller who passed
/// `limit` in the base params and a `page_size` does not end up with two
/// `limit` fields on the wire for Slack to choose between.
test "page parameters override the caller's" {
  let base = @api.Params::new()
  base.put_str("types", Some("public_channel"))
  base.put_int("limit", Some(5))
  let p = @client.Paginator::new(page_size=200)
  guard p.next() is Some(page) else { fail("expected a page") }
  assert_eq(
    form(@client.merge_params(base, page)),
    "types=public_channel&limit=200",
  )
}

///|
/// Merging must not mutate the caller's params: the same base is used on every
/// page, and a merge that appended to it would grow a `cursor` field per page.
test "merging leaves the caller's parameters alone" {
  let base = @api.Params::new()
  base.put_str("channel", Some("C1"))
  let p = @client.Paginator::new()
  guard p.next() is Some(first) else { fail("expected a page") }
  @client.merge_params(base, first) |> ignore
  p.accept(page_response(next_cursor="C1"))
  guard p.next() is Some(second) else { fail("expected a page") }
  assert_eq(
    form(@client.merge_params(base, second)),
    "channel=C1&limit=200&cursor=C1",
  )
  assert_eq(form(base), "channel=C1")
}

///|
/// The status rules, without a transport: 429 is a rate limit, non-2xx is
/// infrastructure, 200 with `ok:false` is Slack declining, 200 with `ok:true`
/// is the answer.
test "response interpretation" {
  let ok = @client.interpret_response(
    @testing.json_response("{\"ok\":true,\"x\":1}"),
  )
  assert_true(ok.ok)
  try
    @client.interpret_response(
      @testing.json_response("{\"ok\":false,\"error\":\"channel_not_found\"}"),
    )
    |> ignore
  catch {
    @api.PlatformError(result~) =>
      assert_eq(result.error, Some("channel_not_found"))
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected ok:false to raise")
  }
  try @client.interpret_response(@testing.rate_limited(30)) |> ignore catch {
    @api.RateLimitedError(retry_after~) => assert_eq(retry_after, 30)
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a 429 to raise")
  }
  try
    @client.interpret_response(@testing.response(503, "upstream is down"))
    |> ignore
  catch {
    @api.HttpError(status~, body~, ..) => {
      assert_eq(status, 503)
      assert_eq(body, "upstream is down")
    }
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a 503 to raise")
  }
}

///|
/// A 429 with no usable `Retry-After` still has to produce a number, or the
/// caller has nothing to wait. 60 seconds, as in slack-rs.
test "a 429 without a usable Retry-After falls back to 60 seconds" {
  for headers in [[], [("retry-after", "not a number")]] {
    try
      @client.interpret_response(
        @testing.response(
          429,
          "{\"ok\":false,\"error\":\"ratelimited\"}",
          headers~,
        ),
      )
      |> ignore
    catch {
      @api.RateLimitedError(retry_after~) => assert_eq(retry_after, 60)
      e => fail("unexpected error: \{e}")
    } noraise {
      _ => fail("expected a 429 to raise")
    }
  }
}
