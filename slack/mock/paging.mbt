// Cursor pagination, from the server's side.
//
// @client's `Paginator` is the client half and is already tested against
// node-slack-sdk's eight pagination tests. This is the half that produces what
// it walks, and the reason it exists is the one case those tests can only
// simulate: Slack sends `"next_cursor": ""` on the last page, and a client that
// treats an empty cursor as a real one asks for the same page forever. A mock
// that omitted the field instead would let that bug through.

///|
/// Slack's own default page size for the cursor methods.
///
/// 100, not @client's `default_page_size` of 200: 200 is what the paginator
/// ASKS for, and this is what Slack gives when nobody asks. The difference is
/// exactly the thing `Paginator::next` sending `limit` on the first request
/// exists to remove, so the mock has to have both numbers for that to be
/// visible.
let default_page_size : Int = 100

///|
/// The largest page Slack will return however large a `limit` is asked for.
let max_page_size : Int = 1000

///|
/// One page of a collection, and the cursor for the next.
///
/// The cursor is `m:<offset>` rather than Slack's base64 of `b<id>`. The
/// paginator treats it as opaque -- it reads it from `response_metadata` and
/// sends it back untouched -- and a readable cursor is worth far more in a
/// failing test than a plausible one. A deliberate divergence, and the only
/// thing that could notice it is a caller that parses the cursor, which is
/// exactly what nobody should do.
///
/// The returned cursor is `Some("")` on the last page and never `None`: the
/// empty string is what Slack really sends, and reproducing it is what makes
/// this a regression test for `Paginator::accept`.
fn page_of(
  items : Array[Json],
  form : Form,
  default_limit? : Int = default_page_size,
) -> (Array[Json], String) {
  let limit = match form.int("limit") {
    Some(n) if n > 0 => if n > max_page_size { max_page_size } else { n }
    _ => default_limit
  }
  let start = cursor_offset(form.get("cursor"))
  let out : Array[Json] = []
  let mut i = start
  while i < items.length() && out.length() < limit {
    out.push(items[i])
    i += 1
  }
  let next = if i < items.length() { "m:" + i.to_string() } else { "" }
  (out, next)
}

///|
/// Where a cursor points. An absent, empty or unparseable cursor starts at the
/// beginning -- Slack ignores a cursor it does not recognise rather than
/// refusing, and a test that mistyped one should see the first page and notice,
/// not see an error and go looking in the wrong place.
fn cursor_offset(cursor : String?) -> Int {
  guard cursor is Some(c) && c.has_prefix("m:") else { return 0 }
  let offset = @string.parse_int(c[2:].to_owned()) catch { _ => 0 }
  if offset >= 0 {
    offset
  } else {
    0
  }
}

///|
/// `files.list` pages by page number, not by cursor.
///
/// The only method in the typed surface that does. Its response carries a
/// `paging` object instead of `response_metadata`, which is why the client's
/// signature takes `count` and `page` rather than `limit` and `cursor` -- and
/// the vendored fixture pins it, so the shape check would catch it anyway.
fn page_numbered(
  items : Array[Json],
  form : Form,
) -> (Array[Json], Int, Int, Int) {
  let count = match form.int("count") {
    Some(n) if n > 0 => n
    _ => default_page_size
  }
  let page = match form.int("page") {
    Some(n) if n > 0 => n
    _ => 1
  }
  let total = items.length()
  let pages = if total == 0 { 1 } else { (total + count - 1) / count }
  let start = (page - 1) * count
  let out : Array[Json] = []
  let mut i = start
  while i < total && out.length() < count {
    out.push(items[i])
    i += 1
  }
  (out, count, page, pages)
}
