// Disk-level container support: locate an exFAT volume inside a full
// disk image (raw volume, MBR-partitioned disk or GPT disk). Read-only;
// partition tables are parsed just far enough to find candidate offsets,
// which are then confirmed by the exFAT boot signature.

///|
#derive(Debug, Eq)
pub struct Partition {
  start_lba : Int64
  lba_count : Int64
  kind : String
}

///|
fn is_exfat_at(image : Bytes, off : Int64) -> Bool {
  if off < 0L || off + 11L > image.length().to_int64() {
    return false
  }
  let o = off.to_int()
  image.at(o).to_int() == 0xEB &&
  image.at(o + 1).to_int() == 0x76 &&
  image.at(o + 2).to_int() == 0x90 &&
  image.at(o + 3).to_int() == 'E'.to_int() &&
  image.at(o + 4).to_int() == 'X'.to_int() &&
  image.at(o + 5).to_int() == 'F'.to_int() &&
  image.at(o + 6).to_int() == 'A'.to_int() &&
  image.at(o + 7).to_int() == 'T'.to_int() &&
  image.at(o + 8).to_int() == ' '.to_int() &&
  image.at(o + 9).to_int() == ' '.to_int() &&
  image.at(o + 10).to_int() == ' '.to_int()
}

///|
/// Parse the four primary MBR partition entries. Returns an empty array
/// when the image does not carry an MBR signature. Any non-empty
/// partition is a candidate (formatters use 0x07, 0x0C or even 0x83 for
/// exFAT); every candidate is confirmed by the exFAT boot signature.
pub fn mbr_partitions(image : Bytes) -> Array[Partition] {
  let out : Array[Partition] = []
  if image.length() < 512 ||
    image.at(510).to_int() != 0x55 ||
    image.at(511).to_int() != 0xAA {
    return out
  }
  for k in 0..<4 {
    let base = 446 + 16 * k
    let t = image.at(base + 4).to_int()
    if t != 0 {
      let start = @util.le_u32(image, base + 8).to_int64()
      let count = @util.le_u32(image, base + 12).to_int64()
      if start > 0L && count > 0L {
        out.push({ start_lba: start, lba_count: count, kind: "mbr:0x\{t.to_string(radix=16)}" })
      }
    }
  }
  out
}

///|
/// Parse GPT partition entries of type "Microsoft Basic Data"
/// (EBD0A0A2-B9E5-4433-87C0-68B6B72699C7), the GUID used for exFAT.
pub fn gpt_partitions(image : Bytes) -> Array[Partition] {
  let out : Array[Partition] = []
  if image.length() < 1024 {
    return out
  }
  let sig = "EFI PART"
  for i in 0..<8 {
    if image.at(512 + i).to_int() != sig[i].to_int() {
      return out
    }
  }
  let entry_lba = @util.le_u64(image, 512 + 72)
  let num = @util.le_u32(image, 512 + 80).reinterpret_as_int()
  let size = @util.le_u32(image, 512 + 84).reinterpret_as_int()
  if size < 128 || size > 4096 || num > 4096 {
    return out
  }
  // Basic Data GUID in on-disk (mixed-endian) byte order.
  let guid = [
    0xA2, 0xA0, 0xD0, 0xEB, 0xE5, 0xB9, 0x33, 0x44, 0x87, 0xC0, 0x68, 0xB6,
    0xB7, 0x26, 0x99, 0xC7,
  ]
  for i in 0..<num {
    let base64 = entry_lba * 512L + (i * size).to_int64()
    if base64 + size.to_int64() > image.length().to_int64() {
      break
    }
    let base = base64.to_int()
    let mut matches = true
    for g in 0..<16 {
      if image.at(base + g).to_int() != guid[g] {
        matches = false
        break
      }
    }
    if matches {
      let start = @util.le_u64(image, base + 32)
      let end = @util.le_u64(image, base + 40)
      if end >= start && start > 0L {
        out.push({ start_lba: start, lba_count: end - start + 1L, kind: "gpt:basic-data" })
      }
    }
  }
  out
}

///|
/// Byte offset of the exFAT volume inside `image`: 0 for a raw volume,
/// otherwise the first MBR/GPT partition whose boot signature matches.
pub fn exfat_offset(image : Bytes) -> Int64? {
  if is_exfat_at(image, 0L) {
    return Some(0L)
  }
  for p in mbr_partitions(image) {
    let off = p.start_lba * 512L
    if is_exfat_at(image, off) {
      return Some(off)
    }
  }
  for p in gpt_partitions(image) {
    let off = p.start_lba * 512L
    if is_exfat_at(image, off) {
      return Some(off)
    }
  }
  None
}