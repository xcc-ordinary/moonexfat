// Shared little-endian readers and byte helpers.

///|
pub fn le_u16(data : Bytes, off : Int) -> Int {
  data.at(off).to_int() | (data.at(off + 1).to_int() << 8)
}

///|
pub fn le_u32(data : Bytes, off : Int) -> UInt {
  data.at(off).to_uint() |
  (data.at(off + 1).to_uint() << 8) |
  (data.at(off + 2).to_uint() << 16) |
  (data.at(off + 3).to_uint() << 24)
}

///|
pub fn le_u64(data : Bytes, off : Int) -> Int64 {
  let mut v : Int64 = 0L
  for k in 0..<8 {
    v = v | (data.at(off + k).to_int64() << (8 * k))
  }
  v
}

///|
/// Copy `len` bytes starting at `start`. Caller guarantees bounds.
pub fn slice(data : Bytes, start : Int, len : Int) -> Bytes {
  Bytes::makei(len, fn(i) { data.at(start + i) })
}

///|
/// The exFAT rotate-right-1 accumulate checksum over `data[from..<to]`,
/// with no skipped bytes (used for the Up-case Table, spec §7.2.2, and
/// entry-set checksums, spec §6.3.3).
pub fn rot_checksum(data : Bytes, from : Int, to : Int) -> UInt {
  let mut sum : UInt = 0U
  for i in from..<to {
    let carry = if (sum & 1U) == 1U { 0x80000000U } else { 0U }
    sum = carry + (sum >> 1) + data.at(i).to_uint()
  }
  sum
}