// Tests for boot-region parsing, validation and checksum.
//
// The synthetic fixture below mirrors testdata/synthetic.exfat. Its expected
// boot checksum 0x829BD81D was computed by an INDEPENDENT implementation
// (a PowerShell script following the spec pseudocode), so the checksum test
// is a cross-validation, not a self-consistency check.

///|
fn synthetic() -> Bytes {
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
      // VolumeLength = 131072 = 0x00020000
      74 => b'\x02'
      // FatOffset = 24
      80 => b'\x18'
      // FatLength = 128
      84 => b'\x80'
      // ClusterHeapOffset = 152
      88 => b'\x98'
      // ClusterCount = 16365 = 0x3FED
      92 => b'\xED'
      93 => b'\x3F'
      // FirstClusterOfRootDirectory = 4
      96 => b'\x04'
      // VolumeSerialNumber = 0x1234ABCD
      100 => b'\xCD'
      101 => b'\xAB'
      102 => b'\x34'
      103 => b'\x12'
      // FileSystemRevision = 0x0100
      105 => b'\x01'
      108 => b'\x09' // BytesPerSectorShift = 9
      109 => b'\x03' // SectorsPerClusterShift = 3
      110 => b'\x01' // NumberOfFats = 1
      111 => b'\x80' // DriveSelect
      _ =>
        if i < 4608 && i % 512 == 510 {
          b'\x55'
        } else if i < 4608 && i % 512 == 511 {
          b'\xAA'
        } else if i >= 5632 {
          // Boot checksum 0x829BD81D, little-endian, repeated 128 times.
          match (i - 5632) % 4 {
            0 => b'\x1D'
            1 => b'\xD8'
            2 => b'\x9B'
            _ => b'\x82'
          }
        } else {
          b'\x00'
        }
    }
  })
}

///|
fn set_byte(img : Bytes, at : Int, v : Byte) -> Bytes {
  Bytes::makei(img.length(), fn(i) { if i == at { v } else { img.at(i) } })
}

///|
fn set_u32(img : Bytes, off : Int, v : UInt) -> Bytes {
  Bytes::makei(img.length(), fn(i) {
    if i >= off && i < off + 4 {
      ((v >> ((i - off) * 8)) & 0xFFU).to_byte()
    } else {
      img.at(i)
    }
  })
}

///|
#warnings("-result_error_return")
fn parse_result(img : Bytes) -> Result[BootRegion, BootError] {
  let b = parse_boot_sector(img) catch { e => return Err(e) }
  Ok(b)
}

///|
#warnings("-result_error_return")
fn verify_result(img : Bytes) -> Result[BootRegion, BootError] {
  let b = verify_boot_region(img) catch { e => return Err(e) }
  Ok(b)
}

///|
#warnings("-result_error_return")
fn offset_result(b : BootRegion, cluster : UInt) -> Result[Int64, BootError] {
  let v = b.cluster_offset(cluster) catch { e => return Err(e) }
  Ok(v)
}

///|
test "parse synthetic boot sector fields" {
  let b = parse_boot_sector(synthetic()) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(b.partition_offset, 0L)
  assert_eq(b.volume_length, 131072L)
  assert_eq(b.fat_offset, 24U)
  assert_eq(b.fat_length, 128U)
  assert_eq(b.cluster_heap_offset, 152U)
  assert_eq(b.cluster_count, 16365U)
  assert_eq(b.root_dir_cluster, 4U)
  assert_eq(b.volume_serial, 0x1234ABCDU)
  assert_eq(b.fs_revision, 0x0100)
  assert_eq(b.bytes_per_sector_shift, 9)
  assert_eq(b.sectors_per_cluster_shift, 3)
  assert_eq(b.number_of_fats, 1)
  assert_eq(b.percent_in_use, 0)
}

///|
test "boot checksum matches independent vector 0x829BD81D" {
  let sum = boot_checksum(synthetic(), 512) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(sum, 0x829BD81DU)
}

///|
test "verify full boot region succeeds" {
  assert_true(
    match verify_result(synthetic()) {
      Ok(_) => true
      Err(_) => false
    },
  )
}

///|
test "geometry helpers and cluster offsets" {
  let b = parse_boot_sector(synthetic()) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(b.sector_size(), 512)
  assert_eq(b.sectors_per_cluster(), 8)
  assert_eq(b.cluster_size(), 4096)
  assert_eq(offset_result(b, 2U), Ok(77824L))
  assert_eq(offset_result(b, 4U), Ok(86016L))
  assert_eq(offset_result(b, 16366U), Ok(67104768L))
  assert_eq(offset_result(b, 1U), Err(BadClusterIndex(1U)))
  assert_eq(offset_result(b, 16367U), Err(BadClusterIndex(16367U)))
}

///|
test "reject bad JumpBoot" {
  assert_eq(parse_result(set_byte(synthetic(), 0, b'\x00')), Err(BadJumpBoot))
}

///|
test "reject bad FileSystemName" {
  assert_eq(parse_result(set_byte(synthetic(), 3, b'e')), Err(BadFileSystemName))
}

///|
test "reject non-zero MustBeZero" {
  assert_eq(
    parse_result(set_byte(synthetic(), 20, b'\x01')),
    Err(NonZeroMustBeZero(20)),
  )
}

///|
test "reject bad sector shifts" {
  assert_eq(
    parse_result(set_byte(synthetic(), 108, b'\x08')),
    Err(BadSectorShift(8)),
  )
  assert_eq(
    parse_result(set_byte(synthetic(), 108, b'\x0D')),
    Err(BadSectorShift(13)),
  )
}

///|
test "reject cluster larger than 32 MiB" {
  assert_eq(
    parse_result(set_byte(synthetic(), 109, b'\x11')),
    Err(BadClusterShift(17)),
  )
}

///|
test "reject bad NumberOfFats" {
  assert_eq(
    parse_result(set_byte(synthetic(), 110, b'\x00')),
    Err(BadNumberOfFats(0)),
  )
  assert_eq(
    parse_result(set_byte(synthetic(), 110, b'\x03')),
    Err(BadNumberOfFats(3)),
  )
}

///|
test "PercentInUse: 101 invalid, 255 (unknown) valid" {
  assert_eq(
    parse_result(set_byte(synthetic(), 112, b'\x65')),
    Err(BadPercentInUse(101)),
  )
  assert_true(
    match parse_result(set_byte(synthetic(), 112, b'\xFF')) {
      Ok(_) => true
      Err(_) => false
    },
  )
}

///|
test "reject unknown major revision" {
  assert_eq(
    parse_result(set_byte(synthetic(), 105, b'\x02')),
    Err(BadRevision(512)),
  )
}

///|
test "reject FatOffset behind boot regions" {
  assert_eq(parse_result(set_u32(synthetic(), 80, 12U)), Err(BadFatOffset(12U)))
}

///|
test "reject FAT too small for cluster count" {
  assert_eq(parse_result(set_u32(synthetic(), 84, 1U)), Err(BadFatLength(1U)))
}

///|
test "reject cluster heap overlapping FAT" {
  assert_eq(
    parse_result(set_u32(synthetic(), 88, 100U)),
    Err(BadClusterHeapOffset(100U)),
  )
}

///|
test "reject zero ClusterCount" {
  assert_eq(parse_result(set_u32(synthetic(), 92, 0U)), Err(BadClusterCount(0U)))
}

///|
test "reject root cluster out of range" {
  assert_eq(parse_result(set_u32(synthetic(), 96, 1U)), Err(BadRootCluster(1U)))
}

///|
test "reject volume smaller than cluster heap" {
  assert_eq(
    parse_result(set_u32(synthetic(), 72, 1000U)),
    Err(VolumeTooSmall(1000L)),
  )
}

///|
test "reject missing signature in sector 0" {
  assert_eq(
    parse_result(set_byte(synthetic(), 510, b'\x00')),
    Err(BadSignature(0)),
  )
}

///|
test "reject missing signature in extended sector 3" {
  assert_eq(
    verify_result(set_byte(synthetic(), 3 * 512 + 510, b'\x00')),
    Err(BadSignature(3)),
  )
}

///|
test "detect corrupted checksum repetition" {
  assert_eq(
    verify_result(set_byte(synthetic(), 5632, b'\x00')),
    Err(ChecksumMismatch(0x829BD81DU, 0x829BD800U)),
  )
}

///|
test "checksum ignores VolumeFlags and PercentInUse mutations" {
  let img = set_byte(synthetic(), 106, b'\x03')
  let img = set_byte(img, 107, b'\x01')
  let img = set_byte(img, 112, b'\x64')
  assert_true(
    match verify_result(img) {
      Ok(_) => true
      Err(_) => false
    },
  )
}

///|
test "truncated buffers are reported" {
  assert_true(
    match parse_result(Bytes::make(100, b'\x00')) {
      Err(Truncated(_)) => true
      _ => false
    },
  )
  let img = synthetic()
  let short = Bytes::makei(5632, fn(i) { img.at(i) })
  assert_true(
    match verify_result(short) {
      Err(Truncated(_)) => true
      _ => false
    },
  )
}