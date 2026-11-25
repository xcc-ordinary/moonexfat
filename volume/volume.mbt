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
/// The cluster chain of `start`, for inspection and W3 file reading.
pub fn Volume::cluster_chain(
  self : Volume,
  start : UInt,
) -> Array[UInt] raise VolumeError {
  self.fat.chain(start) catch { e => raise FatFailed(e.message()) }
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