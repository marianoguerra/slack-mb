// The files.* family.
//
// The library does not implement the file-BYTES half of the upload dance --
// the `PUT` to the URL `files.getUploadURLExternal` hands back is left to the
// caller, and `slack/README.mbt.md` says so under "Not included". This mock
// therefore models the two ends and not the middle: a file exists after
// `getUploadURLExternal` and becomes real after `completeUploadExternal`,
// with no bytes in between.

///|
fn Workspace::file_arg(self : Self, form : Form) -> FileRecord raise Refusal {
  let id = form.require_as("file", "file_not_found")
  match self.files.get(id) {
    Some(file) if !file.deleted => file
    _ => raise refuse("file_not_found")
  }
}

///|
/// `files.info`.
///
/// `paging` is here rather than a cursor: the pagination on `files.info` is
/// over the file's COMMENTS, which is why `Client::files_info` takes `cursor`
/// and `limit` while `files.list` takes `count` and `page`. Comments are not
/// modelled, so the list is empty and the paging block says so.
fn Workspace::files_info(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let file = self.file_arg(form)
  {
    "file": file.to_json(),
    "comments": Json::array([]),
    "paging": Json::object({
      "count": Json::number(100.0, repr="100"),
      "total": Json::number(0.0, repr="0"),
      "page": Json::number(1.0, repr="1"),
      "pages": Json::number(1.0, repr="1"),
    }),
  }
}

///|
/// `files.list`.
///
/// The one paginated method in the implemented surface that does NOT use a
/// cursor. Its response carries `paging` instead of `response_metadata`, which
/// is why `Client::files_list` takes `count` and `page` -- and which the corpus
/// pins, so a mock that answered with a cursor here would fail the shape check.
fn Workspace::files_list(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  ignore(auth)
  let wanted_channel = form.get("channel")
  let wanted_user = form.get("user")
  let types = form.csv("types")
  let matching : Array[Json] = []
  let mut total = 0
  for _, file in self.files {
    if file.deleted {
      continue
    }
    if wanted_channel is Some(id) &&
      !id.is_empty() &&
      !file.channels.contains(id) {
      continue
    }
    if wanted_user is Some(id) && !id.is_empty() && file.user != id {
      continue
    }
    // `all` is Slack's wildcard and means do not filter.
    if types is Some(list) &&
      !list.is_empty() &&
      !list.contains("all") &&
      !list.contains(file.filetype) {
      continue
    }
    total += 1
    matching.push(file.to_json())
  }
  let (page, count, page_number, pages) = page_numbered(matching, form)
  {
    "files": Json::array(page),
    "paging": Json::object({
      "count": Json::number(count.to_double(), repr=count.to_string()),
      "total": Json::number(total.to_double(), repr=total.to_string()),
      "page": Json::number(
        page_number.to_double(),
        repr=page_number.to_string(),
      ),
      "pages": Json::number(pages.to_double(), repr=pages.to_string()),
    }),
  }
}

///|
/// `files.delete`.
///
/// A tombstone rather than a removal: Slack keeps answering `file_not_found`
/// for a deleted file, and keeping the record is what lets a test assert that
/// the delete happened at all.
fn Workspace::files_delete(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let file = self.file_arg(form)
  file.deleted = true
  Map([])
}

///|
/// `files.getUploadURLExternal`: reserve an id and hand back a URL.
///
/// The URL goes nowhere. Nothing in this library `PUT`s to it -- that half is
/// the caller's -- so what a test can check here is that the id came back and
/// that `completeUploadExternal` was called with it.
fn Workspace::files_get_upload_url_external(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let filename = form.require_as("filename", "invalid_arguments")
  guard form.int("length") is Some(length) && length >= 0 else {
    raise refuse("invalid_arguments")
  }
  let id = self.next_file_id()
  self.files[id] = {
    id,
    name: filename,
    title: form.get("alt_txt").unwrap_or(filename),
    mimetype: "application/octet-stream",
    filetype: form.get("snippet_type").unwrap_or("binary"),
    user: auth.user_id,
    size: length,
    created: self.now / 1000L,
    channels: [],
    deleted: false,
    // Set until completeUploadExternal clears it. A file with one is reserved,
    // not real, and `files.list` leaves it out.
    upload_token: Some(id),
  }
  {
    "upload_url": Json::string(
      "https://mock.slack.local/upload/\{id}?name=\{filename}",
    ),
    "file_id": Json::string(id),
  }
}

///|
/// `files.completeUploadExternal`.
fn Workspace::files_complete_upload_external(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  guard form.json("files") is Some(Array(entries)) else {
    raise refuse("invalid_arguments")
  }
  let channel = form.get("channel_id")
  let out : Array[Json] = []
  for entry in entries {
    guard entry is Object(fields) && fields.get("id") is Some(String(id)) else {
      raise refuse("invalid_arguments")
    }
    guard self.files.get(id) is Some(file) else {
      raise refuse("file_not_found")
    }
    if fields.get("title") is Some(String(title)) {
      file.title = title
    }
    file.upload_token = None
    if channel is Some(target) && !target.is_empty() {
      if !file.channels.contains(target) {
        file.channels.push(target)
      }
    }
    out.push(file.to_json())
  }
  { "files": Json::array(out) }
}
