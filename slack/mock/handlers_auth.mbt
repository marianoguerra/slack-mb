// api.test, auth.test, auth.revoke.
//
// Every handler in this package has the same shape: it takes the decoded form
// and the authenticated token, it is written as though it succeeds, and it
// raises a `Refusal` when it cannot. The dispatcher turns that into
// `{"ok": false, ...}` with HTTP 200.

///|
/// `api.test` echoes its arguments back under `args`.
///
/// That echo is not decoration -- it is the only way to check a form encoder
/// against SLACK's parser rather than against another SDK's expectations, which
/// is why `ext/cmd/integration` sends `São Paulo`, `a&b=c`, `1+1 = 2` and an
/// emoji through it. Reproducing it here is what lets that same check run
/// against the mock.
///
/// One documented quirk is NOT reproduced: against real Slack the token comes
/// back inside `args` too. That is because Slack still accepts a token in the
/// body, and echoes whatever body it was given. This library never puts one
/// there -- `build_request` lifts it into the `Authorization` header -- so
/// there is nothing for the echo to find, and inventing one would be
/// contradicted by `check_library_invariants`.
fn Workspace::api_test(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(self)
  ignore(auth)
  let args : Map[String, Json] = Map([])
  for entry in form.entries {
    args[entry.0] = Json::string(entry.1)
  }
  // `error` is the one argument api.test acts on rather than echoes: it makes
  // the call fail with whatever string was passed, which is how Slack lets a
  // client exercise its own error path without provoking a real failure.
  if form.get("error") is Some(code) && !code.is_empty() {
    raise refuse(code)
  }
  { "args": Json::object(args) }
}

///|
/// `auth.test`: who this token is.
fn Workspace::auth_test(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  ignore(form)
  let out : Map[String, Json] = Map([])
  out["url"] = Json::string("https://\{self.team.domain}.slack.com/")
  out["team"] = Json::string(self.team.name)
  out["user"] = Json::string(self.user_name(auth.user_id))
  out["team_id"] = Json::string(auth.team_id)
  out["user_id"] = Json::string(auth.user_id)
  if auth.bot_id is Some(bot_id) {
    out["bot_id"] = Json::string(bot_id)
  }
  out["is_enterprise_install"] = Json::boolean(false)
  out["app_id"] = Json::string(auth.app_id)
  if self.team.enterprise_id is Some(id) {
    out["enterprise_id"] = Json::string(id)
  }
  out
}

///|
/// `auth.revoke`: stop this token working.
///
/// `test=true` reports what WOULD happen without doing it, which is what the
/// `dry_run` argument on `Client::auth_revoke` sends. Getting this backwards --
/// revoking during a dry run -- would break every later call in the test with
/// `token_revoked`, so it is worth its own line.
fn Workspace::auth_revoke(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] {
  let dry_run = form.flag("test", default=false)
  if !dry_run {
    self.revoke_token(auth.token)
  }
  { "revoked": Json::boolean(!dry_run) }
}
