// Volume integration tests on an in-memory mini exFAT volume that mirrors
// testdata/mini.exfat byte for byte. Independent vectors (PowerShell):
//   boot checksum         = 0x46987370
//   up-case TableChecksum = 0x88E38EE3
//   HELLO.TXT SetChecksum = 0x357E (16-bit rotate accumulator)
//   NameHash("HELLO.TXT") = 0x3046
//   NameHash("NESTED.TXT")= 0x6A4A

///|
fn ascii_bytes(s : String) -> Bytes {
  Bytes::makei(s.length(), fn(i) { s[i].to_int().to_byte() })
}

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
    73 => b'\x02' // VolumeLength = 512
    80 => b'\x18' // FatOffset = 24
    84 => b'\x04' // FatLength = 4
    88 => b'\x1C' // ClusterHeapOffset = 28
    92 => b'\xE4' // ClusterCount = 484
    93 => b'\x01'
    96 => b'\x02' // root cluster = 2
    100 => b'\x25' // serial 0x20261125
    101 => b'\x11'
    102 => b'\x26'
    103 => b'\x20'
    105 => b'\x01' // revision 1.0
    108 => b'\x09' // 512-byte sectors
    109 => b'\x00' // 1 sector per cluster
    110 => b'\x01' // 1 FAT
    111 => b'\x80'
    112 => b'\x02' // PercentInUse = 2 (excluded from boot checksum)
    _ =>
      if i < 4608 && i % 512 == 510 {
        b'\x55'
      } else if i < 4608 && i % 512 == 511 {
        b'\xAA'
      } else if i >= 5632 {
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
fn upcase_byte(j : Int) -> Byte {
  if j % 2 == 0 {
    let u = j / 2
    let v = if u >= 97 && u <= 122 { u - 32 } else { u }
    v.to_byte()
  } else {
    b'\x00'
  }
}

///|
fn healthy_upcase() -> @upcase.UpcaseTable {
  let table = Bytes::makei(256, upcase_byte)
  @upcase.UpcaseTable::parse(table, 0x88E38EE3U) catch {
    _ => abort("upcase setup failed")
  }
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
fn meta_entry(t : Int, checksum : UInt, cluster : UInt, len : Int64) -> Bytes {
  Bytes::makei(32, fn(i) {
    match i {
      0 => t.to_byte()
      _ =>
        if i >= 4 && i < 8 {
          ((checksum >> ((i - 4) * 8)) & 0xFFU).to_byte()
        } else if i >= 20 && i < 24 {
          ((cluster >> ((i - 20) * 8)) & 0xFFU).to_byte()
        } else if i >= 24 {
          ((len >> ((i - 24) * 8)) & 0xFFL).to_int().to_byte()
        } else {
          b'\x00'
        }
    }
  })
}

///|
fn label_entry() -> Bytes {
  Bytes::makei(32, fn(i) {
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
}

///|
/// Build a file directory entry set: File (0x85) + Stream (0xC0) +
/// File Name (0xC1) entries, with NameHash and SetChecksum.
fn file_set(
  name : String,
  attrs : Int,
  flags : Int,
  cluster : UInt,
  len : Int64,
) -> Bytes {
  let chars = name.to_array()
  let nlen = chars.length()
  let fn_count = (nlen + 14) / 15
  let sc = 1 + fn_count
  let total = 32 * (1 + sc)
  let ts : UInt = 0x5D796000U // 2026-11-25 12:00:00
  let hash = @entries.name_hash(name, healthy_upcase())
  let base = Bytes::makei(total, fn(i) {
    let rel = i % 32
    let which = i / 32
    if which == 0 {
      match rel {
        0 => b'\x85'
        1 => sc.to_byte()
        4 => (attrs & 0xFF).to_byte()
        _ =>
          if rel >= 8 && rel < 12 {
            ((ts >> ((rel - 8) * 8)) & 0xFFU).to_byte()
          } else if rel >= 12 && rel < 16 {
            ((ts >> ((rel - 12) * 8)) & 0xFFU).to_byte()
          } else if rel >= 16 && rel < 20 {
            ((ts >> ((rel - 16) * 8)) & 0xFFU).to_byte()
          } else {
            b'\x00'
          }
      }
    } else if which == 1 {
      match rel {
        0 => b'\xC0'
        1 => flags.to_byte()
        3 => nlen.to_byte()
        4 => (hash & 0xFF).to_byte()
        5 => ((hash >> 8) & 0xFF).to_byte()
        _ =>
          if rel >= 8 && rel < 16 {
            ((len >> ((rel - 8) * 8)) & 0xFFL).to_int().to_byte()
          } else if rel >= 20 && rel < 24 {
            ((cluster >> ((rel - 20) * 8)) & 0xFFU).to_byte()
          } else if rel >= 24 {
            ((len >> ((rel - 24) * 8)) & 0xFFL).to_int().to_byte()
          } else {
            b'\x00'
          }
      }
    } else {
      let k = which - 2
      if rel == 0 {
        b'\xC1'
      } else {
        let unit_idx = k * 15 + (rel - 2) / 2
        if rel >= 2 && unit_idx < nlen {
          let u = chars[unit_idx].to_int()
          if rel % 2 == 0 {
            (u & 0xFF).to_byte()
          } else {
            ((u >> 8) & 0xFF).to_byte()
          }
        } else {
          b'\x00'
        }
      }
    }
  })
  let mut sum = 0
  for i in 0..<total {
    if i == 2 || i == 3 {
      continue
    }
    sum = (((sum & 1) << 15) + (sum >> 1) + base.at(i).to_int()) & 0xFFFF
  }
  let cs = sum
  Bytes::makei(total, fn(i) {
    if i == 2 {
      (cs & 0xFF).to_byte()
    } else if i == 3 {
      ((cs >> 8) & 0xFF).to_byte()
    } else {
      base.at(i)
    }
  })
}

///|
/// Simulate deletion: clear the InUse bit (0x80) of every entry's type
/// byte, exactly as the spec's delete operation does. The stored
/// SetChecksum becomes stale; NameHash remains valid.
fn deleted_set(set : Bytes) -> Bytes {
  Bytes::makei(set.length(), fn(i) {
    if i % 32 == 0 {
      (set.at(i).to_int() & 0x7F).to_byte()
    } else {
      set.at(i)
    }
  })
}

///|
fn root_bytes() -> Bytes {
  concat([
    meta_entry(0x81, 0U, 3U, 61L),
    meta_entry(0x82, 0x88E38EE3U, 4U, 256L),
    label_entry(),
    file_set("HELLO.TXT", 0x20, 0x03, 5U, 27L),
    file_set("DATA.BIN", 0x20, 0x01, 6U, 1200L),
    file_set("SUB", 0x10, 0x03, 9U, 512L),
    deleted_set(file_set("GONE.TXT", 0x20, 0x03, 11U, 5L)),
    Bytes::make(64, b'\x00'),
  ])
}

///|
fn sub_bytes() -> Bytes {
  concat([
    file_set("NESTED.TXT", 0x20, 0x03, 10U, 18L),
    Bytes::make(416, b'\x00'),
  ])
}

///|
fn fat_byte(j : Int) -> Byte {
  match j {
    0 => b'\xF8'
    24 => b'\x07' // cluster 6 -> 7
    28 => b'\x08' // cluster 7 -> 8
    _ =>
      if (j >= 1 && j < 24) || (j >= 32 && j < 44) {
        b'\xFF'
      } else {
        b'\x00'
      }
  }
}

///|
fn mini() -> Bytes {
  let root = root_bytes()
  let sub = sub_bytes()
  let hello = ascii_bytes("Hello, exFAT from MoonBit!\n")
  let nested = ascii_bytes("nested file works\n")
  Bytes::makei(262144, fn(i) {
    if i < 6144 {
      boot_byte(i)
    } else if i < 12288 {
      boot_byte(i - 6144)
    } else if i >= 12288 && i < 12332 {
      fat_byte(i - 12288)
    } else if i >= 14336 && i < 14848 {
      root.at(i - 14336)
    } else if i == 14848 {
      b'\xFF' // bitmap: clusters 2..10 allocated
    } else if i == 14849 {
      b'\x01'
    } else if i >= 15360 && i < 15616 {
      upcase_byte(i - 15360)
    } else if i >= 15872 && i < 15872 + hello.length() {
      hello.at(i - 15872)
    } else if i >= 16384 && i < 17584 {
      ((i - 16384) % 251).to_byte() // DATA.BIN content across clusters 6-8
    } else if i >= 17920 && i < 18432 {
      sub.at(i - 17920)
    } else if i >= 18432 && i < 18432 + nested.length() {
      nested.at(i - 18432)
    } else if i >= 18944 && i < 18949 {
      "gone\n"[i - 18944].to_int().to_byte() // deleted GONE.TXT data, cluster 11
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
#warnings("-result_error_return")
fn list_root_r(vol : Volume) -> Result[Array[@entries.FileEntry], VolumeError] {
  let v = vol.list_root() catch { e => return Err(e) }
  Ok(v)
}

///|
#warnings("-result_error_return")
fn resolve_r(vol : Volume, p : String) -> Result[@entries.FileEntry, VolumeError] {
  let v = vol.resolve(p) catch { e => return Err(e) }
  Ok(v)
}

///|
fn opened() -> Volume {
  Volume::open(mini()) catch { e => abort("open failed: " + e.message()) }
}

///|
test "mini volume boot checksum matches independent vector" {
  // PercentInUse changed from 1 to 2 in W3; the checksum is unchanged
  // because the spec excludes that mutable field.
  let sum = @boot.boot_checksum(mini(), 512) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(sum, 0x46987370U)
}

///|
test "HELLO.TXT set checksum matches independent vector 0x357E" {
  assert_eq(@util.le_u16(root_bytes(), 96 + 2), 0x357E)
}

///|
test "name hash matches independent vectors" {
  let uc = healthy_upcase()
  assert_eq(@entries.name_hash("HELLO.TXT", uc), 0x3046)
  assert_eq(@entries.name_hash("NESTED.TXT", uc), 0x6A4A)
}

///|
test "open mini volume end to end" {
  let vol = opened()
  assert_eq(vol.boot.cluster_count, 484U)
  assert_eq(vol.boot.percent_in_use, 2)
  assert_eq(vol.label, Some("TEST"))
  assert_eq(vol.bitmap.allocated_count(), 9)
  assert_eq(vol.upcase.length(), 128)
  assert_eq(chain_r(vol, 2U), Ok([2U]))
  assert_eq(alloc_r(vol, 2U), Ok(true))
  assert_eq(alloc_r(vol, 11U), Ok(false))
}

///|
test "list root directory" {
  let vol = opened()
  let listing = vol.list_root() catch {
    e => {
      println(e.message())
      assert_true(false)
      return
    }
  }
  assert_eq(listing.length(), 3)
  assert_eq(listing[0].name, "HELLO.TXT")
  assert_eq(listing[0].data_length, 27L)
  assert_eq(listing[0].no_fat_chain, true)
  assert_eq(listing[0].is_dir(), false)
  assert_eq(listing[1].name, "DATA.BIN")
  assert_eq(listing[1].no_fat_chain, false)
  assert_eq(listing[2].name, "SUB")
  assert_eq(listing[2].is_dir(), true)
  let m = listing[0].modified
  assert_eq(m.year, 2026)
  assert_eq(m.month, 11)
  assert_eq(m.day, 25)
  assert_eq(m.hour, 12)
  assert_eq(m.minute, 0)
  assert_eq(m.second, 0)
}

///|
test "read single-cluster file via NoFatChain" {
  let vol = opened()
  let e = vol.resolve("HELLO.TXT") catch {
    _ => {
      assert_true(false)
      return
    }
  }
  let data = vol.read_file(e) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(data, ascii_bytes("Hello, exFAT from MoonBit!\n"))
}

///|
test "read multi-cluster file via FAT chain" {
  let vol = opened()
  assert_eq(chain_r(vol, 6U), Ok([6U, 7U, 8U]))
  let e = vol.resolve("DATA.BIN") catch {
    _ => {
      assert_true(false)
      return
    }
  }
  let data = vol.read_file(e) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(data.length(), 1200)
  for i in 0..<1200 {
    assert_eq(data.at(i).to_int(), i % 251)
  }
}

///|
test "case-insensitive path resolution into subdirectory" {
  let vol = opened()
  let e = vol.resolve("sub/nested.txt") catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(e.name, "NESTED.TXT")
  let data = vol.read_file(e) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(data, ascii_bytes("nested file works\n"))
}

///|
test "path errors are structured" {
  let vol = opened()
  assert_eq(resolve_r(vol, "NOPE"), Err(PathNotFound("NOPE")))
  assert_eq(resolve_r(vol, "HELLO.TXT/x"), Err(NotADirectory("HELLO.TXT")))
  assert_eq(resolve_r(vol, "/"), Err(PathNotFound("/")))
}

///|
test "corrupted file set checksum is detected on listing" {
  // Byte 40 of the HELLO.TXT set lives in the root cluster (14336+96+40).
  let img = set_byte(mini(), 14336 + 96 + 40, b'\xFF')
  let vol = Volume::open(img) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  match list_root_r(vol) {
    Err(DirFailed(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "renamed file without rehash is detected" {
  // 'H' of HELLO.TXT -> 'J' (first filename unit, low byte).
  let img = set_byte(mini(), 14336 + 96 + 64 + 2, b'J')
  let vol = Volume::open(img) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  match list_root_r(vol) {
    Err(DirFailed(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "deleted entry sets are listed separately and recoverable" {
  let vol = opened()
  let live = vol.list_root() catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(live.length(), 3)
  let gone = vol.list_deleted_root() catch {
    e => {
      println(e.message())
      assert_true(false)
      return
    }
  }
  assert_eq(gone.length(), 1)
  assert_eq(gone[0].name, "GONE.TXT")
  assert_eq(gone[0].deleted, true)
  assert_eq(gone[0].first_cluster, 11U)
  assert_eq(vol.deleted_intact(gone[0]), true)
  let data = vol.recover(gone[0]) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(data, ascii_bytes("gone\n"))
  let e = vol.resolve_deleted("gone.txt") catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(e.name, "GONE.TXT")
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
///|
test "stat timestamps and UTC offset from entry bytes" {
  // Set LastModifiedUtcOffset (byte 23 of the HELLO.TXT set) to UTC+8,
  // then recompute the set checksum so the set stays valid.
  let patched = set_byte(mini(), 14336 + 96 + 23, b'\xA0')
  let mut sum = 0
  for k in 0..<96 {
    if k == 2 || k == 3 {
      continue
    }
    sum = (((sum & 1) << 15) + (sum >> 1) + patched.at(14336 + 96 + k).to_int()) & 0xFFFF
  }
  let img = Bytes::makei(patched.length(), fn(i) {
    if i == 14336 + 96 + 2 {
      (sum & 0xFF).to_byte()
    } else if i == 14336 + 96 + 3 {
      ((sum >> 8) & 0xFF).to_byte()
    } else {
      patched.at(i)
    }
  })
  let vol = Volume::open(img) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  let e = vol.resolve("HELLO.TXT") catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(e.created.year, 2026)
  assert_eq(e.accessed.month, 11)
  assert_eq(e.utc_offset_minutes, Some(480))
  let plain = opened().resolve("HELLO.TXT") catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(plain.utc_offset_minutes, None)
}

///|
test "verify reports a consistent mini volume" {
  let r = opened().verify()
  assert_eq(r.files, 3)
  assert_eq(r.dirs, 1)
  assert_eq(r.fat_bitmap_mismatches, 0)
  assert_eq(r.orphan_clusters, 0)
  assert_eq(r.problems.length(), 0)
}

///|
test "verify detects bitmap/FAT disagreement and orphan clusters" {
  // Cluster 20: bitmap-only allocation -> orphan. Cluster 21: FAT says
  // end-of-chain but bitmap says free -> true inconsistency.
  let img0 = set_byte(mini(), 14850, b'\x04')
  let img = Bytes::makei(img0.length(), fn(i) {
    if i >= 12288 + 21 * 4 && i < 12288 + 22 * 4 {
      b'\xFF'
    } else {
      img0.at(i)
    }
  })
  let vol = Volume::open(img) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  let r = vol.verify()
  assert_true(r.fat_bitmap_mismatches >= 1)
  assert_true(r.orphan_clusters >= 1)
}

///|
test "verify detects a broken FAT chain" {
  // Zero FAT[7]: DATA.BIN's chain 6 -> 7 -> 8 breaks at 7.
  let img = set_byte(mini(), 12288 + 7 * 4, b'\x00')
  let vol = Volume::open(img) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  let r = vol.verify()
  assert_true(r.problems.length() >= 1)
  assert_true(r.orphan_clusters >= 1) // cluster 8 now unreachable
}

///|
test "tree walks the whole directory tree" {
  let t = opened().tree() catch {
    _ => {
      assert_true(false)
      return
    }
  }
  assert_eq(t.length(), 4)
  let paths = t.map(fn(x) { x.0 })
  assert_true(paths.contains("HELLO.TXT"))
  assert_true(paths.contains("DATA.BIN"))
  assert_true(paths.contains("SUB"))
  assert_true(paths.contains("SUB/NESTED.TXT"))
}

///|
test "cluster runs: contiguous and FAT-chained files" {
  let vol = opened()
  let hello = vol.resolve("HELLO.TXT") catch { _ => abort("setup") }
  let runs = vol.cluster_runs(hello) catch { _ => abort("runs") }
  assert_eq(runs, [(5U, 1)])
  let data = vol.resolve("DATA.BIN") catch { _ => abort("setup") }
  let runs2 = vol.cluster_runs(data) catch { _ => abort("runs") }
  assert_eq(runs2, [(6U, 3)])
}

///|
test "cluster runs detect fragmentation" {
  // Rewire DATA.BIN's chain to 6 -> 8 -> 7 -> EOC (non-contiguous).
  let base = mini()
  let img = Bytes::makei(base.length(), fn(i) {
    if i == 12288 + 6 * 4 {
      b'\x08'
    } else if i >= 12288 + 7 * 4 && i < 12288 + 8 * 4 {
      b'\xFF'
    } else if i == 12288 + 8 * 4 {
      b'\x07'
    } else if i > 12288 + 8 * 4 && i < 12288 + 9 * 4 {
      b'\x00'
    } else {
      base.at(i)
    }
  })
  let vol = Volume::open(img) catch { _ => abort("open") }
  let data = vol.resolve("DATA.BIN") catch { _ => abort("setup") }
  let runs = vol.cluster_runs(data) catch { _ => abort("runs") }
  assert_eq(runs, [(6U, 1), (8U, 1), (7U, 1)])
}

///|
test "find is case-insensitive and matches substrings" {
  let vol = opened()
  let a = vol.find("nested") catch { _ => abort("find") }
  assert_eq(a.length(), 1)
  assert_eq(a[0].0, "SUB/NESTED.TXT")
  let b = vol.find(".txt") catch { _ => abort("find") }
  assert_eq(b.length(), 2)
  let c = vol.find("sub") catch { _ => abort("find") }
  assert_eq(c.length(), 1)
  assert_eq(c[0].1.is_dir(), true)
  let d = vol.find("zzz") catch { _ => abort("find") }
  assert_eq(d.length(), 0)
}
