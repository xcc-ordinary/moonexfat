// exFAT Up-case Table (spec §7.2): UTF-16 code-unit mapping used for
// case-insensitive name comparison, with its own TableChecksum (§7.2.2).

///|
#derive(Debug, Eq)
pub suberror UpcaseError {
  ChecksumMismatch(UInt, UInt)
  TableTooShort(Int)
  OddLength(Int)
  NotIdentity(Int)
  InvalidMapping(Int)
}

///|
pub fn UpcaseError::message(self : UpcaseError) -> String {
  match self {
    ChecksumMismatch(expected, actual) =>
      "up-case checksum mismatch: expected 0x\{expected.to_string(radix=16)}, found 0x\{actual.to_string(radix=16)}"
    TableTooShort(n) => "up-case table has \{n} bytes, needs at least 256"
    OddLength(n) => "up-case table length \{n} is not a multiple of 2"
    NotIdentity(i) => "up-case entry \{i} violates the ASCII mapping rule"
    InvalidMapping(i) => "up-case entry \{i} maps to invalid 0xFFFF"
  }
}

///|
#derive(Debug, Eq)
pub struct UpcaseTable {
  table : Array[Int]
}

///|
/// Parse and validate an Up-case Table against the checksum stored in its
/// directory entry. Checks: at least 128 entries, even byte length,
/// TableChecksum, ASCII mapping rule (a-z map to A-Z, other code points
/// 0..127 are identity), and no mapping to 0xFFFF.
pub fn UpcaseTable::parse(
  data : Bytes,
  checksum : UInt,
) -> UpcaseTable raise UpcaseError {
  guard data.length() >= 256 else {
    raise TableTooShort(data.length())
  }
  guard data.length() % 2 == 0 else {
    raise OddLength(data.length())
  }
  let actual = @util.rot_checksum(data, 0, data.length())
  guard actual == checksum else {
    raise ChecksumMismatch(checksum, actual)
  }
  let n = data.length() / 2
  let table = Array::makei(n, fn(i) { @util.le_u16(data, 2 * i) })
  for i in 0..<128 {
    let expected = if i >= 97 && i <= 122 { i - 32 } else { i }
    guard table[i] == expected else {
      raise NotIdentity(i)
    }
  }
  for i in 0..<n {
    guard table[i] != 0xFFFF else {
      raise InvalidMapping(i)
    }
  }
  { table, }
}

///|
pub fn UpcaseTable::length(self : UpcaseTable) -> Int {
  self.table.length()
}

///|
/// Map one character through the table; code points beyond the table
/// are returned unchanged.
pub fn UpcaseTable::upcase_char(self : UpcaseTable, c : Char) -> Char {
  let u = c.to_int()
  if u >= 0 && u < self.table.length() {
    self.table[u].unsafe_to_char()
  } else {
    c
  }
}

///|
pub fn UpcaseTable::upcase_string(self : UpcaseTable, s : String) -> String {
  String::from_iter(s.iter().map(fn(c) { self.upcase_char(c) }))
}