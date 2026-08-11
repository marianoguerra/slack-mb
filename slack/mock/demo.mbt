// A workspace with something already in it.

///|
/// The token `demo()` installs. Holds every scope the implemented methods ask
/// for, so nothing a test does is refused for want of one.
pub let demo_token : String = "xoxb-mock-demo-token"

///|
/// A workspace with something already in it.
///
/// Four people and a bot, three channels, a DM, an MPIM, a thread with two
/// replies and two reactions, a pinned message, a usergroup and a file -- and
/// `demo_token`, which can do anything.
///
/// This exists because the first thing anyone does with a mock is spend twenty
/// minutes seeding one before finding out whether it works at all. It is also
/// what the conformance tests in `ext/` drive, so it is exercised by every
/// check rather than being a demo that quietly rots.
///
/// The ids it mints are stable and published in `demo_ids`, which makes them
/// an API-compatibility surface: adding a user in the middle of this function
/// would renumber everything after it and break a consumer's assertions. Add at
/// the end.
pub fn Workspace::demo() -> Workspace {
  let ws = Workspace::new()
  let alice = ws.add_user(
    name="alice",
    real_name="Alice Alvarez",
    title="Staff Engineer",
    is_admin=true,
    is_owner=true,
  )
  let bob = ws.add_user(name="bob", real_name="Bob Bailey", title="Designer")
  let carol = ws.add_user(
    name="carol",
    real_name="Carol Chen",
    title="Engineering Manager",
  )
  let dave = ws.add_user(name="dave", real_name="Dave Diaz", title="Support")
  // Creates the bot user, so it is minted after the humans and its id stays
  // put when one of them changes.
  let app = ws.install_app(token=demo_token, name="mockbot")
  ws.grant_all_scopes(demo_token)
  let bot = app.user_id
  let general = ws.add_channel(
    name="general",
    members=[alice, bob, carol, dave, bot],
    topic="Company-wide announcements",
    purpose="This channel is for workspace-wide communication",
    creator=alice,
  )
  let random = ws.add_channel(
    name="random",
    members=[alice, bob, bot],
    topic="Non-work banter",
    creator=bob,
  )
  let ops = ws.add_channel(
    name="ops",
    is_private=true,
    members=[alice, carol, bot],
    topic="Incidents and on-call",
    creator=carol,
  )
  let dm = ws.add_im(user=bob)
  let mpim = ws.add_mpim(users=[bob, carol])

  // A short history in #general, oldest first. Each `add_message` advances the
  // clock by one simulated second, so the timestamps are distinct and ordered
  // without anything being arranged.
  ws.add_message(channel=general, user=alice, text="Morning, everyone.")
  |> ignore
  let thread_root = ws.add_message(
    channel=general,
    user=carol,
    text="Deploy is going out at 14:00. Shout if that is a problem.",
    blocks=[
      @blocks.section_text("*Deploy window*\nGoing out at 14:00 UTC."),
      @blocks.divider(),
      @blocks.context([@blocks.context_text("Posted by the release bot.")]),
    ],
  )
  ws.add_message(
    channel=general,
    user=bob,
    text="Works for me.",
    thread_ts=thread_root,
  )
  |> ignore
  ws.add_message(
    channel=general,
    user=dave,
    text="Can we push to 15:00? Support handover is at 14.",
    thread_ts=thread_root,
  )
  |> ignore
  let pinned = ws.add_message(
    channel=general,
    user=alice,
    text="Onboarding checklist: https://example.com/onboarding",
  )
  ws.pin(channel=general, ts=pinned)
  ws.add_reaction(channel=general, ts=thread_root, user=bob, name="eyes")
  ws.add_reaction(channel=general, ts=thread_root, user=dave, name="eyes")
  ws.add_reaction(channel=general, ts=pinned, user=carol, name="bookmark")
  ws.add_message(channel=random, user=bob, text="Anyone tried the new place?")
  |> ignore
  ws.add_message(
    channel=ops,
    user=carol,
    text="Pager is quiet. :crossed_fingers:",
  )
  |> ignore
  ws.add_message(channel=dm, user=bob, text="Got a minute?") |> ignore
  ws.add_message(channel=mpim, user=carol, text="Three-way sync?") |> ignore
  ws.add_bookmark(
    channel=general,
    title="Runbook",
    link="https://example.com/runbook",
    emoji=":books:",
  )
  |> ignore
  let usergroup = ws.add_usergroup(
    name="Engineering",
    handle="eng",
    description="Everyone who carries a pager",
    users=[alice, carol],
    channels=[general, ops],
  )
  let file = ws.add_file(
    name="postmortem.md",
    user=carol,
    title="Postmortem: 2023-11-14",
    mimetype="text/markdown",
    filetype="markdown",
    size=2048,
    channels=[ops],
  )
  ws.demo_ids_slot.clear()
  for
    entry in [
      ("alice", alice),
      ("bob", bob),
      ("carol", carol),
      ("dave", dave),
      ("bot", bot),
      ("general", general),
      ("random", random),
      ("ops", ops),
      ("dm", dm),
      ("mpim", mpim),
      ("thread_root", thread_root),
      ("pinned", pinned),
      ("usergroup", usergroup),
      ("file", file),
    ] {
    ws.demo_ids_slot[entry.0] = entry.1
  }
  ws
}

///|
/// The ids `demo()` minted, by the name this file gave them.
///
/// So a test can say `ws.demo_id("general")` instead of re-deriving the
/// counter, and so that renumbering shows up as a failing lookup rather than as
/// a call to a channel that happens to exist.
///
/// Empty for a workspace that did not come from `demo()`.
pub fn Workspace::demo_id(self : Self, name : String) -> String {
  match self.demo_ids_slot.get(name) {
    Some(id) => id
    None =>
      abort(
        "no demo id named \{name}; demo() mints alice, bob, carol, dave, bot, general, random, ops, dm, mpim, thread_root, pinned, usergroup, file",
      )
  }
}

///|
/// Every name `demo_id` will answer to.
pub fn Workspace::demo_ids(self : Self) -> Map[String, String] {
  self.demo_ids_slot
}
