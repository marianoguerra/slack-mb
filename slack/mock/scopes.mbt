// Which scopes each method accepts.
//
// From each method's page under https://docs.slack.dev/reference/methods/ ,
// read as a bot token would need them. ANY ONE of the listed scopes satisfies
// the call, which is how Slack's own check works -- `conversations.info` opens
// on `channels:read` OR `groups:read` OR `im:read` OR `mpim:read`, because
// which one applies depends on the conversation and the API asks for either.
//
// A method absent from this table needs no scope. `api.test` is the honest
// example: it works with no token at all against real Slack, and the only
// reason this mock still requires one is that a request with no `Authorization`
// header is far more likely to be a bug in the code under test than a
// deliberate anonymous call.

///|
/// Method name to the scopes that satisfy it, first-listed being the one
/// reported as `needed`.
let method_scopes : Map[String, Array[String]] = {
  // auth, team
  "auth.test": [],
  "auth.revoke": [],
  "api.test": [],
  "team.info": ["team:read"],
  "team.profile.get": ["users.profile:read"],

  // users
  "users.info": ["users:read"],
  "users.list": ["users:read"],
  "users.lookupByEmail": ["users:read.email"],
  "users.conversations": [
    "channels:read", "groups:read", "im:read", "mpim:read",
  ],
  "users.getPresence": ["users:read"],
  "users.setPresence": ["users:write"],
  "users.profile.get": ["users.profile:read"],
  "users.profile.set": ["users.profile:write"],

  // usergroups
  "usergroups.create": ["usergroups:write"],
  "usergroups.list": ["usergroups:read"],
  "usergroups.users.list": ["usergroups:read"],
  "usergroups.users.update": ["usergroups:write"],

  // conversations
  "conversations.list": ["channels:read", "groups:read", "im:read", "mpim:read"],
  "conversations.info": ["channels:read", "groups:read", "im:read", "mpim:read"],
  "conversations.members": [
    "channels:read", "groups:read", "im:read", "mpim:read",
  ],
  "conversations.history": [
    "channels:history", "groups:history", "im:history", "mpim:history",
  ],
  "conversations.replies": [
    "channels:history", "groups:history", "im:history", "mpim:history",
  ],
  "conversations.create": ["channels:manage", "groups:write"],
  "conversations.invite": ["channels:manage", "groups:write"],
  "conversations.join": ["channels:join"],
  "conversations.kick": ["channels:manage", "groups:write"],
  "conversations.leave": ["channels:manage", "groups:write"],
  "conversations.archive": ["channels:manage", "groups:write"],
  "conversations.close": ["im:write", "mpim:write"],
  "conversations.open": ["im:write", "mpim:write", "channels:manage"],
  "conversations.rename": ["channels:manage", "groups:write"],
  "conversations.mark": ["channels:write", "groups:write"],
  "conversations.setPurpose": ["channels:manage", "groups:write"],
  "conversations.setTopic": ["channels:manage", "groups:write"],

  // chat
  "chat.postMessage": ["chat:write"],
  "chat.postEphemeral": ["chat:write"],
  "chat.update": ["chat:write"],
  "chat.delete": ["chat:write"],
  "chat.meMessage": ["chat:write"],
  "chat.scheduleMessage": ["chat:write"],
  "chat.deleteScheduledMessage": ["chat:write"],
  "chat.scheduledMessages.list": ["chat:write"],
  "chat.getPermalink": ["none"],
  "chat.unfurl": ["links:write"],

  // reactions, pins, bookmarks
  "reactions.add": ["reactions:write"],
  "reactions.remove": ["reactions:write"],
  "reactions.get": ["reactions:read"],
  "reactions.list": ["reactions:read"],
  "pins.add": ["pins:write"],
  "pins.remove": ["pins:write"],
  "pins.list": ["pins:read"],
  "bookmarks.add": ["bookmarks:write"],
  "bookmarks.list": ["bookmarks:read"],

  // files
  "files.info": ["files:read"],
  "files.list": ["files:read"],
  "files.delete": ["files:write"],
  "files.getUploadURLExternal": ["files:write"],
  "files.completeUploadExternal": ["files:write"],

  // views
  "views.open": [],
  "views.push": [],
  "views.update": [],
  "views.publish": [],
}

///|
/// `chat.getPermalink` is the one method whose docs list a scope that is not a
/// scope. Slack's page says "none", and a token with any scope at all may call
/// it, so the table's literal `"none"` must never be required.
let pseudo_scope : String = "none"

///|
/// The scopes that satisfy one method, or `None` when the method is not in the
/// table and therefore needs nothing.
fn scopes_for(api_method : String) -> Array[String]? {
  match method_scopes.get(api_method) {
    Some(scopes) => Some(scopes.filter(s => s != pseudo_scope))
    None => None
  }
}

///|
/// Every real scope this table mentions, sorted, with no duplicates.
///
/// What `grant_all_scopes` hands out, and derived from the table rather than
/// listed again: a second list would drift the first time a method is added.
fn all_scopes() -> Array[String] {
  let out : Array[String] = []
  for _, scopes in method_scopes {
    for scope in scopes {
      if scope != pseudo_scope && !out.contains(scope) {
        out.push(scope)
      }
    }
  }
  out
}
