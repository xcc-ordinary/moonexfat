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

// ---- W3: file directory entry sets (spec §6.3, §7.4, §7.5) ----

///|
#derive(Debug, Eq)
pub suberror EntriesError {
  TruncatedSet(Int)
  BadSecondaryCount(Int)
  SetChecksumMismatch(Int, Int)
  MissingStream(Int)
  BadFileNameEntry(Int)
  NameLengthInvalid(Int)
  NameHashMismatch(Int, Int)
}

///|
pub fn EntriesError::message(self : EntriesError) -> String {
  match self {
    TruncatedSet(i) => "directory entry set at \{i} is truncated"
    BadSecondaryCount(n) => "file entry SecondaryCount \{n} out of range 2..18"
    SetChecksumMismatch(expected, actual) =>
      "entry set checksum mismatch: expected 0x\{expected.to_string(radix=16)}, found 0x\{actual.to_string(radix=16)}"
    MissingStream(i) => "file entry at \{i} lacks a Stream Extension (0xC0)"
    BadFileNameEntry(i) => "expected File Name entry (0xC1) at \{i}"
    NameLengthInvalid(n) => "NameLength \{n} does not fit the file name entries"
    NameHashMismatch(expected, actual) =>
      "name hash mismatch: expected 0x\{expected.to_string(radix=16)}, found 0x\{actual.to_string(radix=16)}"
  }
}

///|
/// Decoded exFAT timestamp (local time fields; UTC offset not applied).
#derive(Debug, Eq)
pub struct DateTime {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
}

///|
/// Decode the packed 32-bit exFAT timestamp (spec §7.4.7):
/// year-1980 (7 bits), month (4), day (5), hour (5), minute (6),
/// double-second (5).
pub fn decode_timestamp(raw : UInt) -> DateTime {
  let v = raw.reinterpret_as_int()
  {
    year: 1980 + (v >> 25),
    month: (v >> 21) & 0xF,
    day: (v >> 16) & 0x1F,
    hour: (v >> 11) & 0x1F,
    minute: (v >> 5) & 0x3F,
    second: (v & 0x1F) * 2,
  }
}

///|
/// One parsed file directory entry set: File (0x85) + Stream Extension
/// (0xC0) + 1..17 File Name (0xC1) entries.
#derive(Debug, Eq)
pub struct FileEntry {
  name : String
  attributes : Int
  first_cluster : UInt
  data_length : Int64
  valid_data_length : Int64
  no_fat_chain : Bool
  modified : DateTime
  deleted : Bool
  created : DateTime
  accessed : DateTime
  create_10ms : Int
  modified_10ms : Int
  utc_offset_minutes : Int?
}

///|
/// Decode a UTC-offset byte (spec §7.4.9): bit 7 marks validity, the low
/// 7 bits are a two's-complement count of 15-minute increments.
pub fn decode_utc_offset(raw : Int) -> Int? {
  if (raw & 0x80) == 0 {
    return None
  }
  let v = raw & 0x7F
  let signed = if v >= 64 {
    v - 128
  } else {
    v
  }
  Some(signed * 15)
}

///|
/// Human-readable attribute flags (spec §7.4.3).
pub fn attribute_string(attrs : Int) -> String {
  let parts : Array[String] = []
  if (attrs & 0x01) != 0 {
    parts.push("READONLY")
  }
  if (attrs & 0x02) != 0 {
    parts.push("HIDDEN")
  }
  if (attrs & 0x04) != 0 {
    parts.push("SYSTEM")
  }
  if (attrs & 0x10) != 0 {
    parts.push("DIRECTORY")
  }
  if (attrs & 0x20) != 0 {
    parts.push("ARCHIVE")
  }
  if parts.length() == 0 {
    "NONE"
  } else {
    parts.join(" ")
  }
}

///|
pub fn FileEntry::is_dir(self : FileEntry) -> Bool {
  (self.attributes & 0x10) != 0
}

///|
fn hash_step(h : Int, byte : Int) -> Int {
  (((h << 15) | (h >> 1)) + byte) & 0xFFFF
}

///|
/// NameHash (spec §7.4.2): rotate-right-1 accumulate over the UTF-16LE
/// bytes of the up-cased name, modulo 2^16.
pub fn name_hash(name : String, upcase : @upcase.UpcaseTable) -> Int {
  let up = upcase.upcase_string(name)
  let mut h = 0
  for c in up.iter() {
    let u = c.to_int()
    if u > 0xFFFF {
      let v = u - 0x10000
      let hi = 0xD800 + (v >> 10)
      let lo = 0xDC00 + (v & 0x3FF)
      h = hash_step(h, hi & 0xFF)
      h = hash_step(h, hi >> 8)
      h = hash_step(h, lo & 0xFF)
      h = hash_step(h, lo >> 8)
    } else {
      h = hash_step(h, u & 0xFF)
      h = hash_step(h, (u >> 8) & 0xFF)
    }
  }
  h
}

///|
/// List the live file entry sets of a directory. Special metadata entries
/// (0x81/0x82/0x83) are skipped, deleted sets (0x05) are skipped via
/// SecondaryCount, and scanning stops at the end marker (0x00).
/// Each set's SetChecksum (§6.3.3) is verified; when `upcase` is given,
/// the NameHash is verified too.
pub fn list_dir(
  dir : Bytes,
  upcase : @upcase.UpcaseTable?,
) -> Array[FileEntry] raise EntriesError {
  scan(dir, upcase, deleted=false)
}

///|
/// List deleted file entry sets (InUse bit cleared: 0x05/0x40/0x41).
/// Deletion clears the InUse bits without recomputing SetChecksum, so
/// the stored set checksum is stale by design and is not verified here;
/// NameHash still covers the unchanged name and is verified.
pub fn list_deleted(
  dir : Bytes,
  upcase : @upcase.UpcaseTable?,
) -> Array[FileEntry] raise EntriesError {
  scan(dir, upcase, deleted=true)
}

///|
fn scan(
  dir : Bytes,
  upcase : @upcase.UpcaseTable?,
  deleted~ : Bool,
) -> Array[FileEntry] raise EntriesError {
  let file_type = if deleted {
    0x05
  } else {
    0x85
  }
  let stream_type = if deleted {
    0x40
  } else {
    0xC0
  }
  let name_type = if deleted {
    0x41
  } else {
    0xC1
  }
  let out : Array[FileEntry] = []
  let mut i = 0
  while i + 32 <= dir.length() {
    let t = dir.at(i).to_int()
    if t == 0 {
      break
    }
    if t == file_type {
      let sc = dir.at(i + 1).to_int()
      guard sc >= 2 && sc <= 18 else {
        raise BadSecondaryCount(sc)
      }
      let total = 32 * (1 + sc)
      guard i + total <= dir.length() else {
        raise TruncatedSet(i)
      }
      if !deleted {
        // SetChecksum (§7.4.1.2): 16-bit rotate-right-1 accumulate over
        // the whole set, excluding the 2-byte SetChecksum field itself.
        let mut sum = 0
        for k in 0..<total {
          if k == 2 || k == 3 {
            continue
          }
          sum = (((sum & 1) << 15) + (sum >> 1) + dir.at(i + k).to_int()) & 0xFFFF
        }
        let expected = @util.le_u16(dir, i + 2)
        guard sum == expected else {
          raise SetChecksumMismatch(expected, sum)
        }
      }
      guard dir.at(i + 32).to_int() == stream_type else {
        raise MissingStream(i)
      }
      let flags = dir.at(i + 33).to_int()
      let name_len = dir.at(i + 35).to_int()
      let stored_hash = @util.le_u16(dir, i + 36)
      let vdl = @util.le_u64(dir, i + 40)
      let fc = @util.le_u32(dir, i + 52)
      let dl = @util.le_u64(dir, i + 56)
      guard name_len >= 1 && name_len <= 15 * (sc - 1) else {
        raise NameLengthInvalid(name_len)
      }
      let units : Array[Int] = []
      for k in 0..<(sc - 1) {
        let base = i + 64 + 32 * k
        guard dir.at(base).to_int() == name_type else {
          raise BadFileNameEntry(base)
        }
        for j in 0..<15 {
          if units.length() < name_len {
            units.push(@util.le_u16(dir, base + 2 + 2 * j))
          }
        }
      }
      let chars : Array[Char] = []
      let mut k = 0
      while k < units.length() {
        let u = units[k]
        if u >= 0xD800 && u <= 0xDBFF && k + 1 < units.length() &&
              units[k + 1] >= 0xDC00 && units[k + 1] <= 0xDFFF {
          let cp = 0x10000 + ((u - 0xD800) << 10) + (units[k + 1] - 0xDC00)
          chars.push(cp.unsafe_to_char())
          k = k + 2
        } else {
          if u < 0xD800 || u > 0xDFFF {
            chars.push(u.unsafe_to_char())
          }
          k = k + 1
        }
      }
      let name = String::from_array(chars)
      match upcase {
        Some(uc) => {
          let h = name_hash(name, uc)
          guard h == stored_hash else {
            raise NameHashMismatch(stored_hash, h)
          }
        }
        None => ()
      }
      out.push({
        name,
        attributes: @util.le_u16(dir, i + 4),
        first_cluster: fc,
        data_length: dl,
        valid_data_length: vdl,
        no_fat_chain: (flags & 2) != 0,
        modified: decode_timestamp(@util.le_u32(dir, i + 12)),
        deleted,
        created: decode_timestamp(@util.le_u32(dir, i + 8)),
        accessed: decode_timestamp(@util.le_u32(dir, i + 16)),
        create_10ms: dir.at(i + 20).to_int(),
        modified_10ms: dir.at(i + 21).to_int(),
        utc_offset_minutes: decode_utc_offset(dir.at(i + 23).to_int()),
      })
      i = i + total
    } else if t == (if deleted { 0x85 } else { 0x05 }) {
      i = i + 32 * (1 + dir.at(i + 1).to_int())
    } else if (t & 0x80) == 0 {
      i = i + 32
    } else if t >= 0xA0 && t <= 0xBF {
      i = i + 32 * (1 + dir.at(i + 1).to_int())
    } else {
      i = i + 32
    }
  }
  out
}