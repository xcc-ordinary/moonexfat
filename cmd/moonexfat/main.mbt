// moonexfat CLI: inspect exFAT disk images.
// Run via:
//   moon run cmd/moonexfat --target wasm -- inspect testdata/synthetic.exfat

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  match args[1] {
    "inspect" =>
      if args.length() >= 3 {
        inspect(args[2])
      } else {
        println("inspect: need an image file path")
      }
    _ => print_usage()
  }
}

///|
fn print_usage() -> Unit {
  println("moonexfat - pure-MoonBit exFAT image parser")
  println("")
  println("usage:")
  println("  moonexfat inspect IMAGE")
  println("      Validate the main boot region (sectors 0-11) of an exFAT")
  println("      image and print its geometry.")
}

///|
async fn inspect(path : String) -> Unit {
  let file = @fs.open(path, mode=ReadOnly) catch {
    e => {
      println("error: cannot open \{path}: \{e}")
      return
    }
  }
  defer file.close()
  let head = file.at(0L).read_exactly(512) catch {
    _ => {
      println("error: cannot read first 512 bytes (file too small?)")
      return
    }
  }
  let bps_shift = head.at(108).to_int()
  if bps_shift < 9 || bps_shift > 12 {
    println("error: BytesPerSectorShift \{bps_shift} out of range 9..12")
    return
  }
  let size = 1 << bps_shift
  let region = file.at(0L).read_exactly(12 * size) catch {
    _ => {
      println("error: cannot read the 12-sector boot region")
      return
    }
  }
  let boot = @boot.verify_boot_region(region) catch {
    e => {
      println("boot region INVALID: \{e.message()}")
      return
    }
  }
  println("exFAT boot region OK (main, sectors 0-11, checksum verified)")
  println("  sector size        : \{boot.sector_size()} bytes")
  println("  cluster size       : \{boot.cluster_size()} bytes")
  println("  volume length      : \{boot.volume_length} sectors")
  println("  partition offset   : \{boot.partition_offset} sectors")
  println("  FAT offset/length  : \{boot.fat_offset} / \{boot.fat_length} sectors")
  println("  number of FATs     : \{boot.number_of_fats}")
  println("  cluster heap offset: \{boot.cluster_heap_offset} sectors")
  println("  cluster count      : \{boot.cluster_count}")
  println("  root dir cluster   : \{boot.root_dir_cluster}")
  println("  volume serial      : 0x\{boot.volume_serial.to_string(radix=16)}")
  println("  fs revision        : \{boot.fs_revision >> 8}.\{boot.fs_revision & 0xFF}")
  println("  volume flags       : \{boot.volume_flags}")
  println("  percent in use     : \{boot.percent_in_use}")
}