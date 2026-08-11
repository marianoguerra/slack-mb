// One request in, one response out.
//
// This is the whole mock as far as anything outside it is concerned, and it is
// SYNCHRONOUS on purpose. `async` needs moonbitlang/async, which this module
// does not have and must never gain, so the state machine is written as an
// ordinary function and only the two-line `Transport` impl in transport.mbt is
// async. That is what lets this package's own tests drive it.

///|
/// Answer one already-built request.
///
/// Takes the whole `HttpRequest` rather than a `(method, params)` pair, for the
/// same reason the `Transport` trait does: by this point the token has been
/// lifted into a header and the body has been serialised exactly once, and a
/// mock that saw the params instead would be agreeing with the client about an
/// encoding neither of them had to perform. Going through the bytes is what
/// makes this exercise `build_request`, `encode_form` and `decode_form` on
/// every call.
///
/// Raises only for the `Disconnect` fault. Everything else Slack would refuse
/// comes back as an HTTP 200 carrying `ok: false`.
pub fn Workspace::handle(
  self : Self,
  request : @api.HttpRequest,
) -> @api.HttpResponse raise @api.SlackError {
  let api_method = method_of_url(request.url)
  let form = Form::of(@api.decode_form(request.body_text()))
  self.invoke(api_method, form, token?=bearer_token(request.headers))
}

///|
/// The method name: the last path segment of the URL.
///
/// The same split `FakeTransport::method_of` does, and it is here rather than
/// shared because @testing and @mock are siblings -- neither should depend on
/// the other for four lines.
fn method_of_url(url : String) -> String {
  match url.rev_find("/") {
    Some(i) => url[i + 1:].to_owned()
    None => url
  }
}

///|
/// The token out of an `Authorization: Bearer` header.
///
/// Header names are lowercased by every transport, which this library requires
/// and `build_request` guarantees. A header that is present but not `Bearer`
/// yields `None` and therefore `not_authed`, which is what Slack does with a
/// Basic auth header.
fn bearer_token(headers : Map[String, String]) -> String? {
  guard headers.get("authorization") is Some(value) else { return None }
  if value.has_prefix("Bearer ") {
    Some(value[7:].to_owned())
  } else {
    None
  }
}

///|
/// The dispatcher, without HTTP around it.
///
/// The order is deliberate. A fault is taken BEFORE authentication and before
/// any state change, so an injected failure never leaves the workspace
/// half-mutated; the clock advances before the handler runs, so a message
/// minted inside it gets a timestamp later than the call that preceded it.
pub fn Workspace::invoke(
  self : Self,
  api_method : String,
  form : Form,
  token? : String,
) -> @api.HttpResponse raise @api.SlackError {
  if self.take_fault(api_method) is Some(fault) {
    let response = self.apply_fault(fault)
    self.record(api_method, form, response)
    return response
  }
  self.advance(self.tick_millis)
  // The scopes the token holds, reported the way Slack reports them: in a
  // header, not in the body. `ApiResponse::of_http` folds `x-oauth-scopes` into
  // `response_metadata.scopes`, following node-slack-sdk, and a caller
  // diagnosing a `missing_scope` reads it from there.
  let scope_header : Array[(String, String)] = match
    self.tokens.get(token.unwrap_or("")) {
    Some(record) => [("x-oauth-scopes", record.scopes.join(","))]
    None => []
  }
  let response = try {
    let auth = self.authenticate(token)
    self.authorize(api_method, auth)
    let body = self.route(api_method, form, auth)
    ok_response(body, headers=scope_header)
  } catch {
    Refusal(code~, needed~, provided~, messages~) =>
      error_response(code, needed, provided, messages, headers=scope_header)
  }
  self.record(api_method, form, response)
  response
}

///|
/// Turn a queued fault into what the transport would have produced.
fn Workspace::apply_fault(
  self : Self,
  fault : Fault,
) -> @api.HttpResponse raise @api.SlackError {
  ignore(self)
  match fault {
    ErrorCode(code) => error_response(code, None, None, [])
    RateLimited(seconds) =>
      response(
        429,
        (
          #|{"ok":false,"error":"ratelimited"}
        ),
        headers=[("retry-after", seconds.to_string())],
      )
    Http(status~, body~, headers~) => response(status, body, headers~)
    NotJson(body) => response(200, body)
    // The one case that does not come back as bytes at all. `Client::call`
    // narrows whatever the transport raises through `to_slack_error`, so this
    // reaches the caller as `RequestError` -- the shape of a socket giving out.
    Disconnect(why) => raise @api.RequestError("mock slack: \{why}")
  }
}

///|
/// Append to the call log. Every request, including the ones a fault answered
/// and the ones that never authenticated: a test asking "what did my code
/// send" wants all of them.
fn Workspace::record(
  self : Self,
  api_method : String,
  form : Form,
  response : @api.HttpResponse,
) -> Unit {
  let parsed = @api.ApiResponse::of_http(response)
  self.calls.push({
    api_method,
    form: form.entries,
    status: response.status,
    ok: parsed.ok,
    error: parsed.error,
  })
}

///|
/// An HTTP 200 with a JSON body. Header names lowercased, as a real transport
/// is required to do.
fn response(
  status : Int,
  body : String,
  headers? : Array[(String, String)] = [],
) -> @api.HttpResponse {
  let h : Map[String, String] = Map([])
  h["content-type"] = "application/json; charset=utf-8"
  for entry in headers {
    h[entry.0.to_lower()] = entry.1
  }
  { status, headers: h, body }
}

///|
/// `{"ok": true, ...}`.
///
/// `ok` first, because that is where Slack puts it and because a golden diff
/// that starts with the field everyone reads first is easier to scan.
fn ok_response(
  body : Map[String, Json],
  headers? : Array[(String, String)] = [],
) -> @api.HttpResponse {
  let out : Map[String, Json] = Map([])
  out["ok"] = Json::boolean(true)
  for key, value in body {
    out[key] = value
  }
  response(200, Json::object(out).stringify(), headers~)
}

///|
/// `{"ok": false, "error": ...}`, with HTTP 200.
///
/// The status is 200 and not 4xx, and that is not an oversight: Slack answers
/// every refusal with 200 and `ok: false`, which is exactly why
/// `interpret_response` treats the status code and `ok` as two different
/// questions. A mock that answered 400 here would let a client that conflated
/// them pass.
fn error_response(
  code : String,
  needed : String?,
  provided : String?,
  messages : Array[String],
  headers? : Array[(String, String)] = [],
) -> @api.HttpResponse {
  let out : Map[String, Json] = Map([])
  out["ok"] = Json::boolean(false)
  out["error"] = Json::string(code)
  if needed is Some(n) {
    out["needed"] = Json::string(n)
  }
  if provided is Some(p) {
    out["provided"] = Json::string(p)
  }
  if !messages.is_empty() {
    out["response_metadata"] = Json::object({
      "messages": Json::array(messages.map(m => Json::string(m))),
    })
  }
  response(200, Json::object(out).stringify(), headers~)
}

///|
/// Every method this mock answers statefully, sorted by wire name.
///
/// The dispatch table's contents as data, because a `match` cannot be
/// enumerated. ext/test/mockshape checks this list against the typed methods on
/// `@client.Client`, so adding a method there fails a test until a handler
/// exists here.
pub let implemented_methods : Array[String] = [
  "api.test", "auth.revoke", "auth.test", "bookmarks.add", "bookmarks.list", "chat.delete",
  "chat.deleteScheduledMessage", "chat.getPermalink", "chat.meMessage", "chat.postEphemeral",
  "chat.postMessage", "chat.scheduleMessage", "chat.scheduledMessages.list", "chat.unfurl",
  "chat.update", "conversations.archive", "conversations.close", "conversations.create",
  "conversations.history", "conversations.info", "conversations.invite", "conversations.join",
  "conversations.kick", "conversations.leave", "conversations.list", "conversations.mark",
  "conversations.members", "conversations.open", "conversations.rename", "conversations.replies",
  "conversations.setPurpose", "conversations.setTopic", "files.completeUploadExternal",
  "files.delete", "files.getUploadURLExternal", "files.info", "files.list", "pins.add",
  "pins.list", "pins.remove", "reactions.add", "reactions.get", "reactions.list",
  "reactions.remove", "team.info", "team.profile.get", "usergroups.create", "usergroups.list",
  "usergroups.users.list", "usergroups.users.update", "users.conversations", "users.getPresence",
  "users.info", "users.list", "users.lookupByEmail", "users.profile.get", "users.profile.set",
  "users.setPresence", "views.open", "views.publish", "views.push", "views.update",
]

///|
pub fn is_implemented(api_method : String) -> Bool {
  implemented_methods.contains(api_method)
}

///|
/// Route one call to its handler.
///
/// A `match` on the wire name, in the same order as `implemented_methods`. The
/// two are kept in step by a test in ext/test/mockshape, which derives the list
/// a third way -- from the typed methods on `@client.Client` -- so that adding
/// one there fails until a handler exists here.
fn Workspace::route(
  self : Self,
  api_method : String,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  match api_method {
    "api.test" => self.api_test(form, auth)
    "auth.revoke" => self.auth_revoke(form, auth)
    "auth.test" => self.auth_test(form, auth)
    "bookmarks.add" => self.bookmarks_add(form, auth)
    "bookmarks.list" => self.bookmarks_list(form, auth)
    "chat.delete" => self.chat_delete(form, auth)
    "chat.deleteScheduledMessage" =>
      self.chat_delete_scheduled_message(form, auth)
    "chat.getPermalink" => self.chat_get_permalink(form, auth)
    "chat.meMessage" => self.chat_me_message(form, auth)
    "chat.postEphemeral" => self.chat_post_ephemeral(form, auth)
    "chat.postMessage" => self.chat_post_message(form, auth)
    "chat.scheduleMessage" => self.chat_schedule_message(form, auth)
    "chat.scheduledMessages.list" =>
      self.chat_scheduled_messages_list(form, auth)
    "chat.unfurl" => self.chat_unfurl(form, auth)
    "chat.update" => self.chat_update(form, auth)
    "conversations.archive" => self.conversations_archive(form, auth)
    "conversations.close" => self.conversations_close(form, auth)
    "conversations.create" => self.conversations_create(form, auth)
    "conversations.history" => self.conversations_history(form, auth)
    "conversations.info" => self.conversations_info(form, auth)
    "conversations.invite" => self.conversations_invite(form, auth)
    "conversations.join" => self.conversations_join(form, auth)
    "conversations.kick" => self.conversations_kick(form, auth)
    "conversations.leave" => self.conversations_leave(form, auth)
    "conversations.list" => self.conversations_list(form, auth)
    "conversations.mark" => self.conversations_mark(form, auth)
    "conversations.members" => self.conversations_members(form, auth)
    "conversations.open" => self.conversations_open(form, auth)
    "conversations.rename" => self.conversations_rename(form, auth)
    "conversations.replies" => self.conversations_replies(form, auth)
    "conversations.setPurpose" => self.conversations_set_purpose(form, auth)
    "conversations.setTopic" => self.conversations_set_topic(form, auth)
    "files.completeUploadExternal" =>
      self.files_complete_upload_external(form, auth)
    "files.delete" => self.files_delete(form, auth)
    "files.getUploadURLExternal" =>
      self.files_get_upload_url_external(form, auth)
    "files.info" => self.files_info(form, auth)
    "files.list" => self.files_list(form, auth)
    "pins.add" => self.pins_add(form, auth)
    "pins.list" => self.pins_list(form, auth)
    "pins.remove" => self.pins_remove(form, auth)
    "reactions.add" => self.reactions_add(form, auth)
    "reactions.get" => self.reactions_get(form, auth)
    "reactions.list" => self.reactions_list(form, auth)
    "reactions.remove" => self.reactions_remove(form, auth)
    "team.info" => self.team_info(form, auth)
    "team.profile.get" => self.team_profile_get(form, auth)
    "usergroups.create" => self.usergroups_create(form, auth)
    "usergroups.list" => self.usergroups_list(form, auth)
    "usergroups.users.list" => self.usergroups_users_list(form, auth)
    "usergroups.users.update" => self.usergroups_users_update(form, auth)
    "users.conversations" => self.users_conversations(form, auth)
    "users.getPresence" => self.users_get_presence(form, auth)
    "users.info" => self.users_info(form, auth)
    "users.list" => self.users_list(form, auth)
    "users.lookupByEmail" => self.users_lookup_by_email(form, auth)
    "users.profile.get" => self.users_profile_get(form, auth)
    "users.profile.set" => self.users_profile_set(form, auth)
    "users.setPresence" => self.users_set_presence(form, auth)
    "views.open" => self.views_open(form, auth)
    "views.publish" => self.views_publish(form, auth)
    "views.push" => self.views_push(form, auth)
    "views.update" => self.views_update(form, auth)
    _ => raise self.unknown(api_method)
  }
}

///|
/// What to say about a method with no handler.
///
/// Two different situations, and collapsing them costs a caller an afternoon.
/// A name that is not a Slack method at all gets Slack's own `unknown_method`.
/// A name that IS one -- `admin.users.invite`, say -- gets
/// `mock_method_not_implemented`, because answering `unknown_method` there
/// would send someone hunting a typo they did not make. `set_strict_unknown`
/// turns the distinction off for a test that wants Slack's literal answer.
fn Workspace::unknown(self : Self, api_method : String) -> Refusal {
  if @methods.is_known(api_method) && !self.strict_unknown {
    refuse("mock_method_not_implemented")
  } else {
    refuse("unknown_method")
  }
}
