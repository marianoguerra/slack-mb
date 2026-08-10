///|
/// HMAC-SHA256, RFC 2104.
///
/// `H((K ^ opad) ++ H((K ^ ipad) ++ text))`, where K is the key zero-padded to
/// the block size -- or, when the key is longer than a block, `H(key)` padded
/// the same way. That last case is the one implementations get wrong, which is
/// why RFC 4231 devotes two of its seven vectors to it.
pub fn hmac_sha256(key : BytesView, message : BytesView) -> Bytes {
  let block = FixedArray::make(block_size, b'\x00')
  if key.length() > block_size {
    let hashed = sha256(key)
    for i in 0..<hashed.length() {
      block[i] = hashed[i]
    }
  } else {
    for i in 0..<key.length() {
      block[i] = key[i]
    }
  }
  let inner = Sha256::new()
  let ipad : Array[Byte] = Array::make(block_size, b'\x00')
  for i in 0..<block_size {
    ipad[i] = block[i] ^ b'\x36'
  }
  inner.update(Bytes::from_array(ipad[:])[:])
  inner.update(message)
  let inner_digest = inner.finish()
  let outer = Sha256::new()
  let opad : Array[Byte] = Array::make(block_size, b'\x00')
  for i in 0..<block_size {
    opad[i] = block[i] ^ b'\x5c'
  }
  outer.update(Bytes::from_array(opad[:])[:])
  outer.update(inner_digest[:])
  outer.finish()
}
