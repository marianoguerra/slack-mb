// SHA-256, FIPS 180-4 / RFC 6234.
//
// A straight transcription: the variable names below are the ones in the
// standard (`w`, `a`..`h`, `ch`, `maj`, the four sigmas), because a reader
// checking this against the spec should not also have to translate names.

///|
/// Round constants: the first 32 bits of the fractional parts of the cube roots
/// of the first 64 primes.
let k : FixedArray[UInt] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
  0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
  0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
  0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
  0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
  0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
  0xc67178f2,
]

///|
/// Initial hash value: the first 32 bits of the fractional parts of the square
/// roots of the first 8 primes.
let init_state : FixedArray[UInt] = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
  0x5be0cd19,
]

///|
/// The block size in bytes. Public because HMAC's key padding is defined in
/// terms of it, and so is RFC 4231's "longer than block-size key" case.
pub let block_size : Int = 64

///|
/// The digest size in bytes.
pub let digest_size : Int = 32

///|
fn rotr(x : UInt, n : Int) -> UInt {
  (x >> n) | (x << (32 - n))
}

///|
/// A streaming SHA-256.
///
/// Streaming rather than one-shot because HMAC needs to hash
/// `key_pad ++ message` without materialising the concatenation, and because a
/// caller hashing a large request body should not have to hold a second copy of
/// it. `sha256` is the one-shot convenience on top.
pub struct Sha256 {
  state : FixedArray[UInt]
  /// Bytes not yet absorbed into `state`; always fewer than `block_size`.
  buf : FixedArray[Byte]
  mut buf_len : Int
  /// Total bytes fed in, for the length suffix. Int64 because the padding
  /// encodes a 64-bit *bit* count and Int would overflow at 256 MB.
  mut total : Int64
}

///|
pub fn Sha256::new() -> Sha256 {
  {
    state: FixedArray::makei(8, i => init_state[i]),
    buf: FixedArray::make(block_size, b'\x00'),
    buf_len: 0,
    total: 0L,
  }
}

///|
/// Absorb one 64-byte block out of `src` starting at `off`.
fn Sha256::compress(self : Self, src : FixedArray[Byte], off : Int) -> Unit {
  let w : FixedArray[UInt] = FixedArray::make(64, 0)
  for t in 0..<16 {
    let i = off + t * 4
    w[t] = (src[i].to_uint() << 24) |
      (src[i + 1].to_uint() << 16) |
      (src[i + 2].to_uint() << 8) |
      src[i + 3].to_uint()
  }
  for t in 16..<64 {
    let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
    let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
    w[t] = w[t - 16] + s0 + w[t - 7] + s1
  }
  let mut a = self.state[0]
  let mut b = self.state[1]
  let mut c = self.state[2]
  let mut d = self.state[3]
  let mut e = self.state[4]
  let mut f = self.state[5]
  let mut g = self.state[6]
  let mut h = self.state[7]
  for t in 0..<64 {
    let big_s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
    let ch = (e & f) ^ (e.lnot() & g)
    let t1 = h + big_s1 + ch + k[t] + w[t]
    let big_s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
    let maj = (a & b) ^ (a & c) ^ (b & c)
    let t2 = big_s0 + maj
    h = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2
  }
  self.state[0] = self.state[0] + a
  self.state[1] = self.state[1] + b
  self.state[2] = self.state[2] + c
  self.state[3] = self.state[3] + d
  self.state[4] = self.state[4] + e
  self.state[5] = self.state[5] + f
  self.state[6] = self.state[6] + g
  self.state[7] = self.state[7] + h
}

///|
/// Feed more input. May be called any number of times; the result depends only
/// on the concatenation, never on how it was chunked.
pub fn Sha256::update(self : Self, data : BytesView) -> Unit {
  self.total = self.total + data.length().to_int64()
  let mut i = 0
  // Top up a partial block first, so the fast path below can copy nothing.
  if self.buf_len > 0 {
    while i < data.length() && self.buf_len < block_size {
      self.buf[self.buf_len] = data[i]
      self.buf_len += 1
      i += 1
    }
    if self.buf_len == block_size {
      self.compress(self.buf, 0)
      self.buf_len = 0
    }
  }
  // Whole blocks straight from the input.
  while data.length() - i >= block_size {
    let block = FixedArray::make(block_size, b'\x00')
    for j in 0..<block_size {
      block[j] = data[i + j]
    }
    self.compress(block, 0)
    i += block_size
  }
  // Remainder waits for the next update, or for finish().
  while i < data.length() {
    self.buf[self.buf_len] = data[i]
    self.buf_len += 1
    i += 1
  }
}

///|
/// The 32-byte digest. Consumes the hasher's state -- calling `update` after
/// this would continue from a padded state and produce nonsense, so don't.
pub fn Sha256::finish(self : Self) -> Bytes {
  let bit_len = self.total * 8L
  // 0x80, then zeros, so that the length lands in the last 8 bytes of a block.
  self.update(b"\x80"[:])
  // `update` counted that byte; the padding length is computed from the
  // pre-padding total, hence the recomputation from buf_len here.
  while self.buf_len != block_size - 8 {
    self.update(b"\x00"[:])
  }
  let tail : Array[Byte] = Array::make(8, b'\x00')
  for i in 0..<8 {
    tail[i] = ((bit_len >> ((7 - i) * 8)) & 0xffL).to_byte()
  }
  self.update(Bytes::from_array(tail[:])[:])
  let out : Array[Byte] = Array::make(digest_size, b'\x00')
  for i in 0..<8 {
    let v = self.state[i]
    out[i * 4] = (v >> 24).to_byte()
    out[i * 4 + 1] = (v >> 16).to_byte()
    out[i * 4 + 2] = (v >> 8).to_byte()
    out[i * 4 + 3] = v.to_byte()
  }
  Bytes::from_array(out[:])
}

///|
/// One-shot SHA-256.
pub fn sha256(data : BytesView) -> Bytes {
  let h = Sha256::new()
  h.update(data)
  h.finish()
}
