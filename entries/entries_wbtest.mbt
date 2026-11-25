// Root-directory scanning tests.

///|
fn entry(t : Int, secondary_count : Int, first_cluster : UInt, len : Int64) -> Bytes {
  Bytes::makei(32, fn(i) {
    match i {
      0 => t.to_byte()
      1 => secondary_count.to_byte()
      20 => (first_cluster & 0xFFU).to_byte()
      _ =>
        if i >= 24 && i < 32 {
          ((len >> ((i - 24) * 8)) & 0xFFL).to_int().to_byte()
        } else {
          b'\x00'
        }
    }
  })
}

///|
fn concat(parts : Array[Bytes]) -> Bytes {
  let total = parts.fold(init=0, fn(acc, p) { acc + p.length() })
  Bytes::makei(total, fn(i) {
    let mut off = 0
    for p in parts {
      if i < off + p.length() {
        return p.at(i - off)
      }
      off = off + p.length()
    }
    b'\x00'
  })
}

///|
test "find bitmap and up-case entries" {
  let dir = concat([
    entry(0x81, 0, 3U, 61L),
    entry(0x82, 0, 4U, 256L),
    Bytes::make(32, b'\x00'),
  ])
  let bm = find_special(dir, 0x81).unwrap()
  assert_eq(bm.first_cluster, 3U)
  assert_eq(bm.data_length, 61L)
  let uc = find_special(dir, 0x82).unwrap()
  assert_eq(uc.first_cluster, 4U)
  assert_eq(uc.data_length, 256L)
}

///|
test "file entry sets are skipped via SecondaryCount" {
  let dir = concat([
    entry(0x85, 2, 9U, 100L), // file primary + 2 secondaries
    entry(0xC0, 0, 0U, 0L),
    entry(0xC1, 0, 0U, 0L),
    entry(0x81, 0, 3U, 61L),
    Bytes::make(32, b'\x00'),
  ])
  let bm = find_special(dir, 0x81).unwrap()
  assert_eq(bm.first_cluster, 3U)
}

///|
test "end-of-directory stops the scan" {
  let dir = concat([
    Bytes::make(32, b'\x00'),
    entry(0x81, 0, 3U, 61L), // after end marker: must NOT be found
  ])
  assert_eq(find_special(dir, 0x81), None)
}

///|
test "volume label decoding" {
  let label = Bytes::makei(32, fn(i) {
    match i {
      0 => b'\x83'
      1 => b'\x04'
      2 => b'T'
      4 => b'E'
      6 => b'S'
      8 => b'T'
      _ => b'\x00'
    }
  })
  assert_eq(volume_label(label), Some("TEST"))
  assert_eq(volume_label(Bytes::make(64, b'\x00')), None)
}
///|
test "UTC offset decoding" {
  assert_eq(decode_utc_offset(0x80), Some(0))
  assert_eq(decode_utc_offset(0x80 | 32), Some(480)) // UTC+8
  assert_eq(decode_utc_offset(0x80 | 0x7C), Some(-60)) // -4 * 15
  assert_eq(decode_utc_offset(0x20), None) // validity bit clear
}

///|
test "attribute string" {
  assert_eq(attribute_string(0x20), "ARCHIVE")
  assert_eq(attribute_string(0x10), "DIRECTORY")
  assert_eq(attribute_string(0x01 | 0x02 | 0x04), "READONLY HIDDEN SYSTEM")
  assert_eq(attribute_string(0), "NONE")
}
