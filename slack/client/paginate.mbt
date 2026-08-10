// Cursor pagination.
//
// https://docs.slack.dev/apis/web-api/pagination
//
// Slack's collection methods answer with `response_metadata.next_cursor`, and
// the caller is expected to pass it back until it stops coming. There are
// exactly two ways to get this wrong, and both are here as tests: treating an
// EMPTY cursor as a real one (an infinite loop over the last page), and
// forgetting the page size on requests after the first (so page one holds 100
// items and every later page holds 200).
//
// The state machine is pure and holds no transport, which is what lets node's
// eight pagination tests port without a server.

///|
/// node-slack-sdk's `defaultPageSize`.
pub let default_page_size : Int = 200

///|
pub struct Paginator {
  page_size : Int
  mut cursor : String?
  mut finished : Bool
  mut pages : Int
}

///|
/// A paginator over one method.
///
/// `cursor` resumes a walk that was interrupted -- a job that paged through
/// 40,000 conversations and died at 30,000 should not start again.
pub fn Paginator::new(
  page_size? : Int = default_page_size,
  cursor? : String,
) -> Paginator {
  { page_size, cursor, finished: false, pages: 0 }
}

///|
/// The extra parameters for the next request, or `None` when there are no more
/// pages.
///
/// `limit` is sent on EVERY request, including the first. node-slack-sdk adds
/// it only from the second request onward, which means page one comes back at
/// whatever default the method happens to have (usually 100) and every later
/// page holds 200 -- a difference the caller never asked for and will only
/// notice as an odd row count. Sending it consistently is a deliberate
/// divergence.
pub fn Paginator::next(self : Self) -> @api.Params? {
  if self.finished {
    return None
  }
  let params = @api.Params::new()
  params.put_int("limit", Some(self.page_size))
  params.put_str("cursor", self.cursor)
  Some(params)
}

///|
/// Record a page and work out whether there is another.
///
/// An absent cursor ends the walk, and so does an EMPTY one: Slack sends
/// `"next_cursor": ""` on the last page, and a client that treats that as a
/// cursor asks for the same page forever. node-slack-sdk's
/// `paginationOptionsForNextPage` checks for both, and so does this.
pub fn Paginator::accept(self : Self, response : @api.ApiResponse) -> Unit {
  self.pages += 1
  match response.response_metadata.next_cursor {
    Some(cursor) =>
      if cursor.is_empty() {
        self.finished = true
        self.cursor = None
      } else {
        self.cursor = Some(cursor)
      }
    None => {
      self.finished = true
      self.cursor = None
    }
  }
}

///|
/// Stop early, whatever the cursor says. The caller's own decision -- "I have
/// enough", "I found what I was looking for" -- rather than Slack's.
pub fn Paginator::stop(self : Self) -> Unit {
  self.finished = true
}

///|
pub fn Paginator::pages(self : Self) -> Int {
  self.pages
}

///|
pub fn Paginator::cursor(self : Self) -> String? {
  self.cursor
}

///|
pub fn Paginator::is_finished(self : Self) -> Bool {
  self.finished
}

///|
/// Merge a paginator's parameters into a caller's, without mutating theirs.
///
/// The paginator's values win: a caller who passed `limit` in the base params
/// AND a `page_size` meant the page size, and two `limit` fields on the wire
/// would let Slack pick.
pub fn merge_params(base : @api.Params, page : @api.Params) -> @api.Params {
  let out = @api.Params::new()
  let overridden = []
  for entry in page.entries {
    overridden.push(entry.0)
  }
  for entry in base.entries {
    if !overridden.contains(entry.0) {
      out.put(entry.0, entry.1)
    }
  }
  for entry in page.entries {
    out.put(entry.0, entry.1)
  }
  out
}

///|
/// Pull the items out of a paged response.
///
/// Slack has no single name for "the collection": `conversations.list` answers
/// with `channels`, `users.list` with `members`, `conversations.history` with
/// `messages`. So the key is the caller's to supply, and an absent or
/// non-array key yields nothing rather than raising -- a page with no items is
/// a normal thing on the last page of a filtered query.
pub fn page_items(response : @api.ApiResponse, key : String) -> Array[Json] {
  match response.get(key) {
    Some(Array(items)) => items
    _ => []
  }
}
