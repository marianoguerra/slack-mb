// RFC 4231 §4 -- the HMAC-SHA-256 test cases, all seven.
//
// Cases 6 and 7 are the ones worth having: both use a 131-byte key, which is
// longer than SHA-256's 64-byte block, so they are the only ones that exercise
// "hash the key first". An implementation that skips that step passes cases 1-5
// and fails in production against any long signing secret.

///|
fn hex(s : String) -> Bytes {
  match @crypto.of_hex(s) {
    Some(b) => b
    None => abort("bad hex in test data: \{s}")
  }
}

///|
fn repeated(byte : Byte, n : Int) -> Bytes {
  Bytes::from_array(Array::make(n, byte)[:])
}

///|
fn mac(key : Bytes, data : Bytes) -> String {
  @crypto.to_hex(@crypto.hmac_sha256(key[:], data[:])[:])
}

///|
test "RFC 4231 case 1 -- 20-byte key" {
  assert_eq(
    mac(repeated(b'\x0b', 20), ascii("Hi There")),
    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
  )
}

///|
/// A key shorter than the block size, which must be zero-padded rather than
/// hashed.
test "RFC 4231 case 2 -- short key, short data" {
  assert_eq(
    mac(ascii("Jefe"), ascii("what do ya want for nothing?")),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  )
}

///|
test "RFC 4231 case 3 -- 20-byte key, 50 bytes of 0xdd" {
  assert_eq(
    mac(repeated(b'\xaa', 20), repeated(b'\xdd', 50)),
    "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe",
  )
}

///|
test "RFC 4231 case 4 -- 25-byte key, 50 bytes of 0xcd" {
  assert_eq(
    mac(
      hex("0102030405060708090a0b0c0d0e0f10111213141516171819"),
      repeated(b'\xcd', 50),
    ),
    "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b",
  )
}

///|
/// The RFC only publishes the first 128 bits for this case, so that is all this
/// asserts. Slack never truncates, so truncation is not a feature here -- the
/// test is a prefix check.
test "RFC 4231 case 5 -- truncated to 128 bits" {
  let full = @crypto.hmac_sha256(
    repeated(b'\x0c', 20)[:],
    ascii("Test With Truncation")[:],
  )
  assert_eq(@crypto.to_hex(full[0:16]), "a3b6167473100ee06e0c796c2955552b")
}

///|
test "RFC 4231 case 6 -- 131-byte key, hashed first" {
  assert_eq(
    mac(
      repeated(b'\xaa', 131),
      ascii("Test Using Larger Than Block-Size Key - Hash Key First"),
    ),
    "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
  )
}

///|
test "RFC 4231 case 7 -- 131-byte key, 152-byte data" {
  assert_eq(
    mac(
      repeated(b'\xaa', 131),
      ascii(
        "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.",
      ),
    ),
    "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2",
  )
}

///|
/// A key of exactly the block size is padded, not hashed. RFC 4231 has no
/// vector for the boundary itself, and it is the obvious place for a `>` to
/// have been written as a `>=`.
test "a key of exactly the block size is not hashed" {
  let key = repeated(b'\xaa', 64)
  let padded_key_mac = mac(key, ascii("boundary"))
  let hashed_key_mac = mac(@crypto.sha256(key[:]), ascii("boundary"))
  assert_not_eq(padded_key_mac, hashed_key_mac)
  // 65 bytes, on the other side of the boundary, IS hashed first.
  let long = repeated(b'\xaa', 65)
  assert_eq(
    mac(long, ascii("boundary")),
    mac(@crypto.sha256(long[:]), ascii("boundary")),
  )
}
