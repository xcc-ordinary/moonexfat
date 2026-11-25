// Volume-level integration: boot region -> FAT -> root directory ->
// allocation bitmap + up-case table. Operates on an in-memory image
// (Bytes); streaming IO for large images is planned for W3/W4.

///|
#derive(Debug, Eq)
pub suberror VolumeError {
  BootFailed(String)
  FatFailed(String)
  ImageTooSmall(String)
  BitmapMissing
  UpcaseMissing
  BitmapFailed(String)
  UpcaseFailed(String)
  DataLengthInvalid(Int64)
  DirFailed(String)
  PathNotFound(String)
  NotADirectory(String)
}

///|
pub fn VolumeError::message(self : VolumeError) -> String {
  match self {
    BootFailed(m) => "boot region: \{m}"
    FatFailed(m) => "FAT: \{m}"
    ImageTooSmall(m) => "image too small: \{m}"
    BitmapMissing => "no Allocation Bitmap entry in root directory"
    UpcaseMissing => "no Up-case Table entry in root directory"
    BitmapFailed(m) => "allocation bitmap: \{m}"
    UpcaseFailed(m) => "up-case table: \{m}"
    DataLengthInvalid(n) => "metadata DataLength \{n} exceeds its cluster chain"
    DirFailed(m) => "directory: \{m}"
    PathNotFound(p) => "path not found: \{p}"
    NotADirectory(p) => "not a directory: \{p}"
  }
}

///|
#derive(Debug, Eq)
pub struct Volume {
  boot : @boot.BootRegion
  image : Bytes
  fat : @fat.FatView
  root_dir : Bytes
  bitmap : @bitmap.Bitmap
  upcase : @upcase.UpcaseTable
  label : String?
}

///|
/// Open an exFAT volume from a full in-memory image: verify the boot
/// region, load the FAT, walk the root directory chain, then locate and
/// validate the Allocation Bitmap and Up-case Table.
pub fn Volume::open(image : Bytes) -> Volume raise VolumeError {
  let boot = @boot.verify_boot_region(image) catch {
    e => raise BootFailed(e.message())
  }
  let size64 = boot.sector_size().to_int64()
  let fat_start = boot.fat_offset.to_int64() * size64
  let fat_len = boot.fat_length.to_int64() * size64
  guard fat_start + fat_len <= image.length().to_int64() else {
    raise ImageTooSmall("FAT region beyond end of image")
  }
  let heap_end = (boot.cluster_heap_offset.to_int64() +
      boot.cluster_count.to_int64() * boot.sectors_per_cluster().to_int64()) *
    size64
  guard heap_end <= image.length().to_int64() else {
    raise ImageTooSmall("cluster heap beyond end of image")
  }
  let fat = @fat.FatView::new(
    @util.slice(image, fat_start.to_int(), fat_len.to_int()),
    boot.cluster_count,
  ) catch { e => raise FatFailed(e.message()) }
  let root_dir = read_chain(image, boot, fat, boot.root_dir_cluster, None)
  let bm_entry = match @entries.find_special(root_dir, 0x81) {
    Some(e) => e
    None => raise BitmapMissing
  }
  let bm_bytes = read_chain(
    image, boot, fat, bm_entry.first_cluster, Some(bm_entry.data_length),
  )
  let bitmap = @bitmap.Bitmap::new(bm_bytes, boot.cluster_count) catch {
    e => raise BitmapFailed(e.message())
  }
  let uc_entry = match @entries.find_special(root_dir, 0x82) {
    Some(e) => e
    None => raise UpcaseMissing
  }
  let uc_bytes = read_chain(
    image, boot, fat, uc_entry.first_cluster, Some(uc_entry.data_length),
  )
  let upcase = @upcase.UpcaseTable::parse(uc_bytes, uc_entry.table_checksum) catch {
    e => raise UpcaseFailed(e.message())
  }
  {
    boot,
    image,
    fat,
    root_dir,
    bitmap,
    upcase,
    label: @entries.volume_label(root_dir),
  }
}

///|
/// Open an exFAT volume from a full disk image: raw volume, MBR disk or
/// GPT disk. The partition offset is auto-detected via the boot signature.
pub fn Volume::open_disk(image : Bytes) -> Volume raise VolumeError {
  match @disk.exfat_offset(image) {
    Some(off) => {
      let o = off.to_int()
      Volume::open(@util.slice(image, o, image.length() - o))
    }
    None =>
      raise BootFailed("no exFAT volume found (checked offset 0, MBR and GPT partitions)")
  }
}

///|
/// The cluster chain of `start`, for inspection and W3 file reading.
pub fn Volume::cluster_chain(
  self : Volume,
  start : UInt,
) -> Array[UInt] raise VolumeError {
  self.fat.chain(start) catch { e => raise FatFailed(e.message()) }
}

// ---- W3: directory listing, path resolution, file reading ----

///|
/// List the root directory's file entry sets.
pub fn Volume::list_root(self : Volume) -> Array[@entries.FileEntry] raise VolumeError {
  @entries.list_dir(self.root_dir, Some(self.upcase)) catch {
    e => raise DirFailed(e.message())
  }
}

///|
/// List the contents of a directory entry.
pub fn Volume::list_dir_entry(
  self : Volume,
  entry : @entries.FileEntry,
) -> Array[@entries.FileEntry] raise VolumeError {
  guard entry.is_dir() else {
    raise NotADirectory(entry.name)
  }
  let data = self.read_entry_data(entry)
  @entries.list_dir(data, Some(self.upcase)) catch {
    e => raise DirFailed(e.message())
  }
}

///|
fn split_path(path : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for c in path.iter() {
    if c == '/' || c == '\\' {
      if cur != "" {
        out.push(cur)
        cur = ""
      }
    } else {
      cur = cur + "\{c}"
    }
  }
  if cur != "" {
    out.push(cur)
  }
  out
}

///|
/// Resolve a '/'-separated path case-insensitively (via the volume's
/// up-case table) and return its file entry.
pub fn Volume::resolve(
  self : Volume,
  path : String,
) -> @entries.FileEntry raise VolumeError {
  self.resolve_path(path, deleted=false)
}

///|
/// Like `resolve`, but searches deleted entry sets (for recovery).
pub fn Volume::resolve_deleted(
  self : Volume,
  path : String,
) -> @entries.FileEntry raise VolumeError {
  self.resolve_path(path, deleted=true)
}

///|
fn Volume::resolve_path(
  self : Volume,
  path : String,
  deleted~ : Bool,
) -> @entries.FileEntry raise VolumeError {
  let parts = split_path(path)
  guard parts.length() > 0 else {
    raise PathNotFound(path)
  }
  let mut listing = self.entries_of(None, deleted)
  for idx in 0..<parts.length() {
    let seg = parts[idx]
    let target = self.upcase.upcase_string(seg)
    let mut hit : @entries.FileEntry? = None
    for e in listing {
      if self.upcase.upcase_string(e.name) == target {
        hit = Some(e)
        break
      }
    }
    let e = match hit {
      Some(e) => e
      None => raise PathNotFound(path)
    }
    if idx == parts.length() - 1 {
      return e
    }
    listing = self.entries_of(Some(e), deleted)
  }
  raise PathNotFound(path)
}

///|
/// Entry sets of a directory (None = root), live or deleted.
fn Volume::entries_of(
  self : Volume,
  dir : @entries.FileEntry?,
  deleted : Bool,
) -> Array[@entries.FileEntry] raise VolumeError {
  let data = match dir {
    None => self.root_dir
    Some(e) => {
      guard e.is_dir() else {
        raise NotADirectory(e.name)
      }
      if deleted {
        self.read_contiguous(e)
      } else {
        self.read_entry_data(e)
      }
    }
  }
  let listing = if deleted {
    @entries.list_deleted(data, Some(self.upcase)) catch {
      e => raise DirFailed(e.message())
    }
  } else {
    @entries.list_dir(data, Some(self.upcase)) catch {
      e => raise DirFailed(e.message())
    }
  }
  listing
}

///|
/// List deleted entry sets in the root directory.
pub fn Volume::list_deleted_root(self : Volume) -> Array[@entries.FileEntry] raise VolumeError {
  self.entries_of(None, true)
}

///|
/// List deleted entry sets inside a (possibly deleted) directory.
pub fn Volume::list_deleted_dir(
  self : Volume,
  entry : @entries.FileEntry,
) -> Array[@entries.FileEntry] raise VolumeError {
  self.entries_of(Some(entry), true)
}

///|
/// Best-effort recovery of a deleted file: read its former clusters
/// contiguously. Deletion zeroes FAT chains, so the chain is unusable;
/// data survives until those clusters are reallocated and overwritten.
pub fn Volume::recover(
  self : Volume,
  entry : @entries.FileEntry,
) -> Bytes raise VolumeError {
  self.read_contiguous(entry)
}

///|
/// Whether a deleted file's former clusters are all still free in the
/// allocation bitmap — a strong hint that its data has not been reused.
pub fn Volume::deleted_intact(self : Volume, entry : @entries.FileEntry) -> Bool {
  let csize = self.boot.cluster_size()
  if entry.data_length <= 0L {
    return true
  }
  let n = ((entry.data_length + csize.to_int64() - 1L) / csize.to_int64()).to_int()
  for k in 0..<n {
    let c = entry.first_cluster.to_int() + k
    if c < 2 || c > self.boot.cluster_count.reinterpret_as_int() + 1 {
      return false
    }
    let allocated = self.bitmap.is_allocated(c.reinterpret_as_uint()) catch {
      _ => return false
    }
    if allocated {
      return false
    }
  }
  true
}

///|
/// Read a file's data: contiguous clusters when NoFatChain is set,
/// otherwise the FAT chain; truncated to DataLength.
pub fn Volume::read_file(
  self : Volume,
  entry : @entries.FileEntry,
) -> Bytes raise VolumeError {
  self.read_entry_data(entry)
}

///|
fn Volume::read_entry_data(
  self : Volume,
  entry : @entries.FileEntry,
) -> Bytes raise VolumeError {
  let dl = entry.data_length
  guard dl >= 0L else {
    raise DataLengthInvalid(dl)
  }
  if dl == 0L {
    return Bytes::make(0, b'\x00')
  }
  if entry.no_fat_chain {
    self.read_contiguous(entry)
  } else {
    let csize = self.boot.cluster_size()
    let nclusters = ((dl + csize.to_int64() - 1L) / csize.to_int64()).to_int()
    let size64 = self.boot.sector_size().to_int64()
    let heap64 = self.boot.cluster_heap_offset.to_int64() * size64
    let chain = self.fat.chain(entry.first_cluster) catch {
      e => raise FatFailed(e.message())
    }
    guard chain.length() >= nclusters else {
      raise DataLengthInvalid(dl)
    }
    Bytes::makei(dl.to_int(), fn(i) {
      let cluster = chain[i / csize].to_int64()
      let off = heap64 +
        (cluster - 2L) * self.boot.sectors_per_cluster().to_int64() * size64 +
        (i % csize).to_int64()
      self.image.at(off.to_int())
    })
  }
}

///|
/// Read `ceil(DataLength / cluster_size)` consecutive clusters starting
/// at FirstCluster, truncated to DataLength.
fn Volume::read_contiguous(
  self : Volume,
  entry : @entries.FileEntry,
) -> Bytes raise VolumeError {
  let dl = entry.data_length
  guard dl >= 0L else {
    raise DataLengthInvalid(dl)
  }
  if dl == 0L {
    return Bytes::make(0, b'\x00')
  }
  let csize = self.boot.cluster_size()
  let nclusters = ((dl + csize.to_int64() - 1L) / csize.to_int64()).to_int()
  let size64 = self.boot.sector_size().to_int64()
  let heap64 = self.boot.cluster_heap_offset.to_int64() * size64
  let last = entry.first_cluster.to_int64() + (nclusters - 1).to_int64()
  guard entry.first_cluster >= 2U &&
        last <= self.boot.cluster_count.to_int64() + 1L else {
    raise DataLengthInvalid(dl)
  }
  let start = heap64 +
    (entry.first_cluster.to_int64() - 2L) *
    self.boot.sectors_per_cluster().to_int64() * size64
  guard start + dl <= self.image.length().to_int64() else {
    raise ImageTooSmall("file data beyond end of image")
  }
  @util.slice(self.image, start.to_int(), dl.to_int())
}

///|
/// Read the data of a cluster chain, optionally truncated to `len` bytes
/// (the DataLength of a metadata entry).
fn read_chain(
  image : Bytes,
  boot : @boot.BootRegion,
  fat : @fat.FatView,
  start : UInt,
  len : Int64?,
) -> Bytes raise VolumeError {
  let chain = fat.chain(start) catch { e => raise FatFailed(e.message()) }
  let csize = boot.cluster_size()
  let total = chain.length() * csize
  let data = Bytes::makei(total, fn(i) {
    let cluster = chain[i / csize].to_int64()
    let off = (boot.cluster_heap_offset.to_int64() +
        (cluster - 2L) * boot.sectors_per_cluster().to_int64()) *
      boot.sector_size().to_int64() +
      (i % csize).to_int64()
    image.at(off.to_int())
  })
  match len {
    Some(n) => {
      guard n >= 0L && n <= total.to_int64() else {
        raise DataLengthInvalid(n)
      }
      @util.slice(data, 0, n.to_int())
    }
    None => data
  }
}