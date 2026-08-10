///|
let hex_digits : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
/// Lowercase hex. Slack's `v0=` signature is lowercase, and so is every
/// signature this library will ever compare against, so there is no uppercase
/// variant to pick wrong.
pub fn to_hex(data : BytesView) -> String {
  let out = StringBuilder::new(size_hint=data.length() * 2)
  for i in 0..<data.length() {
    let b = data[i].to_int()
    out.write_char(hex_digits[b >> 4])
    out.write_char(hex_digits[b & 0xf])
  }
  out.to_string()
}

///|
/// Parse hex, either case. `None` on an odd length or a non-hex character -- a
/// malformed signature is not a mismatch to report to the caller, it is input
/// that never had a chance.
pub fn of_hex(s : String) -> Bytes? {
  if s.length() % 2 != 0 {
    return None
  }
  let out : Array[Byte] = Array::make(s.length() / 2, b'\x00')
  for i in 0..<(s.length() / 2) {
    match (nibble(s[i * 2].to_int()), nibble(s[i * 2 + 1].to_int())) {
      (Some(hi), Some(lo)) => out[i] = ((hi << 4) | lo).to_byte()
      _ => return None
    }
  }
  Some(Bytes::from_array(out[:]))
}

///|
fn nibble(c : Int) -> Int? {
  if c >= '0'.to_int() && c <= '9'.to_int() {
    Some(c - '0'.to_int())
  } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
    Some(c - 'a'.to_int() + 10)
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    Some(c - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Compare without leaking where the first difference is.
///
/// A naive `==` returns as soon as two bytes differ, and the time that takes is
/// a measurement of how much of a forged signature was correct -- enough, over
/// many attempts, to build one byte by byte. Length is not secret (a signature
/// of the wrong length is not a near-miss), so returning early on it is fine.
pub fn constant_time_eq(a : BytesView, b : BytesView) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff = 0
  for i in 0..<a.length() {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}
