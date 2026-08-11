// The views.* family.
//
// A view is stored as the JSON the caller sent, with the server-assigned
// fields (`id`, `hash`, `team_id`, `state`, `root_view_id`) merged over it on
// the way out. Same discipline as `Message.blocks`, and for the same reason:
// the blocks inside a modal have to survive the round trip, or the Block Kit
// property this library is built around stops being checkable here.

///|
/// Read and validate the `view` argument.
///
/// A view's `blocks` go through the same `check_blocks` as a message's -- which
/// is where `invalid_blocks` comes from -- but a view has its own refusal for
/// a payload that is not a view at all.
fn Workspace::view_arg(self : Self, form : Form) -> Json raise Refusal {
  guard form.json("view") is Some(payload) else {
    raise refuse("invalid_arguments")
  }
  guard payload is Object(fields) else { raise refuse("invalid_arguments") }
  guard fields.get("type") is Some(String(kind)) &&
    (kind == "modal" || kind == "home") else {
    raise refuse("invalid_arguments")
  }
  self.check_blocks(fields.get("blocks"))
  payload
}

///|
/// Which kind of view a payload declares. Checked by `view_arg` before this
/// runs, so the fallthrough is unreachable rather than a default.
fn view_kind(payload : Json) -> ViewKind {
  if payload is Object(fields) && fields.get("type") is Some(String("home")) {
    Home
  } else {
    Modal
  }
}

///|
/// A view's hash: Slack's optimistic-concurrency token.
///
/// Derived from the view's id and how many times it has been written, so that
/// `views.update` with a stale `hash` can be refused the way Slack refuses it.
/// A counter rather than a digest, because this package has no hash function
/// and importing @crypto for one would be a strange dependency for a mock.
fn Workspace::next_hash(self : Self, view_id : String) -> String {
  "\{self.now / 1000L}.\{view_id}"
}

///|
/// Store a new view and answer with it.
fn Workspace::open_view(
  self : Self,
  payload : Json,
  previous? : ViewRecord,
  user? : String,
) -> Map[String, Json] {
  let id = self.next_view_id()
  let external_id = match payload {
    Object(fields) =>
      match fields.get("external_id") {
        Some(String(x)) if !x.is_empty() => Some(x)
        _ => None
      }
    _ => None
  }
  let record : ViewRecord = {
    id,
    kind: view_kind(payload),
    payload,
    hash: self.next_hash(id),
    external_id,
    // A pushed view keeps the root of the stack it was pushed onto; a fresh
    // one is its own root. That is what `root_view_id` means, and a client
    // popping back to the root reads it.
    root_view_id: match previous {
      Some(prev) => prev.root_view_id
      None => id
    },
    previous_view_id: match previous {
      Some(prev) => Some(prev.id)
      None => None
    },
    user_id: user,
  }
  self.views[id] = record
  { "view": record.to_json(self.team.id) }
}

///|
/// `views.open`.
fn Workspace::views_open(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  // A trigger_id is single-use and expires in three seconds against real
  // Slack. Neither is reproduced -- a mock that expired triggers would make
  // every test race a wall clock it does not have -- but the argument is still
  // required, because forgetting it is the most common views.open failure.
  form.require_as("trigger_id", "invalid_arguments") |> ignore
  let payload = self.view_arg(form)
  self.open_view(payload, user=auth.user_id)
}

///|
/// `views.push`: stack a view on top of the one already open.
fn Workspace::views_push(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  form.require_as("trigger_id", "invalid_arguments") |> ignore
  let payload = self.view_arg(form)
  // The most recently opened modal is the one being pushed onto. Slack ties
  // this to the trigger's own view; the mock has no trigger registry, so the
  // top of the stack is the best available answer and is right whenever a test
  // does one thing at a time.
  let mut previous : ViewRecord? = None
  for _, record in self.views {
    if record.kind == Modal {
      previous = Some(record)
    }
  }
  match previous {
    Some(prev) => self.open_view(payload, previous=prev, user=auth.user_id)
    None => self.open_view(payload, user=auth.user_id)
  }
}

///|
/// `views.update`.
///
/// `hash` is optimistic concurrency: send the one you were given and the update
/// is refused if someone else has written since. An app that ignores it will
/// clobber, against Slack as well as here.
fn Workspace::views_update(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let record = self.find_view(form)
  if form.get("hash") is Some(hash) && !hash.is_empty() && hash != record.hash {
    raise refuse("hash_conflict")
  }
  record.payload = self.view_arg(form)
  record.hash = self.next_hash(record.id)
  { "view": record.to_json(self.team.id) }
}

///|
/// The view named by `view_id` or by `external_id`.
fn Workspace::find_view(self : Self, form : Form) -> ViewRecord raise Refusal {
  if form.get("view_id") is Some(id) && !id.is_empty() {
    guard self.views.get(id) is Some(record) else { raise refuse("not_found") }
    return record
  }
  if form.get("external_id") is Some(external) && !external.is_empty() {
    for _, record in self.views {
      if record.external_id is Some(x) && x == external {
        return record
      }
    }
    raise refuse("not_found")
  }
  raise refuse("invalid_arguments")
}

///|
/// `views.publish`: the App Home tab, which is per user and replaces rather
/// than stacks. Publishing twice for the same user updates the same view,
/// which is why this looks for an existing one first.
fn Workspace::views_publish(
  self : Self,
  form : Form,
  auth : TokenRecord,
) -> Map[String, Json] raise Refusal {
  ignore(auth)
  let user = form.require_as("user_id", "user_not_found")
  guard self.users.get(user) is Some(_) else { raise refuse("user_not_found") }
  let payload = self.view_arg(form)
  for _, record in self.views {
    if record.kind == Home && record.user_id is Some(owner) && owner == user {
      if form.get("hash") is Some(hash) &&
        !hash.is_empty() &&
        hash != record.hash {
        raise refuse("hash_conflict")
      }
      record.payload = payload
      record.hash = self.next_hash(record.id)
      return { "view": record.to_json(self.team.id) }
    }
  }
  self.open_view(payload, user~)
}
