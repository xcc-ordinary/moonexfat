// Boot Checksum computation (spec section 3.4).

///|
/// Compute the 32-bit Boot Checksum over the first 11 sectors of a boot
/// region. Per the spec, the VolumeFlags (bytes 106..107) and PercentInUse
/// (byte 112) fields of the Main Boot Sector are excluded, because the
/// filesystem may mutate them without resealing the checksum.
///
/// Step: `checksum = rotate_right(checksum, 1) + byte` (mod 2^32).
pub fn boot_checksum(
  data : Bytes,
  sector_size : Int,
) -> UInt raise BootError {
  let n = 11 * sector_size
  guard data.length() >= n else {
    raise Truncated("boot checksum needs 11 sectors (\{n} bytes)")
  }
  let mut sum : UInt = 0U
  for i in 0..<n {
    if i == 106 || i == 107 || i == 112 {
      continue
    }
    let carry = if (sum & 1U) == 1U { 0x80000000U } else { 0U }
    sum = carry + (sum >> 1) + data.at(i).to_uint()
  }
  sum
}