// Minimal library usage sample: open an exFAT image with moonexfat,
// list the root directory, read a file, and verify volume consistency.
//
// Run from the repository root:
//   moon run examples/basic --target wasm
//   moon run examples/basic --target wasm -- path/to/your.exfat

///|
async fn main {
  let args = @env.args()
  let path = if args.length() >= 2 {
    args[1]
  } else {
    "testdata/mini.exfat"
  }
  // 1. Read the image into memory and open it (MBR/GPT aware).
  let image = @fs.read_binary(path) catch {
    e => {
      println("cannot read \{path}: \{e}")
      return
    }
  }
  let vol = @volume.Volume::open_disk(image) catch {
    e => {
      println("not a valid exFAT volume: \{e.message()}")
      return
    }
  }
  println("volume label: \{vol.label.unwrap_or("(none)")}")
  // 2. List the root directory.
  let entries = vol.list_root() catch {
    e => {
      println("list_root failed: \{e.message()}")
      return
    }
  }
  for e in entries {
    let kind = if e.is_dir() { "<DIR>" } else { "\{e.data_length} B" }
    println("  \{e.name}  (\{kind})")
  }
  // 3. Resolve a path (case-insensitive) and read the file.
  let entry = vol.resolve("hello.txt") catch {
    e => {
      println("resolve failed: \{e.message()}")
      return
    }
  }
  let data = vol.read_file(entry) catch {
    e => {
      println("read failed: \{e.message()}")
      return
    }
  }
  println("HELLO.TXT (\{data.length()} bytes):")
  println(@utf8.decode(data) catch { _ => "(binary data)" })
  // 4. Whole-volume consistency check (FAT vs bitmap, orphan clusters).
  let report = vol.verify()
  println(
    "verify: \{report.files} files, \{report.dirs} dirs, " +
    "\{report.fat_bitmap_mismatches} FAT/bitmap mismatches, " +
    "\{report.orphan_clusters} orphan clusters",
  )
}