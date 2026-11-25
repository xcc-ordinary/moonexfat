// Up-case table tests. The healthy fixture's checksum 0x88E38EE3 was
// computed by an independent PowerShell implementation.

///|
fn ascii_table() -> Bytes {
  Bytes::makei(256, fn(i) {
    if i % 2 == 0 {
      let u = i / 2
      let v = if u >= 97 && u <= 122 { u - 32 } else { u }
      v.to_byte()
    } else {
      b'\x00'
    }
  })
}

///|
fn set_u16(data : Bytes, at : Int, v : Int) -> Bytes {
  Bytes::makei(data.length(), fn(i) {
    if i == at {
      (v & 0xFF).to_byte()
    } else if i == at + 1 {
      ((v >> 8) & 0xFF).to_byte()
    } else {
      data.at(i)
    }
  })
}

///|
#warnings("-result_error_return")
fn parse_result(data : Bytes, sum : UInt) -> Result[UpcaseTable, UpcaseError] {
  let t = UpcaseTable::parse(data, sum) catch { e => return Err(e) }
  Ok(t)
}

///|
fn healthy() -> UpcaseTable {
  UpcaseTable::parse(ascii_table(), 0x88E38EE3U) catch {
    _ => abort("upcase setup failed")
  }
}

///|
test "parse healthy ASCII table with independent checksum vector" {
  let t = healthy()
  assert_eq(t.length(), 128)
  assert_eq(t.upcase_char('a'), 'A')
  assert_eq(t.upcase_char('z'), 'Z')
  assert_eq(t.upcase_char('A'), 'A')
  assert_eq(t.upcase_char('0'), '0')
  assert_eq(t.upcase_string("Hello exFAT 123"), "HELLO EXFAT 123")
}

///|
test "checksum mismatch is detected" {
  assert_eq(
    parse_result(ascii_table(), 0U),
    Err(ChecksumMismatch(0U, 0x88E38EE3U)),
  )
}

///|
test "ASCII mapping rule is enforced" {
  // 'A' (65) must stay identity.
  let bad = set_u16(ascii_table(), 2 * 65, 66)
  let sum = @util.rot_checksum(bad, 0, bad.length())
  assert_eq(parse_result(bad, sum), Err(NotIdentity(65)))
  // 'a' (97) must map to 'A', not identity.
  let bad2 = set_u16(ascii_table(), 2 * 97, 97)
  let sum2 = @util.rot_checksum(bad2, 0, bad2.length())
  assert_eq(parse_result(bad2, sum2), Err(NotIdentity(97)))
}

///|
test "mapping to 0xFFFF is rejected" {
  let base = ascii_table()
  let extended = Bytes::makei(258, fn(i) {
    if i < 256 { base.at(i) } else { b'\xFF' }
  })
  let sum = @util.rot_checksum(extended, 0, extended.length())
  assert_eq(parse_result(extended, sum), Err(InvalidMapping(128)))
}

///|
test "short and odd-length tables are rejected" {
  assert_eq(
    parse_result(Bytes::make(100, b'\x00'), 0U),
    Err(TableTooShort(100)),
  )
  assert_eq(
    parse_result(Bytes::make(257, b'\x00'), 0U),
    Err(OddLength(257)),
  )
}

///|
test "code points beyond the table pass through" {
  assert_eq(healthy().upcase_char('中'), '中')
}