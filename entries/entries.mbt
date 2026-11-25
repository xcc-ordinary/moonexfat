// Root-directory scanning for the special metadata entries (spec §7):
// Allocation Bitmap (0x81), Up-case Table (0x82), Volume Label (0x83).
// File entry sets (0x85 + secondaries) are skipped correctly; full file
// parsing arrives in W3.

///|
/// A located special metadata entry. `table_checksum` is only meaningful
/// for the Up-case Table entry (0x82).
#derive(Debug, Eq)
pub struct SpecialEntry {
  entry_type : Int
  first_cluster : UInt
  data_length : Int64
  table_checksum : UInt
}

///|
/// Byte offset of the first entry of type `entry_type`, or None.
/// Scanning stops at the end-of-directory marker (0x00). File entry sets
/// (primary 0x85) are skipped using their SecondaryCount field.
fn find_entry(dir : Bytes, entry_type : Int) -> Int? {
  let mut i = 0
  while i + 32 <= dir.length() {
    let t = dir.at(i).to_int()
    if t == 0 {
      break
    }
    if t == entry_type {
      return Some(i)
    }
    if t == 0x85 {
      i = i + 32 * (1 + dir.at(i + 1).to_int())
    } else {
      i = i + 32
    }
  }
  None
}

///|
/// Locate the Allocation Bitmap (0x81) or Up-case Table (0x82) entry.
pub fn find_special(dir : Bytes, entry_type : Int) -> SpecialEntry? {
  guard entry_type == 0x81 || entry_type == 0x82 else {
    return None
  }
  match find_entry(dir, entry_type) {
    Some(i) =>
      Some({
        entry_type,
        first_cluster: @util.le_u32(dir, i + 20),
        data_length: @util.le_u64(dir, i + 24),
        table_checksum: @util.le_u32(dir, i + 4),
      })
    None => None
  }
}

///|
/// Read the Volume Label (0x83), if present. Surrogate code units are
/// skipped (labels are at most 11 UTF-16 units).
pub fn volume_label(dir : Bytes) -> String? {
  match find_entry(dir, 0x83) {
    Some(i) => {
      let count = dir.at(i + 1).to_int()
      guard count <= 11 else {
        return None
      }
      let chars : Array[Char] = []
      for k in 0..<count {
        let u = @util.le_u16(dir, i + 2 + 2 * k)
        if u < 0xD800 || u > 0xDFFF {
          chars.push(u.unsafe_to_char())
        }
      }
      Some(String::from_array(chars))
    }
    None => None
  }
}