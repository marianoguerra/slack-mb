// Normalising a recording so a real one and a mock one can be compared.
//
// The placeholders are java-slack-sdk's own -- `U00000000`, `C00000000`,
// `0000000000.000000`, `https://www.example.com/`, `12345` -- which is what
// makes a scrubbed recording comparable against the vendored corpus in
// ext/fixtures as well as against another recording. See ext/fixtures/VENDOR.md.
//
// MoonBit has no regular expressions, so each rule below is a hand-written
// shape test. They are deliberately narrow: a rule that scrubbed too much
// would quietly erase the very values the replay diff compares.

///|
/// Scrub every value in a payload.
///
/// What is NOT touched: `text`, `name`, `blocks`, and every other field the
/// scenario itself chose. Those are the point of the comparison -- a mock that
/// got them wrong is wrong -- and a scrubber that flattened them would make the
/// diff pass on an empty mock.
pub fn scrub_json(value : Json) -> Json {
  match value {
    String(s) => Json::string(scrub_text(s))
    Array(items) => Json::array(items.map(item => scrub_json(item)))
    Object(fields) => {
      let out : Map[String, Json] = Map([])
      for key, field in fields {
        out[key] = if is_time_key(key) && field is Number(_) {
          Json::number(12345.0, repr="12345")
        } else {
          scrub_json(field)
        }
      }
      Json::object(out)
    }
    other => other
  }
}

///|
/// Fields whose numeric value is a time and therefore differs between any two
/// runs. Named rather than detected, because a number is a number: `size` and
/// `created` look identical to anything but a list like this one.
fn is_time_key(key : String) -> Bool {
  match key {
    "created"
    | "updated"
    | "date_create"
    | "date_update"
    | "date_created"
    | "date_updated"
    | "date_delete"
    | "last_set"
    | "post_at"
    | "timestamp"
    | "cache_ts"
    | "expires_in"
    | "last_activity" => true
    _ => false
  }
}

///|
/// Scrub one string.
pub fn scrub_text(value : String) -> String {
  if is_slack_id(value) {
    return value[0:1].to_owned() + "00000000"
  }
  if is_slack_ts(value) {
    return "0000000000.000000"
  }
  if value.has_prefix("https://") || value.has_prefix("http://") {
    return "https://www.example.com/"
  }
  value
}

///|
/// A Slack object id: one of the known prefix letters, then at least seven
/// more characters, all uppercase or digits.
///
/// The prefix set is java-slack-sdk's: U and W for users, B for bots, T for
/// teams, E for enterprises, C/D/G for the three kinds of conversation, F for
/// files, A for apps, S for usergroups, Q for the rest.
fn is_slack_id(value : String) -> Bool {
  if value.length() < 8 {
    return false
  }
  if !"UWBTECDGFASQ".contains(value[0:1]) {
    return false
  }
  for i in 1..<value.length() {
    let c = value[i]
    let upper = c >= 'A' && c <= 'Z'
    let digit = c >= '0' && c <= '9'
    if !upper && !digit {
      return false
    }
  }
  true
}

///|
/// A Slack message timestamp: ten digits, a dot, six digits.
///
/// Exactly that shape. A looser rule would catch a version string or a price,
/// and the whole value of a scrubber is that it removes what varies and nothing
/// else.
fn is_slack_ts(value : String) -> Bool {
  if value.length() != 17 {
    return false
  }
  for i in 0..<value.length() {
    let c = value[i]
    if i == 10 {
      if c != '.' {
        return false
      }
    } else if c < '0' || c > '9' {
      return false
    }
  }
  true
}
