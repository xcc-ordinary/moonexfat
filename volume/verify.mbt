// Whole-volume consistency checking: walk every live directory entry
// set, mark reachable clusters, then cross-check the FAT against the
// allocation bitmap and report orphaned (allocated but unreachable)
// clusters. Read-only; problems are collected, never raised.

///|
#derive(Debug, Eq)
pub struct VerifyReport {
  files : Int
  dirs : Int
  fat_bitmap_mismatches : Int
  orphan_clusters : Int
  problems : Array[String]
}

///|
pub fn Volume::verify(self : Volume) -> VerifyReport {
  let count = self.boot.cluster_count.reinterpret_as_int()
  let reachable = Array::make(count + 2, false)
  let problems : Array[String] = []
  let mut files = 0
  let mut dirs = 0
  let csize = self.boot.cluster_size()
  let mark_chain = fn(start : UInt, what : String) {
    let chain = self.fat.chain(start) catch {
      e => {
        problems.push("\{what}: \{e.message()}")
        return
      }
    }
    for c in chain {
      reachable[c.reinterpret_as_int()] = true
    }
  }
  mark_chain(self.boot.root_dir_cluster, "root directory")
  match @entries.find_special(self.root_dir, 0x81) {
    Some(e) => mark_chain(e.first_cluster, "allocation bitmap")
    None => ()
  }
  match @entries.find_special(self.root_dir, 0x82) {
    Some(e) => mark_chain(e.first_cluster, "up-case table")
    None => ()
  }
  let mark_entry = fn(e : @entries.FileEntry, path : String) {
    let n = if e.data_length <= 0L {
      0
    } else {
      ((e.data_length + csize.to_int64() - 1L) / csize.to_int64()).to_int()
    }
    if e.no_fat_chain {
      for k in 0..<n {
        let c = e.first_cluster.reinterpret_as_int() + k
        if c >= 2 && c <= count + 1 {
          reachable[c] = true
        } else {
          problems.push("\{path}: cluster \{c} out of range")
        }
      }
    } else if n > 0 {
      mark_chain(e.first_cluster, path)
    }
  }
  // Iterative directory-tree walk (depth-limited against cyclic dirs).
  let stack : Array[(Bytes, String, Int)] = [(self.root_dir, "", 0)]
  while stack.length() > 0 {
    let (data, path, depth) = match stack.pop() {
      Some(t) => t
      None => break
    }
    let listing = @entries.list_dir(data, Some(self.upcase)) catch {
      e => {
        problems.push("directory '\{path}': \{e.message()}")
        continue
      }
    }
    for e in listing {
      let full = if path == "" {
        e.name
      } else {
        path + "/" + e.name
      }
      if e.is_dir() {
        dirs = dirs + 1
        mark_entry(e, full)
        if depth < 64 {
          let sub = self.read_entry_data(e) catch {
            err => {
              problems.push("\{full}: \{err.message()}")
              continue
            }
          }
          stack.push((sub, full, depth + 1))
        } else {
          problems.push("\{full}: directory depth limit exceeded")
        }
      } else {
        files = files + 1
        mark_entry(e, full)
      }
    }
  }
  // FAT vs allocation bitmap, and orphan detection. Only one direction
  // is a true inconsistency: a non-free FAT entry whose cluster the
  // bitmap reports as free. The reverse (FAT free, bitmap allocated) is
  // normal — NoFatChain contiguous files do not maintain FAT entries.
  let is_free = fn(c : UInt) -> Bool {
    match (self.fat.entry(c) catch { _ => return true }) {
      Free => true
      _ => false
    }
  }
  let mut mismatches = 0
  let mut orphans = 0
  for c in 2..<(count + 2) {
    let cu = c.reinterpret_as_uint()
    let free = is_free(cu)
    let alloc = self.bitmap.is_allocated(cu) catch { _ => false }
    if !free && !alloc {
      mismatches = mismatches + 1
    }
    if alloc && !reachable[c] {
      orphans = orphans + 1
    }
  }
  { files, dirs, fat_bitmap_mismatches: mismatches, orphan_clusters: orphans, problems }
}