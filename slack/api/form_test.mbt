// Ported from node-slack-sdk's `WebClient.test.ts` ("should properly serialize
// ... API arguments", lines 556-600) and java-slack-sdk's
// `RequestFormBuilderTest`.
//
// The node cases assert whole request bodies as literal strings. They are
// reproduced here character for character, which is the only kind of test that
// catches an encoder that is *nearly* right.

///|
fn form(entries : Array[(String, @api.ParamValue)]) -> String {
  @api.encode_form(@api.Params::of(entries))
}

///|
/// node-slack-sdk: "should properly serialize simple API arguments".
test "simple arguments" {
  assert_eq(
    form([
      ("team_id", Str("T12345678")),
      ("foo", Str("stringval")),
      ("bar", Int(42)),
      ("baz", Bool(false)),
    ]),
    "team_id=T12345678&foo=stringval&bar=42&baz=false",
  )
}

///|
/// node-slack-sdk: "should properly serialize complex API arguments". Anything
/// that is not a string, number or boolean becomes a JSON string, and that JSON
/// string is then percent-encoded like any other value -- so `{` and `"` are
/// escaped, but the value itself is not double-encoded.
test "structured arguments become percent-encoded JSON" {
  let arraything : Json = [
    {
      "foo": "stringval",
      "bar": 42,
      "baz": false,
      "zup": ["one", "two", "three"],
    },
  ]
  let objectthing : Json = { "foo": 7, "hum": false }
  assert_eq(
    form([
      ("arraything", JsonVal(arraything)),
      ("objectthing", JsonVal(objectthing)),
    ]),
    "arraything=%5B%7B%22foo%22%3A%22stringval%22%2C%22bar%22%3A42%2C%22baz%22%3Afalse%2C%22zup%22%3A%5B%22one%22%2C%22two%22%2C%22three%22%5D%7D%5D&objectthing=%7B%22foo%22%3A7%2C%22hum%22%3Afalse%7D",
  )
}

///|
/// node-slack-sdk: "should remove undefined or null values from simple API
/// arguments". The `put_*` family is how an absent argument disappears instead
/// of becoming the four characters `null`.
test "absent arguments are dropped, not stringified" {
  let p = @api.Params::new()
  p.put_str("something_undefined", None)
  p.put_int("something_null", None)
  p.put_str("something", Some("else"))
  assert_eq(@api.encode_form(p), "something=else")
  // Every put_* helper drops None the same way.
  let all = @api.Params::new()
  all.put_str("a", None)
  all.put_int("b", None)
  all.put_i64("c", None)
  all.put_num("d", None)
  all.put_bool("e", None)
  all.put_csv("f", None)
  all.put_json("g", None)
  assert_eq(all.length(), 0)
  assert_eq(@api.encode_form(all), "")
}

///|
/// The two SDKs disagree and both are correct on the wire; the knob is what
/// lets each one's golden strings be tested literally.
test "boolean style follows node by default and java on request" {
  let p : Array[(String, @api.ParamValue)] = [
    ("yes", Bool(true)),
    ("no", Bool(false)),
  ]
  assert_eq(@api.encode_form(@api.Params::of(p)), "yes=true&no=false")
  assert_eq(
    @api.encode_form(@api.Params::of(p), bool_style=TrueFalse),
    "yes=true&no=false",
  )
  assert_eq(
    @api.encode_form(@api.Params::of(p), bool_style=OneZero),
    "yes=1&no=0",
  )
}

///|
/// java-slack-sdk `RequestFormBuilderTest#blocks`: a `blocks` list serialises to
/// the JSON array, not to a Java-ish `toString`.
test "blocks serialise as a JSON array" {
  let blocks : Json = [{ "type": "myTestBlock" }]
  assert_eq(
    @api.ParamValue::JsonVal(blocks).to_wire(bool_style=TrueFalse),
    (
      #|[{"type":"myTestBlock"}]
    ),
  )
}

///|
/// java-slack-sdk `RequestFormBuilderTest`: an EMPTY block list is sent as `[]`
/// and not omitted.
///
/// This is not pedantry. On `chat.update`, omitting `blocks` leaves the
/// existing blocks alone while sending `[]` clears them, so "drop empty
/// collections" would make it impossible to remove blocks from a message.
test "an empty blocks list is [] and is not omitted" {
  let empty : Json = []
  assert_eq(@api.ParamValue::JsonVal(empty).to_wire(bool_style=TrueFalse), "[]")
  let p = @api.Params::new()
  p.put_json("blocks", Some(empty))
  assert_eq(@api.encode_form(p), "blocks=%5B%5D")
}

///|
/// java-slack-sdk `RequestFormBuilderTest`: an attachment with no fields set is
/// `[{}]`, for the same reason.
test "an empty attachment is an empty object, not nothing" {
  let attachments : Json = [{}]
  assert_eq(
    @api.ParamValue::JsonVal(attachments).to_wire(bool_style=TrueFalse),
    "[{}]",
  )
}

///|
/// java-slack-sdk comma-joins the fields Slack documents as CSV --
/// `conversations.invite` `users`, `admin.conversations.invite` `user_ids` and
/// 65 others. node-slack-sdk types them as `string` and pushes the joining onto
/// the caller. `Csv` makes the SDK do it while keeping it a per-field decision.
test "Csv joins with commas and no spaces" {
  let p = @api.Params::new()
  p.put_csv("users", Some(["U111", "U222", "U333"]))
  assert_eq(@api.encode_form(p), "users=U111%2CU222%2CU333")
  assert_eq(
    @api.ParamValue::Csv(["U111", "U222"]).to_wire(bool_style=TrueFalse),
    "U111,U222",
  )
  // A single element has no separator; an empty list is the empty string, which
  // is still a present field.
  assert_eq(
    @api.ParamValue::Csv(["U111"]).to_wire(bool_style=TrueFalse),
    "U111",
  )
  assert_eq(@api.ParamValue::Csv([]).to_wire(bool_style=TrueFalse), "")
}

///|
/// The distinction `ParamValue` exists to preserve: the same array is `a,b` in
/// one field and `["a","b"]` in another, and only Slack's docs know which.
test "Csv and JsonVal are different wire formats for the same data" {
  let items = ["one", "two"]
  assert_eq(
    @api.ParamValue::Csv(items).to_wire(bool_style=TrueFalse),
    "one,two",
  )
  assert_eq(
    @api.ParamValue::JsonVal(["one", "two"]).to_wire(bool_style=TrueFalse),
    (
      #|["one","two"]
    ),
  )
}

///|
/// Percent-encoding follows `encodeURIComponent`, which is what
/// `node:querystring` implements and therefore what node-slack-sdk sends.
test "the unreserved set matches encodeURIComponent" {
  // Left alone.
  assert_eq(
    @api.percent_encode_component("abcXYZ019-_.!~*'()"),
    "abcXYZ019-_.!~*'()",
  )
  // Encoded, uppercase hex.
  assert_eq(@api.percent_encode_component(" "), "%20")
  assert_eq(@api.percent_encode_component("&"), "%26")
  assert_eq(@api.percent_encode_component("="), "%3D")
  assert_eq(@api.percent_encode_component("+"), "%2B")
  assert_eq(@api.percent_encode_component("/"), "%2F")
  assert_eq(@api.percent_encode_component("#"), "%23")
  assert_eq(@api.percent_encode_component("%"), "%25")
  assert_eq(@api.percent_encode_component("\n"), "%0A")
}

///|
/// Space is `%20`, never `+`.
///
/// Both are legal in a form body and Slack reads either, but `%20` is what
/// `node:querystring` and OkHttp's `FormBody` emit -- and since a request
/// signature is computed over the bytes actually sent, "whatever the reference
/// SDKs send" is the only defensible answer.
test "space is %20, not plus" {
  let p = @api.Params::new()
  p.put_str("text", Some("hello world"))
  assert_eq(@api.encode_form(p), "text=hello%20world")
}

///|
/// The UTF-16 trap. MoonBit strings are UTF-16; encoding per code unit would
/// emit surrogate halves and mis-encode every accented character, so this only
/// passes if the encoder walks UTF-8 bytes.
test "non-ASCII is encoded over UTF-8 bytes" {
  assert_eq(@api.percent_encode_component("São Paulo"), "S%C3%A3o%20Paulo")
  assert_eq(
    @api.percent_encode_component("日本語"),
    "%E6%97%A5%E6%9C%AC%E8%AA%9E",
  )
  // Outside the BMP: one code point, four UTF-8 bytes, two UTF-16 code units.
  assert_eq(@api.percent_encode_component("🎉"), "%F0%9F%8E%89")
}

///|
/// Field names go through the same encoder as values. Slack has no method with
/// an exotic argument name, but the generic `call` will happily be handed one.
test "keys are encoded too" {
  assert_eq(form([("weird key&", Str("v"))]), "weird%20key%26=v")
}

///|
/// Numeric shapes reach the wire the way Slack's docs describe them: `ts`
/// values are strings, `limit` is an integer, and a float stays a float.
test "numbers" {
  assert_eq(
    form([
      ("limit", Int(200)),
      ("big", I64(9007199254740993L)),
      ("frac", Num(1.5)),
      ("ts", Str("1234567890.123456")),
    ]),
    "limit=200&big=9007199254740993&frac=1.5&ts=1234567890.123456",
  )
}

///|
/// Slack's message JSON is full of URLs, and a `\/`-escaping serialiser would
/// change every one of them. Neither reference SDK escapes slashes.
test "slashes in embedded JSON are not escaped" {
  let blocks : Json = [
    { "type": "image", "image_url": "https://example.com/a/b.png" },
  ]
  assert_eq(
    @api.ParamValue::JsonVal(blocks).to_wire(bool_style=TrueFalse),
    (
      #|[{"type":"image","image_url":"https://example.com/a/b.png"}]
    ),
  )
}

///|
/// Field order is preserved. Every reference SDK's golden body depends on it,
/// and a body whose field order shifts between runs is miserable to diff in a
/// proxy log.
test "field order is insertion order" {
  let p = @api.Params::new()
  for key in ["z", "a", "m", "b"] {
    p.put_str(key, Some("1"))
  }
  assert_eq(@api.encode_form(p), "z=1&a=1&m=1&b=1")
}

///|
/// Repeated keys are kept, not merged. Slack has no repeated-key argument
/// today, but silently dropping one of a caller's two values would be worse
/// than sending both.
test "repeated keys are kept" {
  assert_eq(form([("k", Str("1")), ("k", Str("2"))]), "k=1&k=2")
}

///|
test "an empty parameter list is an empty body" {
  assert_eq(@api.encode_form(@api.Params::new()), "")
}

///|
/// An empty string value is a present field with no value -- which is what
/// Slack's own slash-command payloads contain (`&text=&response_url=...`).
test "an empty value keeps its field" {
  assert_eq(form([("text", Str(""))]), "text=")
}

///|
/// The property the decoder exists for: what comes out is exactly the pairs
/// that went in, as `to_wire` rendered them.
///
/// Stated modulo `to_wire` rather than as `decode(encode(p)) == p`, because the
/// wire has no types: `Int(42)` and `Str("42")` are the same four bytes, and a
/// decoder that claimed to tell them apart would be lying.
fn round_trips(
  entries : Array[(String, @api.ParamValue)],
  bool_style~ : @api.BoolStyle,
) -> Bool {
  let params = @api.Params::of(entries)
  let expected = entries.map(e => (e.0, e.1.to_wire(bool_style~)))
  @api.decode_form(@api.encode_form(params, bool_style~)) == expected
}

///|
/// Driven over the awkward set `ext/cmd/integration` sends through `api.test`,
/// which is the one place in this repo where a value is compared with what
/// SLACK decoded rather than with another SDK's expectations.
test "every encoder case decodes back to what it encoded" {
  let cases : Array[(String, @api.ParamValue)] = [
    ("team_id", Str("T12345678")),
    ("city", Str("São Paulo")),
    ("query", Str("a&b=c")),
    ("sum", Str("1+1 = 2")),
    ("emoji", Str("🎉")),
    ("percent", Str("100%")),
    ("multiline", Str("one\ntwo")),
    ("empty", Str("")),
    ("limit", Int(200)),
    ("big", I64(9007199254740993L)),
    ("frac", Num(1.5)),
    ("flag", Bool(true)),
    ("off", Bool(false)),
    ("users", Csv(["U1", "U2"])),
    ("blocks", JsonVal([{ "type": "section", "text": "*hi*" }])),
  ]
  // Named rather than `Show`n: `BoolStyle` derives Debug, not Show.
  let styles : Array[(String, @api.BoolStyle)] = [
    ("TrueFalse", TrueFalse),
    ("OneZero", OneZero),
  ]
  for style in styles {
    let (label, bool_style) = style
    assert_true(round_trips(cases, bool_style~), msg="style \{label}")
    // And one field at a time, so a failure names the value that broke.
    for entry in cases {
      assert_true(
        round_trips([entry], bool_style~),
        msg="\{entry.0} at style \{label}",
      )
    }
  }
}

///|
/// An empty body is no pairs at all -- not one pair of two empty strings, which
/// is what a naive split gives and is the bug that makes a no-argument call
/// look like a request for a channel named "".
test "an empty body decodes to nothing" {
  assert_eq(@api.decode_form(""), [])
}

///|
/// A field with no `=` is present with an empty value, which is how `a&b=1` is
/// read everywhere else.
test "a field with no equals sign keeps its name" {
  assert_eq(@api.decode_form("a"), [("a", "")])
  assert_eq(@api.decode_form("a&b=1"), [("a", ""), ("b", "1")])
}

///|
/// Empty segments are skipped, so a trailing `&` or a doubled one does not
/// invent a nameless field.
test "empty segments are skipped" {
  assert_eq(@api.decode_form("a=1&&b=2&"), [("a", "1"), ("b", "2")])
}

///|
test "repeated keys survive the round trip" {
  assert_eq(@api.decode_form("k=1&k=2"), [("k", "1"), ("k", "2")])
}

///|
/// Only the FIRST `=` splits. This encoder escapes `=` as `%3D` so it never
/// produces such a pair itself, but a body from another client can, and losing
/// everything after the second `=` would be silent data loss.
test "only the first equals sign splits a pair" {
  assert_eq(@api.decode_form("q=a=b=c"), [("q", "a=b=c")])
}

///|
/// `+` is a space on the way in. This encoder emits `%20` for a space and
/// `%2B` for a literal `+`, so the pairing is unaffected -- but every other
/// client's body means a space here.
test "plus decodes to a space" {
  assert_eq(@api.decode_form("a+b=c+d"), [("a b", "c d")])
  assert_eq(@api.decode_form("sum=1%2B1"), [("sum", "1+1")])
}

///|
/// Multi-byte characters are reassembled from their UTF-8 bytes, not from
/// UTF-16 code units. `%E2%9C%93` is three bytes and one character.
test "percent escapes decode over UTF-8 bytes" {
  assert_eq(@api.decode_form("x=%E2%9C%93"), [("x", "✓")])
  assert_eq(@api.decode_form("x=S%C3%A3o%20Paulo"), [("x", "São Paulo")])
  // An astral code point is four bytes and one code point.
  assert_eq(@api.decode_form("x=%F0%9F%8E%89"), [("x", "🎉")])
}

///|
/// Hex digits are read in either case. Slack sends uppercase; some clients
/// send lowercase, and both are legal.
test "hex escapes are case-insensitive" {
  assert_eq(@api.decode_form("x=%2f%2F"), [("x", "//")])
}

///|
/// An invalid escape is left literal rather than raising, as WHATWG's
/// urlencoded parser does. A hand-built body with one stray `%` in it is far
/// more useful decoded than rejected.
test "an invalid escape is left as written" {
  assert_eq(@api.decode_form("a=%zz"), [("a", "%zz")])
  assert_eq(@api.decode_form("a=100%"), [("a", "100%")])
  assert_eq(@api.decode_form("a=%4"), [("a", "%4")])
  assert_eq(@api.decode_form("a=%%41"), [("a", "%A")])
}
