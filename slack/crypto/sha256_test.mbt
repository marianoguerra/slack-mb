// The SHA-256 vectors from FIPS 180-4 / RFC 6234 §8.5.
//
// These are the reason this package was written first: the algorithm has no
// MoonBit precedent to copy, and its correctness is binary. If they pass, the
// Slack signature vectors in @signature are testing Slack's construction rather
// than this file.

///|
/// The UTF-8 bytes of an ASCII test vector.
fn ascii(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
test "the empty string" {
  assert_eq(
    @crypto.to_hex(@crypto.sha256(ascii("")[:])[:]),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
}

///|
test "abc" {
  assert_eq(
    @crypto.to_hex(@crypto.sha256(ascii("abc")[:])[:]),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
/// 448 bits: one byte short of needing a second padding block, which is where
/// an off-by-one in the padding shows up.
test "the 448-bit vector" {
  let msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  assert_eq(msg.length(), 56)
  assert_eq(
    @crypto.to_hex(@crypto.sha256(ascii(msg)[:])[:]),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}

///|
/// 896 bits: forces the two-block padding path.
test "the 896-bit vector" {
  let msg =
    #|abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu
  assert_eq(msg.length(), 112)
  assert_eq(
    @crypto.to_hex(@crypto.sha256(ascii(msg)[:])[:]),
    "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
  )
}

///|
/// One million 'a'. The only vector that exercises the 64-bit length field
/// beyond a byte, and the only one slow enough to be worth mentioning: it is
/// ~15,600 blocks.
test "one million a" {
  let h = @crypto.Sha256::new()
  let chunk = ascii("a".repeat(1000))
  for _ in 0..<1000 {
    h.update(chunk[:])
  }
  assert_eq(
    @crypto.to_hex(h.finish()[:]),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
  )
}

///|
/// The streaming contract: the digest depends on the concatenation, not on how
/// it was chunked. Chunk sizes are chosen to straddle the 64-byte block
/// boundary in every way that matters -- under it, exactly on it, over it.
test "chunking does not change the digest" {
  let msg = ascii("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
  let one_shot = @crypto.to_hex(@crypto.sha256(msg[:])[:])
  for size in [1, 7, 63, 64, 65, 55] {
    let h = @crypto.Sha256::new()
    let mut i = 0
    while i < msg.length() {
      let end = if i + size < msg.length() { i + size } else { msg.length() }
      h.update(msg[i:end])
      i = end
    }
    assert_eq(@crypto.to_hex(h.finish()[:]), one_shot, msg="chunk size \{size}")
  }
}

///|
test "hex round-trips" {
  let d = @crypto.sha256(ascii("abc")[:])
  let hex = @crypto.to_hex(d[:])
  guard @crypto.of_hex(hex) is Some(back) else {
    fail("of_hex rejected to_hex")
  }
  assert_eq(back, d)
}

///|
/// Malformed hex is not a mismatch to report, it is input that never had a
/// chance -- so it is None rather than an empty or partial result.
test "of_hex rejects odd lengths and non-hex characters" {
  assert_eq(@crypto.of_hex("abc"), None)
  assert_eq(@crypto.of_hex("zz"), None)
  assert_eq(@crypto.of_hex("v0"), None)
  guard @crypto.of_hex("") is Some(empty) else { fail("empty hex is valid") }
  assert_eq(empty.length(), 0)
  // Either case parses; only the output is fixed to lowercase.
  assert_eq(@crypto.of_hex("FF"), @crypto.of_hex("ff"))
}

///|
test "constant_time_eq agrees with equality" {
  let a = @crypto.sha256(ascii("abc")[:])
  let b = @crypto.sha256(ascii("abc")[:])
  let c = @crypto.sha256(ascii("abd")[:])
  assert_true(@crypto.constant_time_eq(a[:], b[:]))
  assert_false(@crypto.constant_time_eq(a[:], c[:]))
  assert_false(@crypto.constant_time_eq(a[:], a[0:31]))
  assert_true(@crypto.constant_time_eq(a[0:0], b[0:0]))
}
