// Full boot-region verification: sectors 0..11.

///|
/// Verify the Main Boot Region (sectors 0..11) at the start of `data`:
///
/// 1. parse and validate the Main Boot Sector (sector 0);
/// 2. check the 0xAA55 signature of every Extended Boot Sector (1..8);
/// 3. recompute the Boot Checksum over sectors 0..10 and require every
///    4-byte repetition in the Boot Checksum sector (11) to match.
///
/// Returns the validated boot fields on success.
pub fn verify_boot_region(data : Bytes) -> BootRegion raise BootError {
  let boot = parse_boot_sector(data)
  let size = boot.sector_size()
  guard data.length() >= 12 * size else {
    raise Truncated("boot region needs 12 sectors (\{12 * size} bytes)")
  }
  for s in 1..<9 {
    let base = s * size
    guard data.at(base + size - 2) == b'\x55' &&
          data.at(base + size - 1) == b'\xAA' else {
      raise BadSignature(s)
    }
  }
  let expected = boot_checksum(data, size)
  let base = 11 * size
  for k in 0..<(size / 4) {
    let actual = le_u32(data, base + 4 * k)
    guard actual == expected else {
      raise ChecksumMismatch(expected, actual)
    }
  }
  boot
}