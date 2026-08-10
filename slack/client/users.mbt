// Typed calls: users.*, auth.*, team.*, usergroups.*
//
// The read-mostly families. Grouped in one file because none of them is large
// enough to earn its own, and because a caller reaching for `auth.test` is
// usually also reaching for `users.info`.

///|
/// https://docs.slack.dev/reference/methods/auth.test
///
/// The call to make first. It answers with the team, the user and the bot id
/// the token belongs to -- which is the only way to find out what a token
/// actually is, since the `xoxb-` prefix says almost nothing.
pub async fn Client::auth_test(
  self : Self,
) -> @api.ApiResponse raise @api.SlackError {
  self.call(@methods.auth_test, @api.Params::new())
}

///|
/// https://docs.slack.dev/reference/methods/auth.revoke
/// `dry_run` is Slack's `test` argument, renamed because `test` is a MoonBit
/// keyword. Set it to check whether the token WOULD be revoked without
/// revoking it.
pub async fn Client::auth_revoke(
  self : Self,
  dry_run? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_bool("test", dry_run)
  self.call(@methods.auth_revoke, p)
}

///|
/// https://docs.slack.dev/reference/methods/api.test
///
/// Echoes its arguments back. Genuinely useful: it is the one call that proves
/// the transport works without needing a valid token.
pub async fn Client::api_test(
  self : Self,
  error? : String,
  extra? : @api.Params = @api.Params::new(),
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("error", error)
  for entry in extra.entries {
    p.put(entry.0, entry.1)
  }
  self.call(@methods.api_test, p)
}

///|
/// https://docs.slack.dev/reference/methods/users.info
pub async fn Client::users_info(
  self : Self,
  user~ : String,
  include_locale? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("user", Some(user))
  p.put_bool("include_locale", include_locale)
  self.call(@methods.users_info, p)
}

///|
/// https://docs.slack.dev/reference/methods/users.list
pub async fn Client::users_list(
  self : Self,
  cursor? : String,
  limit? : Int,
  include_locale? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("cursor", cursor)
  p.put_int("limit", limit)
  p.put_bool("include_locale", include_locale)
  self.call(@methods.users_list, p)
}

///|
/// Every member, across every page. The collection is called `members`, not
/// `users`.
pub async fn Client::users_list_all(
  self : Self,
  include_locale? : Bool,
  page_size? : Int = default_page_size,
  max_pages? : Int,
) -> Array[Json] raise @api.SlackError {
  let p = @api.Params::new()
  p.put_bool("include_locale", include_locale)
  self.paginate_collect(
    @methods.users_list,
    p,
    "members",
    page_size~,
    max_pages?,
  )
}

///|
/// https://docs.slack.dev/reference/methods/users.lookupByEmail
pub async fn Client::users_lookup_by_email(
  self : Self,
  email~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("email", Some(email))
  self.call(@methods.users_lookup_by_email, p)
}

///|
/// https://docs.slack.dev/reference/methods/users.conversations
pub async fn Client::users_conversations(
  self : Self,
  user? : String,
  types? : Array[String],
  exclude_archived? : Bool,
  cursor? : String,
  limit? : Int,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("user", user)
  p.put_csv("types", types)
  p.put_bool("exclude_archived", exclude_archived)
  p.put_str("cursor", cursor)
  p.put_int("limit", limit)
  self.call(@methods.users_conversations, p)
}

///|
/// https://docs.slack.dev/reference/methods/users.profile.get
pub async fn Client::users_profile_get(
  self : Self,
  user? : String,
  include_labels? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("user", user)
  p.put_bool("include_labels", include_labels)
  self.call(@methods.users_profile_get, p)
}

///|
/// https://docs.slack.dev/reference/methods/users.profile.set
pub async fn Client::users_profile_set(
  self : Self,
  user? : String,
  profile? : Json,
  name? : String,
  value? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("user", user)
  p.put_json("profile", profile)
  p.put_str("name", name)
  p.put_str("value", value)
  self.call(@methods.users_profile_set, p)
}

///|
/// https://docs.slack.dev/reference/methods/users.setPresence
pub async fn Client::users_set_presence(
  self : Self,
  presence~ : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("presence", Some(presence))
  self.call(@methods.users_set_presence, p)
}

///|
/// https://docs.slack.dev/reference/methods/users.getPresence
pub async fn Client::users_get_presence(
  self : Self,
  user? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("user", user)
  self.call(@methods.users_get_presence, p)
}

///|
/// https://docs.slack.dev/reference/methods/team.info
pub async fn Client::team_info(
  self : Self,
  team? : String,
  domain? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("team", team)
  p.put_str("domain", domain)
  self.call(@methods.team_info, p)
}

///|
/// https://docs.slack.dev/reference/methods/team.profile.get
pub async fn Client::team_profile_get(
  self : Self,
  visibility? : String,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("visibility", visibility)
  self.call(@methods.team_profile_get, p)
}

///|
/// https://docs.slack.dev/reference/methods/usergroups.list
pub async fn Client::usergroups_list(
  self : Self,
  include_disabled? : Bool,
  include_count? : Bool,
  include_users? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_bool("include_disabled", include_disabled)
  p.put_bool("include_count", include_count)
  p.put_bool("include_users", include_users)
  self.call(@methods.usergroups_list, p)
}

///|
/// https://docs.slack.dev/reference/methods/usergroups.create
pub async fn Client::usergroups_create(
  self : Self,
  name~ : String,
  handle? : String,
  description? : String,
  channels? : Array[String],
  include_count? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("name", Some(name))
  p.put_str("handle", handle)
  p.put_str("description", description)
  p.put_csv("channels", channels)
  p.put_bool("include_count", include_count)
  self.call(@methods.usergroups_create, p)
}

///|
/// https://docs.slack.dev/reference/methods/usergroups.users.update
///
/// Replaces the membership wholesale; it is not an "add". Reading
/// `usergroups.users.list` first and sending the union is on the caller.
pub async fn Client::usergroups_users_update(
  self : Self,
  usergroup~ : String,
  users~ : Array[String],
  include_count? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("usergroup", Some(usergroup))
  p.put_csv("users", Some(users))
  p.put_bool("include_count", include_count)
  self.call(@methods.usergroups_users_update, p)
}

///|
/// https://docs.slack.dev/reference/methods/usergroups.users.list
pub async fn Client::usergroups_users_list(
  self : Self,
  usergroup~ : String,
  include_disabled? : Bool,
) -> @api.ApiResponse raise @api.SlackError {
  let p = @api.Params::new()
  p.put_str("usergroup", Some(usergroup))
  p.put_bool("include_disabled", include_disabled)
  self.call(@methods.usergroups_users_list, p)
}
