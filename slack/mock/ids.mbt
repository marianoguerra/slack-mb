// Ids and time, both deterministic.
//
// This is the file where the mock diverges from Slack on purpose, twice, and
// both divergences are the point of a mock rather than a shortcut: a workspace
// that minted random ids and read a clock would produce a different response
// every run, and a test that cannot name what it seeded is a test that asserts
// nothing.

///|
/// The counters behind every minted id.
priv struct IdSeq {
  mut user : Int
  mut channel : Int
  mut im : Int
  mut mpim : Int
  mut file : Int
  mut view : Int
  mut usergroup : Int
  mut bookmark : Int
  mut scheduled : Int
  mut bot : Int
  mut app : Int
  /// The epoch second the last `ts` was minted in, and how many have been
  /// minted in it.
  mut ts_seconds : Int64
  mut ts_seq : Int
}

///|
fn IdSeq::new() -> IdSeq {
  {
    user: 0,
    channel: 0,
    im: 0,
    mpim: 0,
    file: 0,
    view: 0,
    usergroup: 0,
    bookmark: 0,
    scheduled: 0,
    bot: 0,
    app: 0,
    ts_seconds: 0L,
    ts_seq: 0,
  }
}

///|
let base36 : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
  'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V',
  'W', 'X', 'Y', 'Z',
]

///|
/// A prefix and eight uppercase base-36 digits: `U00000001`, `C0000000A`.
///
/// The same SHAPE as the placeholders in the vendored corpus (`U00000000`,
/// `C00000000`, `B00000000`), which is what lets a mock response be compared
/// against a recorded real one with nothing but a prefix rewrite -- see the
/// scrubber in ext/scenario.
///
/// A deliberate divergence: Slack's real ids are longer, are not sequential and
/// are not predictable. Being predictable is the whole reason this exists.
fn mint_id(prefix : Char, counter : Int) -> String {
  let digits = FixedArray::make(8, '0')
  let mut n = counter
  let mut i = 7
  while i >= 0 {
    digits[i] = base36[n % 36]
    n = n / 36
    i -= 1
  }
  let out = StringBuilder::new(size_hint=9)
  out.write_char(prefix)
  for j in 0..<8 {
    out.write_char(digits[j])
  }
  out.to_string()
}

///|
/// The next id of each kind. One function per kind so that the counters cannot
/// be crossed by a typo -- a channel minted from the user counter would collide
/// silently and only show up as a baffling `channel_not_found`.
fn Workspace::next_user_id(self : Self) -> String {
  self.ids.user += 1
  mint_id('U', self.ids.user)
}

///|
fn Workspace::next_bot_id(self : Self) -> String {
  self.ids.bot += 1
  mint_id('B', self.ids.bot)
}

///|
fn Workspace::next_app_id(self : Self) -> String {
  self.ids.app += 1
  mint_id('A', self.ids.app)
}

///|
fn Workspace::next_channel_id(self : Self) -> String {
  self.ids.channel += 1
  mint_id('C', self.ids.channel)
}

///|
fn Workspace::next_im_id(self : Self) -> String {
  self.ids.im += 1
  mint_id('D', self.ids.im)
}

///|
fn Workspace::next_mpim_id(self : Self) -> String {
  self.ids.mpim += 1
  mint_id('G', self.ids.mpim)
}

///|
fn Workspace::next_file_id(self : Self) -> String {
  self.ids.file += 1
  mint_id('F', self.ids.file)
}

///|
fn Workspace::next_view_id(self : Self) -> String {
  self.ids.view += 1
  mint_id('V', self.ids.view)
}

///|
fn Workspace::next_usergroup_id(self : Self) -> String {
  self.ids.usergroup += 1
  mint_id('S', self.ids.usergroup)
}

///|
fn Workspace::next_bookmark_id(self : Self) -> String {
  self.ids.bookmark += 1
  mint_id('Q', self.ids.bookmark)
}

///|
fn Workspace::next_scheduled_id(self : Self) -> String {
  self.ids.scheduled += 1
  mint_id('Q', self.ids.scheduled)
}

///|
/// Left-pad with zeroes to a fixed width. Slack's `ts` is exactly ten digits, a
/// dot, and six more; a shorter one sorts wrong everywhere it is compared as a
/// string.
fn pad(n : Int64, width : Int) -> String {
  let s = n.to_string()
  if s.length() >= width {
    return s
  }
  let out = StringBuilder::new(size_hint=width)
  for _ in 0..<(width - s.length()) {
    out.write_char('0')
  }
  out.write_string(s)
  out.to_string()
}

///|
/// The next message timestamp: `1700000000.000001`.
///
/// The six digits after the dot are a per-second counter rather than
/// microseconds, so two messages posted inside the same simulated second still
/// order and still compare as distinct. Slack's own `ts` is not a real
/// microsecond count either -- it is an ordering key that happens to look like
/// a time -- so this is a divergence in how the digits are chosen, not in what
/// they mean.
pub fn Workspace::next_ts(self : Self) -> String {
  let seconds = self.now / 1000L
  if seconds == self.ids.ts_seconds {
    self.ids.ts_seq += 1
  } else {
    self.ids.ts_seconds = seconds
    self.ids.ts_seq = 1
  }
  pad(seconds, 10) + "." + pad(self.ids.ts_seq.to_int64(), 6)
}

///|
/// Compare two Slack timestamps.
///
/// NOT string comparison: MoonBit's `Compare` for `String` is shortlex, so
/// `"1.2"` would sort before `"1700000000.000001"` on length alone, and a
/// caller passing a short `oldest` bound is a real thing -- ext/test/calls does
/// exactly that. Splits at the dot and compares each half as a number, with a
/// missing half read as zero.
pub fn ts_compare(a : String, b : String) -> Int {
  let (a_sec, a_sub) = split_ts(a)
  let (b_sec, b_sub) = split_ts(b)
  if a_sec != b_sec {
    if a_sec < b_sec {
      -1
    } else {
      1
    }
  } else if a_sub != b_sub {
    if a_sub < b_sub {
      -1
    } else {
      1
    }
  } else {
    0
  }
}

///|
/// A `ts` as `(seconds, subsecond)`. An unparseable half is zero rather than an
/// error: a bound a caller invented should narrow nothing, not raise.
fn split_ts(ts : String) -> (Int64, Int64) {
  match ts.split_once(".") {
    Some((sec, sub)) => (parse_i64(sec.to_owned()), parse_i64(sub.to_owned()))
    None => (parse_i64(ts), 0L)
  }
}

///|
fn parse_i64(s : String) -> Int64 {
  @string.parse_int64(s) catch {
    _ => 0L
  }
}

///|
/// Move the clock forward.
///
/// Time is an `Int64` of milliseconds the caller supplies, never read here --
/// the same rule @ratectl and @signature follow, and the reason this package
/// builds on wasm.
pub fn Workspace::advance(self : Self, millis : Int64) -> Unit {
  self.now += millis
}

///|
pub fn Workspace::now(self : Self) -> Int64 {
  self.now
}

///|
pub fn Workspace::set_now(self : Self, now : Int64) -> Unit {
  self.now = now
}

///|
/// How far the clock moves per handled call. One simulated second by default,
/// so a scenario that posts three messages gets three distinct timestamps a
/// second apart without arranging anything.
///
/// Set it to `0L` to freeze time: `next_ts` still returns distinct values,
/// because the sub-second counter keeps rising.
pub fn Workspace::set_tick(self : Self, millis : Int64) -> Unit {
  self.tick_millis = millis
}
