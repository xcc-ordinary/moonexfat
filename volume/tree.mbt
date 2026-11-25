// Recursive directory-tree traversal and name search.

///|
/// Walk the whole live directory tree and return (path, entry) pairs.
/// Depth is limited to 64 levels as a guard against cyclic directories.
pub fn Volume::tree(self : Volume) -> Array[(String, @entries.FileEntry)] raise VolumeError {
  let out : Array[(String, @entries.FileEntry)] = []
  let stack : Array[(Bytes, String, Int)] = [(self.root_dir, "", 0)]
  while stack.length() > 0 {
    let (data, path, depth) = match stack.pop() {
      Some(t) => t
      None => break
    }
    let listing = @entries.list_dir(data, Some(self.upcase)) catch {
      e => raise DirFailed(e.message())
    }
    for e in listing {
      let full = if path == "" {
        e.name
      } else {
        path + "/" + e.name
      }
      out.push((full, e))
      if e.is_dir() {
        guard depth < 64 else {
          raise DirFailed("directory depth limit exceeded at \{full}")
        }
        let sub = self.read_entry_data(e) catch {
          err => raise DirFailed("\{full}: \{err.message()}")
        }
        stack.push((sub, full, depth + 1))
      }
    }
  }
  out
}
///|
/// Case-insensitive substring search over all entry names in the tree
/// (comparison uses the volume's up-case table, as exFAT itself does).
pub fn Volume::find(
  self : Volume,
  pattern : String,
) -> Array[(String, @entries.FileEntry)] raise VolumeError {
  let needle = self.upcase.upcase_string(pattern)
  let all = self.tree()
  all.filter(fn(x) { self.upcase.upcase_string(x.1.name).contains(needle) })
}
