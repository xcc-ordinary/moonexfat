// Disk container tests: a minimal boot-signature stub is wrapped in MBR
// and GPT containers; detection must find the exact byte offset.

///|
fn stub() -> Bytes {
  Bytes::makei(6144, fn(i) {
    match i {
      0 => b'\xEB'
      1 => b'\x76'
      2 => b'\x90'
      3 => b'E'
      4 => b'X'
      5 => b'F'
      6 => b'A'
      7 => b'T'
      8 => b' '
      9 => b' '
      10 => b' '
      _ =>
        if i % 512 == 510 {
          b'\x55'
        } else if i % 512 == 511 {
          b'\xAA'
        } else {
          b'\x00'
        }
    }
  })
}

///|
fn mbr_disk() -> Bytes {
  let s = stub()
  let start = 2048
  Bytes::makei(start * 512 + s.length(), fn(i) {
    if i >= start * 512 {
      s.at(i - start * 512)
    } else if i == 450 {
      b'\x07' // partition type: exFAT/NTFS
    } else if i >= 454 && i < 458 {
      ((start >> ((i - 454) * 8)) & 0xFF).to_byte()
    } else if i >= 458 && i < 462 {
      ((12 >> ((i - 458) * 8)) & 0xFF).to_byte()
    } else if i == 510 {
      b'\x55'
    } else if i == 511 {
      b'\xAA'
    } else {
      b'\x00'
    }
  })
}

///|
fn gpt_disk() -> Bytes {
  let s = stub()
  let start = 2048
  let guid = [
    0xA2, 0xA0, 0xD0, 0xEB, 0xE5, 0xB9, 0x33, 0x44, 0x87, 0xC0, 0x68, 0xB6,
    0xB7, 0x26, 0x99, 0xC7,
  ]
  Bytes::makei(start * 512 + s.length(), fn(i) {
    if i >= start * 512 {
      s.at(i - start * 512)
    } else if i >= 512 && i < 520 {
      "EFI PART"[i - 512].to_int().to_byte()
    } else if i == 584 {
      b'\x02' // partition entry LBA = 2
    } else if i == 592 {
      b'\x01' // 1 entry
    } else if i == 596 {
      b'\x80' // entry size 128
    } else if i >= 1024 && i < 1040 {
      guid[i - 1024].to_byte()
    } else if i >= 1056 && i < 1064 {
      // start LBA 2048; literal bytes avoid wasm 32-bit shift masking
      [0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00][i - 1056].to_byte()
    } else if i >= 1064 && i < 1072 {
      // end LBA 2059
      [0x0B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00][i - 1064].to_byte()
    } else if i == 510 {
      b'\x55' // protective MBR signature
    } else if i == 511 {
      b'\xAA'
    } else if i == 450 {
      b'\xEE' // protective MBR type
    } else {
      b'\x00'
    }
  })
}

///|
test "raw volume detected at offset 0" {
  assert_eq(exfat_offset(stub()), Some(0L))
}

///|
test "MBR partition detected" {
  let img = mbr_disk()
  let parts = mbr_partitions(img)
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].start_lba, 2048L)
  assert_eq(parts[0].lba_count, 12L)
  assert_eq(exfat_offset(img), Some(1048576L))
}

///|
test "GPT basic-data partition detected" {
  let img = gpt_disk()
  let parts = gpt_partitions(img)
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].start_lba, 2048L)
  assert_eq(parts[0].lba_count, 12L)
  assert_eq(exfat_offset(img), Some(1048576L))
}

///|
test "non-exFAT images yield no offset" {
  assert_eq(exfat_offset(Bytes::make(4096, b'\x00')), None)
  // MBR container whose partition does not hold exFAT.
  let img = Bytes::makei(2048 * 512 + 6144, fn(i) {
    if i == 450 {
      b'\x07'
    } else if i >= 454 && i < 458 {
      ((2048 >> ((i - 454) * 8)) & 0xFF).to_byte()
    } else if i == 510 {
      b'\x55'
    } else if i == 511 {
      b'\xAA'
    } else {
      b'\x00'
    }
  })
  assert_eq(exfat_offset(img), None)
}
