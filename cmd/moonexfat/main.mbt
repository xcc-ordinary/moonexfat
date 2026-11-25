// moonexfat CLI: inspect exFAT disk images.
// Run via:
//   moon run cmd/moonexfat --target wasm -- inspect testdata/mini.exfat
//   moon run cmd/moonexfat --target wasm -- chain testdata/mini.exfat 2

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
    "chain" =>
      if args.length() >= 4 {
        chain_cli(args[2], args[3])
      } else {
        println("chain: need an image file path and a cluster number")
      }
    "ls" =>
      if args.length() >= 3 {
        ls_cli(args[2], if args.length() >= 4 { args[3] } else { "/" })
      } else {
        println("ls: need an image file path")
      }
    "cat" =>
      if args.length() >= 4 {
        cat_cli(args[2], args[3])
      } else {
        println("cat: need an image file path and a file path inside it")
      }
    "extract" =>
      if args.length() >= 5 {
        extract_cli(args[2], args[3], args[4])
      } else {
        println("extract: need IMAGE PATH_IN_IMAGE OUTPUT_FILE")
      }
    "deleted" =>
      if args.length() >= 3 {
        deleted_cli(args[2], if args.length() >= 4 { args[3] } else { "/" })
      } else {
        println("deleted: need an image file path")
      }
    "recover" =>
      if args.length() >= 5 {
        recover_cli(args[2], args[3], args[4])
      } else {
        println("recover: need IMAGE DELETED_PATH OUTPUT_FILE")
      }
    "stat" =>
      if args.length() >= 4 {
        stat_cli(args[2], args[3])
      } else {
        println("stat: need an image file path and a file path inside it")
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
  println("      Validate the boot region and volume metadata (FAT, root")
  println("      directory, allocation bitmap, up-case table); print geometry.")
  println("  moonexfat chain IMAGE CLUSTER")
  println("      Walk and print the FAT cluster chain starting at CLUSTER.")
  println("  moonexfat ls IMAGE [DIR]")
  println("      List a directory (default: root).")
  println("  moonexfat cat IMAGE PATH")
  println("      Print a file's content as UTF-8 text.")
  println("  moonexfat extract IMAGE PATH OUTPUT")
  println("      Extract a file from the image to OUTPUT.")
  println("  moonexfat deleted IMAGE [DIR]")
  println("      List deleted entry sets; 'intact' = clusters still free.")
  println("  moonexfat recover IMAGE DELETED_PATH OUTPUT")
  println("      Best-effort recovery of a deleted file's former clusters.")
  println("  moonexfat stat IMAGE PATH")
  println("      Full metadata: attributes, timestamps, UTC offset, clusters.")
}

///|
async fn read_image(path : String) -> Bytes? {
  let b = @fs.read_binary(path) catch {
    e => {
      println("error: cannot read \{path}: \{e}")
      return None
    }
  }
  Some(carve_exfat(b))
}

///|
/// Accept both raw volumes and full disk images (MBR/GPT): slice out the
/// exFAT partition when one is detected.
fn carve_exfat(image : Bytes) -> Bytes {
  match @disk.exfat_offset(image) {
    Some(off) =>
      if off == 0L {
        image
      } else {
        let o = off.to_int()
        @util.slice(image, o, image.length() - o)
      }
    None => image
  }
}

///|
async fn inspect(path : String) -> Unit {
  let image = match read_image(path) {
    Some(b) => b
    None => return
  }
  let boot = @boot.verify_boot_region(image) catch {
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
  let vol = @volume.Volume::open(image) catch {
    e => {
      println("")
      println("volume metadata unavailable: \{e.message()}")
      return
    }
  }
  println("")
  println("volume metadata OK:")
  match vol.label {
    Some(l) => println("  volume label       : \{l}")
    None => println("  volume label       : (none)")
  }
  let root_chain = vol.cluster_chain(boot.root_dir_cluster) catch {
    e => {
      println("  root dir chain     : ERROR \{e.message()}")
      return
    }
  }
  println("  root dir chain     : \{show_chain(root_chain)}")
  println(
    "  allocation bitmap  : \{vol.bitmap.allocated_count()} / \{boot.cluster_count} clusters allocated",
  )
  println(
    "  up-case table      : \{vol.upcase.length()} entries, checksum verified",
  )
}

///|
async fn chain_cli(path : String, cluster_arg : String) -> Unit {
  let start = @string.parse_int(cluster_arg) catch {
    _ => {
      println("chain: invalid cluster number \"\{cluster_arg}\"")
      return
    }
  }
  guard start >= 2 else {
    println("chain: cluster numbers start at 2")
    return
  }
  let image = match read_image(path) {
    Some(b) => b
    None => return
  }
  let vol = @volume.Volume::open(image) catch {
    e => {
      println("error: \{e.message()}")
      return
    }
  }
  let chain = vol.cluster_chain(start.reinterpret_as_uint()) catch {
    e => {
      println("chain INVALID: \{e.message()}")
      return
    }
  }
  println("chain from cluster \{start}: \{show_chain(chain)}")
}

///|
fn show_chain(chain : Array[UInt]) -> String {
  let parts : Array[String] = []
  for c in chain {
    parts.push("\{c}")
  }
  parts.join(" -> ") + " -> EOC"
}

///|
async fn open_volume(path : String) -> @volume.Volume? {
  let image = match read_image(path) {
    Some(b) => b
    None => return None
  }
  let vol = @volume.Volume::open(image) catch {
    e => {
      println("error: \{e.message()}")
      return None
    }
  }
  Some(vol)
}

///|
fn two(n : Int) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
async fn ls_cli(path : String, dir_path : String) -> Unit {
  let vol = match open_volume(path) {
    Some(v) => v
    None => return
  }
  let listing = if dir_path == "/" || dir_path == "" {
    vol.list_root() catch {
      e => {
        println("error: \{e.message()}")
        return
      }
    }
  } else {
    let entry = vol.resolve(dir_path) catch {
      e => {
        println("error: \{e.message()}")
        return
      }
    }
    vol.list_dir_entry(entry) catch {
      e => {
        println("error: \{e.message()}")
        return
      }
    }
  }
  println("TYPE   SIZE       MODIFIED          NAME")
  for e in listing {
    let kind = if e.is_dir() { "<DIR>" } else { "     " }
    let m = e.modified
    let date = "\{m.year}-\{two(m.month)}-\{two(m.day)} \{two(m.hour)}:\{two(m.minute)}"
    println("\{kind}  \{e.data_length}  \{date}  \{e.name}")
  }
  println("\{listing.length()} entries")
}

///|
async fn cat_cli(path : String, file_path : String) -> Unit {
  let vol = match open_volume(path) {
    Some(v) => v
    None => return
  }
  let entry = vol.resolve(file_path) catch {
    e => {
      println("error: \{e.message()}")
      return
    }
  }
  guard !entry.is_dir() else {
    println("error: \{file_path} is a directory")
    return
  }
  let data = vol.read_file(entry) catch {
    e => {
      println("error: \{e.message()}")
      return
    }
  }
  let text = @utf8.decode(data) catch {
    _ => {
      println("error: \{file_path} is not valid UTF-8 (\{data.length()} bytes); use extract")
      return
    }
  }
  println(text)
}

///|
async fn extract_cli(path : String, file_path : String, out : String) -> Unit {
  let vol = match open_volume(path) {
    Some(v) => v
    None => return
  }
  let entry = vol.resolve(file_path) catch {
    e => {
      println("error: \{e.message()}")
      return
    }
  }
  guard !entry.is_dir() else {
    println("error: \{file_path} is a directory")
    return
  }
  let data = vol.read_file(entry) catch {
    e => {
      println("error: \{e.message()}")
      return
    }
  }
  @fs.write_binary(out, data) catch {
    e => {
      println("error: cannot write \{out}: \{e}")
      return
    }
  }
  println("extracted \{data.length()} bytes to \{out}")
}

///|
fn fmt_ts(d : @entries.DateTime, ten_ms : Int) -> String {
  "\{d.year}-\{two(d.month)}-\{two(d.day)} \{two(d.hour)}:\{two(d.minute)}:\{two(d.second)}.\{two(ten_ms)}"
}

///|
fn fmt_offset(minutes : Int?) -> String {
  match minutes {
    None => "(not recorded)"
    Some(m) => {
      let sign = if m < 0 {
        "-"
      } else {
        "+"
      }
      let a = if m < 0 {
        -m
      } else {
        m
      }
      "UTC\{sign}\{two(a / 60)}:\{two(a % 60)}"
    }
  }
}

///|
async fn stat_cli(path : String, file_path : String) -> Unit {
  let vol = match open_volume(path) {
    Some(v) => v
    None => return
  }
  let entry = vol.resolve(file_path) catch {
    _ => {
      let e = vol.resolve_deleted(file_path) catch {
        e2 => {
          println("error: \{e2.message()}")
          return
        }
      }
      e
    }
  }
  let csize = vol.boot.cluster_size()
  let nclusters = if entry.data_length <= 0L {
    0
  } else {
    ((entry.data_length + csize.to_int64() - 1L) / csize.to_int64()).to_int()
  }
  println("name             : \{entry.name}")
  println("type             : \{if entry.is_dir() { "directory" } else { "file" }}\{if entry.deleted { " (DELETED)" } else { "" }}")
  println("attributes       : \{@entries.attribute_string(entry.attributes)}")
  println("data length      : \{entry.data_length} bytes")
  println("valid data length: \{entry.valid_data_length} bytes")
  println("first cluster    : \{entry.first_cluster}")
  println("cluster count    : \{nclusters} (\{csize} B clusters)")
  println("allocation       : \{if entry.no_fat_chain { "contiguous (NoFatChain)" } else { "FAT chain" }}")
  println("created          : \{fmt_ts(entry.created, entry.create_10ms)}")
  println("modified         : \{fmt_ts(entry.modified, entry.modified_10ms)}")
  println("accessed         : \{fmt_ts(entry.accessed, 0)}")
  println("utc offset       : \{fmt_offset(entry.utc_offset_minutes)}")
  if entry.deleted {
    println("recovery hint    : \{if vol.deleted_intact(entry) { "clusters still free — data likely intact" } else { "clusters reallocated — data may be overwritten" }}")
  }
}

///|
async fn deleted_cli(path : String, dir_path : String) -> Unit {
  let vol = match open_volume(path) {
    Some(v) => v
    None => return
  }
  let listing = if dir_path == "/" || dir_path == "" {
    vol.list_deleted_root() catch {
      e => {
        println("error: \{e.message()}")
        return
      }
    }
  } else {
    let entry = vol.resolve_deleted(dir_path) catch {
      e => {
        println("error: \{e.message()}")
        return
      }
    }
    vol.list_deleted_dir(entry) catch {
      e => {
        println("error: \{e.message()}")
        return
      }
    }
  }
  println("STATUS   SIZE       NAME")
  for e in listing {
    let status = if e.is_dir() {
      "<DIR> "
    } else if vol.deleted_intact(e) {
      "intact"
    } else {
      "reused"
    }
    println("\{status}  \{e.data_length}  \{e.name}")
  }
  println("\{listing.length()} deleted entries")
}

///|
async fn recover_cli(path : String, file_path : String, out : String) -> Unit {
  let vol = match open_volume(path) {
    Some(v) => v
    None => return
  }
  let entry = vol.resolve_deleted(file_path) catch {
    e => {
      println("error: \{e.message()}")
      return
    }
  }
  guard !entry.is_dir() else {
    println("error: \{file_path} is a directory")
    return
  }
  let intact = vol.deleted_intact(entry)
  let data = vol.recover(entry) catch {
    e => {
      println("error: \{e.message()}")
      return
    }
  }
  @fs.write_binary(out, data) catch {
    e => {
      println("error: cannot write \{out}: \{e}")
      return
    }
  }
  let hint = if intact {
    "clusters still free — data likely intact"
  } else {
    "WARNING: clusters reallocated — data may be overwritten"
  }
  println("recovered \{data.length()} bytes to \{out} (\{hint})")
}