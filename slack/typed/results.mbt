// The answers that are shaped by their method rather than by an entity.
//
// @model holds what Slack sends in many places -- a `User` is a `User` on six
// methods. What is here is the opposite: a handful of methods answer a bag of
// fields nothing else uses, and giving each one a name is better than handing
// back a `Json` or inventing an entity that occurs once.
//
// They are `pub(all)` so a test can build one, and they carry no `extra`: a
// method-specific answer has no forward-compatibility story to tell, and
// `ApiResponse.raw` is right there through `Api::client`.

///|
/// Who a token is: `auth.test`, which is the first call most apps make.
///
/// The five required fields are the ones Slack answers unconditionally for any
/// valid token. `bot_id` is present for a bot token and absent for a user one,
/// which is the cheapest way to tell them apart.
pub(all) struct Identity {
  url : String
  team : String
  user : String
  team_id : String
  user_id : String
  bot_id : String?
  is_enterprise_install : Bool?
  enterprise_id : String?
  app_id : String?
  app_name : String?
  expires_in : Int?
} derive(Eq, @debug.Debug)

///|
/// Whether this token belongs to a bot.
pub fn Identity::is_bot(self : Identity) -> Bool {
  self.bot_id is Some(_)
}

///|
/// A message queued by `chat.scheduleMessage`.
///
/// `scheduled_message_id` is what `chat.deleteScheduledMessage` cancels it
/// with, and the only handle you get -- there is no `ts` until it is sent.
pub(all) struct Scheduled {
  scheduled_message_id : String
  channel : String
  /// Epoch seconds, as an `Int64` so this still works after 2038.
  post_at : Int64
  message : @model.Message?
} derive(Eq, @debug.Debug)

///|
/// A user's presence: `users.getPresence`.
///
/// Everything but `presence` needs the `users:read` scope on your own user, so
/// the rest is optional and usually absent for anyone else.
pub(all) struct Presence {
  /// `"active"` or `"away"`. The only field Slack always answers.
  presence : String
  online : Bool?
  auto_away : Bool?
  manual_away : Bool?
  connection_count : Int?
  /// Epoch seconds.
  last_activity : Int64?
} derive(Eq, @debug.Debug)

///|
/// Where to PUT a file's bytes: `files.getUploadURLExternal`.
///
/// The upload itself is an ordinary HTTP request to `upload_url` and not a Web
/// API call, so it is not something this library does -- see "Not included" in
/// the library's README. `file_id` is what `files.completeUploadExternal`
/// finishes with.
pub(all) struct Upload {
  upload_url : String
  file_id : String
} derive(Eq, @debug.Debug)

///|
/// `auth.test`, as who you are.
fn identity_of(
  response : @api.ApiResponse,
  api_method : String,
) -> Identity raise TypedError {
  {
    url: entity(response, api_method, "url", id_of),
    team: entity(response, api_method, "team", id_of),
    user: entity(response, api_method, "user", id_of),
    team_id: entity(response, api_method, "team_id", id_of),
    user_id: entity(response, api_method, "user_id", id_of),
    bot_id: response.get_str("bot_id"),
    is_enterprise_install: bool_of(response, "is_enterprise_install"),
    enterprise_id: response.get_str("enterprise_id"),
    app_id: response.get_str("app_id"),
    app_name: response.get_str("app_name"),
    expires_in: int_of(response, "expires_in"),
  }
}

///|
/// An optional boolean field of a response.
fn bool_of(response : @api.ApiResponse, key : String) -> Bool? {
  match response.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
/// An optional whole-number field, at `Int` width.
fn int_of(response : @api.ApiResponse, key : String) -> Int? {
  match response.get(key) {
    Some(Number(n, ..)) => {
      let i = n.to_int()
      if i.to_double() == n {
        Some(i)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// The same at `Int64` width, for the epoch-second fields.
fn int64_of(response : @api.ApiResponse, key : String) -> Int64? {
  match response.get(key) {
    Some(Number(n, ..)) => {
      let i = n.to_int64()
      if i.to_double() == n {
        Some(i)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// A required `Int64`, for the one place a schedule time is not optional.
fn int64_at(
  response : @api.ApiResponse,
  api_method : String,
  key : String,
) -> Int64 raise TypedError {
  guard int64_of(response, key) is Some(value) else {
    raise ResponseShapeError(api_method~, key~)
  }
  value
}
