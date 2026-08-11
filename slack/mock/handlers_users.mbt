// users.*, team.* and usergroups.*.

///|
/// The `user` argument, required, resolved.
fn Workspace::user_arg(
  self : Self,
  form : Form,
  key? : String = "user",
) -> User raise Refusal {
  let id = form.require_as(key, "user_not_found")
  match self.users.get(id) {
    Some(user) => user
    None => raise refuse("user_not_found")
  }
}

///|
/// `users.info`.
fn Workspace::users_info(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let user = self.user_arg(form)
  let include_locale = form.flag("include_locale", default=false)
  { "user": user.to_json(self.team.id, include_locale~) }
}

///|
/// `users.list`.
///
/// `cache_ts` and `offset` are here because the corpus has them, not because
/// anything reads them: a client that ignores a field Slack sends is fine, and
/// a mock that omits one is a mock a client cannot be tested against.
fn Workspace::users_list(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  ignore(auth)
  let include_locale = form.flag("include_locale", default=false)
  let members : Array[Json] = []
  for _, user in self.users {
    members.push(user.to_json(self.team.id, include_locale~))
  }
  let (page, next_cursor) = page_of(members, form)
  {
    "members": Json::array(page),
    "cache_ts": Json::number(
      (self.now / 1000L).to_double(),
      repr=(self.now / 1000L).to_string(),
    ),
    "offset": Json::string(next_cursor),
    "response_metadata": Json::object({
      "next_cursor": Json::string(next_cursor),
    }),
  }
}

///|
/// `users.lookupByEmail`.
///
/// The one method whose refusal is `users_not_found` -- plural, unlike the
/// `user_not_found` every other user method answers. That is Slack's spelling,
/// not a typo, and an app matching on the string would miss it.
fn Workspace::users_lookup_by_email(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let email = form.require_as("email", "users_not_found")
  for _, user in self.users {
    if user.email == email {
      return { "user": user.to_json(self.team.id) }
    }
  }
  raise refuse("users_not_found")
}

///|
/// `users.conversations`: the conversations one user is in.
///
/// Defaults to the CALLING user when `user` is absent, which is the whole point
/// of the method for a bot: "what can I see".
fn Workspace::users_conversations(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  let who = form.get("user").unwrap_or(auth.user_id)
  let types = form.csv("types").unwrap_or(["public_channel"])
  let exclude_archived = form.flag("exclude_archived", default=false)
  let matching : Array[Json] = []
  for _, channel in self.channels {
    if exclude_archived && channel.is_archived {
      continue
    }
    if !type_matches(channel.kind, types) {
      continue
    }
    if !channel.members.contains(who) {
      continue
    }
    matching.push(channel.to_json(include_membership=false, for_list=true))
  }
  let (page, next_cursor) = page_of(matching, form)
  {
    "channels": Json::array(page),
    "response_metadata": Json::object({
      "next_cursor": Json::string(next_cursor),
    }),
  }
}

///|
/// `users.getPresence`.
fn Workspace::users_get_presence(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let id = form.get("user").unwrap_or(auth.user_id)
  guard self.users.get(id) is Some(user) else { raise refuse("user_not_found") }
  let online = user.presence == "active"
  {
    "presence": Json::string(user.presence),
    "online": Json::boolean(online),
    "auto_away": Json::boolean(false),
    "manual_away": Json::boolean(!online),
    "connection_count": Json::number(
      if online {
        1.0
      } else {
        0.0
      },
      repr=if online { "1" } else { "0" },
    ),
    "last_activity": Json::number(
      (self.now / 1000L).to_double(),
      repr=(self.now / 1000L).to_string(),
    ),
  }
}

///|
/// `users.setPresence`. Slack takes only `auto` and `away`; `auto` means
/// "active".
fn Workspace::users_set_presence(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let presence = form.require_as("presence", "invalid_presence")
  guard presence == "auto" || presence == "away" else {
    raise refuse("invalid_presence")
  }
  if self.users.get(auth.user_id) is Some(user) {
    user.presence = if presence == "away" { "away" } else { "active" }
  }
  Map([])
}

///|
/// `users.profile.get`.
fn Workspace::users_profile_get(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let id = form.get("user").unwrap_or(auth.user_id)
  guard self.users.get(id) is Some(user) else { raise refuse("user_not_found") }
  {
    // `fields` is here and NOT on `users.info`'s profile -- the two are
    // different objects in Slack's samples. See the note in render.mbt.
    "profile": user.profile_json(self.team.id, include_fields=true),
  }
}

///|
/// `users.profile.set`, in both of the shapes Slack accepts: a whole `profile`
/// object, or a single `name`/`value` pair.
fn Workspace::users_profile_set(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  let id = form.get("user").unwrap_or(auth.user_id)
  guard self.users.get(id) is Some(user) else { raise refuse("user_not_found") }
  if form.json("profile") is Some(Object(fields)) {
    for key, value in fields {
      user.set_profile_field(key, value)
    }
  } else if form.get("name") is Some(name) {
    user.set_profile_field(name, Json::string(form.get("value").unwrap_or("")))
  } else {
    raise refuse("invalid_arguments")
  }
  user.updated = self.now / 1000L
  {
    "username": Json::string(user.name),
    "profile": user.profile_json(self.team.id, include_fields=true),
  }
}

///|
/// Write one profile field.
///
/// The named fields are set on the record so that `users.info` and
/// `users.list` see them too; anything else goes into `profile_extra` and comes
/// back out of the profile unchanged. A field this model does not know is a
/// field a consumer chose to put there, and dropping it would make
/// `users.profile.set` followed by `users.profile.get` lose data.
fn User::set_profile_field(self : Self, key : String, value : Json) -> Unit {
  let text = match value {
    String(s) => s
    other => other.stringify()
  }
  match key {
    "real_name" => self.real_name = text
    "display_name" => self.display_name = text
    "email" => self.email = text
    "title" => self.title = text
    "phone" => self.phone = text
    "status_text" => self.status_text = text
    "status_emoji" => self.status_emoji = text
    _ => self.profile_extra[key] = value
  }
}

///|
/// `team.info`.
fn Workspace::team_info(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  // `team` and `domain` select another workspace in an org-wide install. There
  // is only one here, so naming a different one is `team_not_found` rather
  // than silently answering about this one.
  if form.get("team") is Some(id) && !id.is_empty() && id != self.team.id {
    raise refuse("team_not_found")
  }
  if form.get("domain") is Some(d) && !d.is_empty() && d != self.team.domain {
    raise refuse("team_not_found")
  }
  { "team": self.team.to_json() }
}

///|
/// `team.profile.get`: the custom profile FIELD DEFINITIONS, not a user's
/// values. An empty workspace has none, which is a real answer rather than a
/// gap -- most workspaces have none either.
fn Workspace::team_profile_get(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  ignore(self)
  ignore(form)
  ignore(auth)
  {
    "profile": Json::object({
      "fields": Json::array([]),
      "sections": Json::array([]),
    }),
  }
}

///|
fn Workspace::usergroup_arg(
  self : Self,
  form : Form,
) -> Usergroup raise Refusal {
  let id = form.require_as("usergroup", "no_such_subteam")
  match self.usergroups.get(id) {
    Some(group) => group
    None => raise refuse("no_such_subteam")
  }
}

///|
/// `usergroups.create`.
fn Workspace::usergroups_create(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let name = form.require_as("name", "invalid_arguments")
  for _, group in self.usergroups {
    if group.name == name {
      raise refuse("name_already_exists")
    }
  }
  let id = self.add_usergroup(
    name~,
    handle=form.get("handle").unwrap_or(name),
    description=form.get("description").unwrap_or(""),
    channels=form.csv("channels").unwrap_or([]),
  )
  guard self.usergroups.get(id) is Some(group) else {
    raise refuse("internal_error")
  }
  {
    "usergroup": group.to_json(
      include_count=form.flag("include_count", default=false),
      include_users=true,
    ),
  }
}

///|
/// `usergroups.list`.
fn Workspace::usergroups_list(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  ignore(auth)
  let include_disabled = form.flag("include_disabled", default=false)
  let include_count = form.flag("include_count", default=false)
  let include_users = form.flag("include_users", default=false)
  let out : Array[Json] = []
  for _, group in self.usergroups {
    if !include_disabled && group.date_delete != 0L {
      continue
    }
    out.push(group.to_json(include_count~, include_users~))
  }
  { "usergroups": Json::array(out) }
}

///|
/// `usergroups.users.list`.
fn Workspace::usergroups_users_list(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let group = self.usergroup_arg(form)
  { "users": Json::array(group.users.map(u => Json::string(u))) }
}

///|
/// `usergroups.users.update`: REPLACES the membership rather than adding to it.
///
/// Worth its own sentence because it is the operation people get wrong: there
/// is no "add one user to a group" method, so a caller who sends one id has
/// just removed everybody else.
fn Workspace::usergroups_users_update(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let group = self.usergroup_arg(form)
  let users = match form.csv("users") {
    Some(list) => list
    None => raise refuse("invalid_arguments")
  }
  for id in users {
    if !(self.users.get(id) is Some(_)) {
      raise refuse("invalid_users")
    }
  }
  group.users = users
  group.date_update = self.now / 1000L
  {
    "usergroup": group.to_json(
      include_count=form.flag("include_count", default=false),
      include_users=true,
    ),
  }
}
