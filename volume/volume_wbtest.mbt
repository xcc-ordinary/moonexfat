// Volume integration tests on an in-memory mini exFAT volume that mirrors
// testdata/mini.exfat byte for byte. Independent vectors (PowerShell):
//   boot checksum        = 0x46987370
//   up-case TableChecksum = 0x88E38EE3

///|
fn boot_byte(i : Int) -> Byte {
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
    // VolumeLength = 512 = 0x200
    73 => b'\x02'
    80 => b'\x18' // FatOffset = 24
    84 => b'\x04' // FatLength = 4
    88 => b'\x1C' // ClusterHeapOffset = 28
    // ClusterCount = 484 = 0x1E4
    92 => b'\xE4'
    93 => b'\x01'
    96 => b'\x02' // root cluster = 2
    // serial 0x20261125
    100 => b'\x25'
    101 => b'\x11'
    102 => b'\x26'
    103 => b'\x20'
    105 => b'\x01' // revision 1.0
    108 => b'\x09' // 512-byte sectors
    109 => b'\x00' // 1 sector per cluster
    110 => b'\x01' // 1 FAT
    111 => b'\x80'
    112 => b'\x01' // PercentInUse = 1
    _ =>
      if i < 4608 && i % 512 == 510 {
        b'\x55'
      } else if i < 4608 && i % 512 == 511 {
        b'\xAA'
      } else if i >= 5632 {
        // boot checksum 0x46987370 LE repeated
        match (i - 5632) % 4 {
          0 => b'\x70'
          1 => b'\x73'
          2 => b'\x98'
          _ => b'\x46'
        }
      } else {
        b'\x00'
      }
  }
}

///|
fn mini() -> Bytes {
  Bytes::makei(262144, fn(i) {
    if i < 6144 {
      boot_byte(i)
    } else if i < 12288 {
      boot_byte(i - 6144) // backup boot region
    } else if i >= 12288 && i < 12308 {
      // FAT: entry0 = media descriptor, entries 1..4 = EOC
      let j = i - 12288
      if j == 0 { b'\xF8' } else { b'\xFF' }
    } else if i == 14336 {
      b'\x81' // allocation bitmap entry
    } else if i == 14356 {
      b'\x03' // bitmap FirstCluster = 3
    } else if i == 14360 {
      b'\x3D' // bitmap DataLength = 61
    } else if i == 14368 {
      b'\x82' // up-case table entry
    } else if i >= 14372 && i < 14376 {
      // TableChecksum 0x88E38EE3 LE
      match i - 14372 {
        0 => b'\xE3'
        1 => b'\x8E'
        2 => b'\xE3'
        _ => b'\x88'
      }
    } else if i == 14388 {
      b'\x04' // up-case FirstCluster = 4
    } else if i == 14392 {
      b'\x00' // DataLength = 256 (low byte)
    } else if i == 14393 {
      b'\x01'
    } else if i == 14400 {
      b'\x83' // volume label
    } else if i == 14401 {
      b'\x04'
    } else if i == 14402 {
      b'T'
    } else if i == 14404 {
      b'E'
    } else if i == 14406 {
      b'S'
    } else if i == 14408 {
      b'T'
    } else if i == 14848 {
      b'\x07' // bitmap: clusters 2,3,4 allocated
    } else if i >= 15360 && i < 15616 {
      // up-case table: ASCII mapping, u16 LE
      let j = i - 15360
      if j % 2 == 0 {
        let u = j / 2
        let v = if u >= 97 && u <= 122 { u - 32 } else { u }
        v.to_byte()
      } else {
        b'\x00'
      }
    } else {
      b'\x00'
    }
  })
}

///|
fn set_byte(img : Bytes, at : Int, v : Byte) -> Bytes {
  Bytes::makei(img.length(), fn(i) { if i == at { v } else { img.at(i) } })
}

///|
#warnings("-result_error_return")
fn open_result(img : Bytes) -> Result[Volume, VolumeError] {
  let v = Volume::open(img) catch { e => return Err(e) }
  Ok(v)
}

///|
#warnings("-result_error_return")
fn chain_r(vol : Volume, c : UInt) -> Result[Array[UInt], VolumeError] {
  let v = vol.cluster_chain(c) catch { e => return Err(e) }
  Ok(v)
}

///|
#warnings("-result_error_return")
fn alloc_r(vol : Volume, c : UInt) -> Result[Bool, @bitmap.BitmapError] {
  let v = vol.bitmap.is_allocated(c) catch { e => return Err(e) }
  Ok(v)
}

///|
test "mini volume boot checksum matches independent vector" {
  let sum = @boot.boot_checksum(mini(), 512) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(sum, 0x46987370U)
}

///|
test "open mini volume end to end" {
  let vol = Volume::open(mini()) catch {
    e => {
      println(e.message())
      assert_true(false)
      return
    }
  }
  assert_eq(vol.boot.cluster_count, 484U)
  assert_eq(vol.label, Some("TEST"))
  assert_eq(vol.bitmap.allocated_count(), 3)
  assert_eq(vol.upcase.length(), 128)
  assert_eq(vol.upcase.upcase_string("mini"), "MINI")
  assert_eq(chain_r(vol, 2U), Ok([2U]))
  assert_eq(alloc_r(vol, 2U), Ok(true))
  assert_eq(alloc_r(vol, 5U), Ok(false))
}

///|
test "missing bitmap entry is reported" {
  let img = set_byte(mini(), 14336, b'\x00')
  assert_eq(open_result(img), Err(BitmapMissing))
}

///|
test "missing up-case entry is reported" {
  let img = set_byte(mini(), 14368, b'\x00')
  assert_eq(open_result(img), Err(UpcaseMissing))
}

///|
test "corrupted up-case checksum is reported" {
  let img = set_byte(mini(), 14372, b'\x00')
  match open_result(img) {
    Err(UpcaseFailed(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "truncated image is reported" {
  let img = mini()
  let short = Bytes::makei(20480, fn(i) { img.at(i) })
  match open_result(short) {
    Err(ImageTooSmall(_)) => ()
    _ => assert_true(false)
  }
}