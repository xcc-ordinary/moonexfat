// exFAT Up-case Table (spec §7.2): UTF-16 code-unit mapping used for
// case-insensitive name comparison, with its own TableChecksum (§7.2.2).
// The on-disk table may be compressed: a 0xFFFF unit followed by a count
// N means the next N code points map to themselves. The checksum covers
// the compressed on-disk bytes; validation applies to the expanded table.

///|
#derive(Debug, Eq)
pub suberror UpcaseError {
  ChecksumMismatch(UInt, UInt)
  TableTooShort(Int)
  OddLength(Int)
  NotIdentity(Int)
  TruncatedCompression(Int)
  InvalidCompression(Int)
}

///|
pub fn UpcaseError::message(self : UpcaseError) -> String {
  match self {
    ChecksumMismatch(expected, actual) =>
      "up-case checksum mismatch: expected 0x\{expected.to_string(radix=16)}, found 0x\{actual.to_string(radix=16)}"
    TableTooShort(n) => "up-case table expands to \{n} entries, needs at least 128"
    OddLength(n) => "up-case table length \{n} is not a multiple of 2"
    NotIdentity(i) => "up-case entry \{i} violates the ASCII mapping rule"
    TruncatedCompression(i) =>
      "up-case compression marker at entry \{i} has no following count"
    InvalidCompression(n) =>
      "up-case compression count \{n} is zero or overflows the code-point space"
  }
}

///|
#derive(Debug, Eq)
pub struct UpcaseTable {
  table : Array[Int]
}

///|
/// Parse and validate an Up-case Table against the checksum stored in its
/// directory entry. The checksum is computed over the raw (possibly
/// compressed) bytes; 0xFFFF compression markers are then expanded.
/// Checks on the expanded table: at least 128 entries and the ASCII
/// mapping rule (a-z map to A-Z, other code points 0..127 are identity).
pub fn UpcaseTable::parse(
  data : Bytes,
  checksum : UInt,
) -> UpcaseTable raise UpcaseError {
  guard data.length() % 2 == 0 else {
    raise OddLength(data.length())
  }
  let actual = @util.rot_checksum(data, 0, data.length())
  guard actual == checksum else {
    raise ChecksumMismatch(checksum, actual)
  }
  let n = data.length() / 2
  let table : Array[Int] = []
  let mut i = 0
  while i < n {
    let u = @util.le_u16(data, 2 * i)
    if u == 0xFFFF && i + 1 < n {
      // Compression marker: the next unit counts identity mappings.
      let count = @util.le_u16(data, 2 * (i + 1))
      guard count >= 1 && table.length() + count <= 0x10000 else {
        raise InvalidCompression(count)
      }
      for _ in 0..<count {
        table.push(table.length())
      }
      i = i + 2
    } else if u == 0xFFFF {
      // A bare trailing 0xFFFF is the literal identity mapping of the
      // last code point 0xFFFF (as in the spec's recommended table).
      guard table.length() == 0xFFFF else {
        raise TruncatedCompression(table.length())
      }
      table.push(0xFFFF)
      i = i + 1
    } else {
      table.push(u)
      i = i + 1
    }
  }
  guard table.length() >= 128 else {
    raise TableTooShort(table.length())
  }
  for i in 0..<128 {
    let expected = if i >= 97 && i <= 122 { i - 32 } else { i }
    guard table[i] == expected else {
      raise NotIdentity(i)
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