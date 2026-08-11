// Who is calling, and what they are allowed to do.
//
// A mock that accepted any token would be missing the failure an app meets
// first and handles worst: `missing_scope`. Slack's scopes are granted at
// install time and a bot almost never has all of them, so the interesting
// question for an app is not "does this work" but "what does it do when it is
// not allowed to". That needs a registry.

///|
/// One installed app's credentials.
pub struct TokenRecord {
  token : String
  /// The user the token acts as. For a bot token, the bot user.
  user_id : String
  bot_id : String?
  app_id : String
  team_id : String
  scopes : Array[String]
  mut revoked : Bool
}

///|
pub fn TokenRecord::has_scope(self : Self, scope : String) -> Bool {
  self.scopes.contains(scope)
}

///|
/// Install an app, and give it a token.
///
/// `user` names an existing user for the token to act as; without one a bot
/// user is created, which is what an app install actually does. `scopes` is
/// what the token holds -- pass a narrow list to test the degraded paths, or
/// call `grant_all_scopes` afterwards to stop thinking about it.
pub fn Workspace::install_app(
  self : Self,
  token~ : String,
  user? : String,
  scopes? : Array[String] = [],
  name? : String = "mockbot",
) -> TokenRecord {
  let bot_id = self.next_bot_id()
  let user_id = match user {
    Some(id) => id
    None => self.add_user(name~, real_name=name, is_bot=true, bot_id~)
  }
  let record = {
    token,
    user_id,
    bot_id: Some(bot_id),
    app_id: self.next_app_id(),
    team_id: self.team.id,
    scopes,
    revoked: false,
  }
  self.tokens[token] = record
  record
}

///|
/// Give a token every scope the implemented methods ask for.
///
/// The knob that makes the mock pleasant to start with while leaving a scope
/// test possible: seed with this, then install a second, narrow token for the
/// test that cares.
pub fn Workspace::grant_all_scopes(self : Self, token : String) -> Unit {
  if self.tokens.get(token) is Some(record) {
    for scope in all_scopes() {
      if !record.scopes.contains(scope) {
        record.scopes.push(scope)
      }
    }
  }
}

///|
/// Revoke a token, as `auth.revoke` does. Every later call answers
/// `token_revoked`.
pub fn Workspace::revoke_token(self : Self, token : String) -> Unit {
  if self.tokens.get(token) is Some(record) {
    record.revoked = true
  }
}

///|
pub fn Workspace::token(self : Self, token : String) -> TokenRecord? {
  self.tokens.get(token)
}

///|
/// Resolve the `Authorization` header to an installed app.
///
/// The four codes are Slack's own, and the order matters: an absent header is
/// `not_authed` (the request never claimed to be anyone), an unknown token is
/// `invalid_auth`, and a revoked one is `token_revoked` -- distinct because an
/// app handles them differently, and collapsing them is what makes a token
/// rotation bug look like a scope bug.
fn Workspace::authenticate(
  self : Self,
  token : String?,
) -> TokenRecord raise Refusal {
  guard token is Some(t) && !t.is_empty() else { raise refuse("not_authed") }
  guard self.tokens.get(t) is Some(record) else { raise refuse("invalid_auth") }
  if record.revoked {
    raise refuse("token_revoked")
  }
  record
}

///|
/// Check a method's scope requirement against what the token holds.
///
/// Any ONE of the method's scopes satisfies it, which is how Slack's own check
/// works: `channels:read` and `groups:read` both open `conversations.info`,
/// because which one you need depends on the channel, and the API asks for
/// either. `needed` reports the first, which is the one Slack names for a bot
/// token in the common case.
fn Workspace::authorize(
  self : Self,
  api_method : String,
  record : TokenRecord,
) -> Unit raise Refusal {
  ignore(self)
  guard scopes_for(api_method) is Some(accepted) else { return }
  if accepted.is_empty() {
    return
  }
  for scope in accepted {
    if record.has_scope(scope) {
      return
    }
  }
  raise refuse_scope(accepted[0], record.scopes)
}
