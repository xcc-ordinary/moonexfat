// exFAT main boot sector parsing and validation.
// Implemented from the Microsoft "exFAT file system specification" (rev 1.00),
// sections 3.1 (Main Boot Region) and 3.4 (Boot Checksum):
// https://learn.microsoft.com/en-us/windows/win32/fileio/exfat-specification
// No code was copied from any GPL implementation; behavior is cross-checked
// against exfatprogs and the Linux kernel exfat driver.

///|
/// Structured errors for boot-region parsing and validation.
/// Each variant names the exact spec constraint that was violated.
#derive(Debug, Eq)
pub suberror BootError {
  Truncated(String)
  BadJumpBoot
  BadFileSystemName
  NonZeroMustBeZero(Int)
  BadSectorShift(Int)
  BadClusterShift(Int)
  BadNumberOfFats(Int)
  BadPercentInUse(Int)
  BadRevision(Int)
  BadFatOffset(UInt)
  BadFatLength(UInt)
  BadClusterHeapOffset(UInt)
  BadClusterCount(UInt)
  BadRootCluster(UInt)
  BadClusterIndex(UInt)
  VolumeTooSmall(Int64)
  BadSignature(Int)
  ChecksumMismatch(UInt, UInt)
}

///|
/// Human-readable description of a boot-region error.
pub fn BootError::message(self : BootError) -> String {
  match self {
    Truncated(why) => "truncated image: \{why}"
    BadJumpBoot => "JumpBoot is not EB 76 90"
    BadFileSystemName => "FileSystemName is not \"EXFAT   \""
    NonZeroMustBeZero(i) => "MustBeZero region is non-zero at byte \{i}"
    BadSectorShift(v) => "BytesPerSectorShift \{v} out of range 9..12"
    BadClusterShift(v) => "SectorsPerClusterShift \{v} makes clusters exceed 32 MiB"
    BadNumberOfFats(v) => "NumberOfFats \{v} must be 1 or 2"
    BadPercentInUse(v) => "PercentInUse \{v} must be 0..100 or 255 (unknown)"
    BadRevision(v) => "FileSystemRevision major \{v >> 8} is not 1"
    BadFatOffset(v) => "FatOffset \{v} must be at least 24 (behind both boot regions)"
    BadFatLength(v) => "FatLength \{v} sectors cannot hold ClusterCount + 2 entries"
    BadClusterHeapOffset(v) => "ClusterHeapOffset \{v} overlaps the FAT region"
    BadClusterCount(v) => "ClusterCount \{v} out of range 1..2^32-11"
    BadRootCluster(v) => "FirstClusterOfRootDirectory \{v} out of range 2..ClusterCount+1"
    BadClusterIndex(v) => "cluster index \{v} out of range 2..ClusterCount+1"
    VolumeTooSmall(v) => "VolumeLength \{v} sectors cannot contain the cluster heap"
    BadSignature(s) => "sector \{s} lacks the 0xAA55 boot signature"
    ChecksumMismatch(expected, actual) =>
      "boot checksum mismatch: expected 0x\{expected.to_string(radix=16)}, found 0x\{actual.to_string(radix=16)}"
  }
}

///|
/// Parsed and validated fields of the exFAT Main Boot Sector (sector 0).
/// Sector counts and offsets follow the spec's units: `*_offset` and
/// `volume_length` are in sectors, not bytes.
#derive(Debug, Eq)
pub struct BootRegion {
  partition_offset : Int64
  volume_length : Int64
  fat_offset : UInt
  fat_length : UInt
  cluster_heap_offset : UInt
  cluster_count : UInt
  root_dir_cluster : UInt
  volume_serial : UInt
  fs_revision : Int
  volume_flags : Int
  bytes_per_sector_shift : Int
  sectors_per_cluster_shift : Int
  number_of_fats : Int
  drive_select : Int
  percent_in_use : Int
}

///|
/// Bytes per sector (512..4096).
pub fn BootRegion::sector_size(self : BootRegion) -> Int {
  1 << self.bytes_per_sector_shift
}

///|
/// Sectors per cluster.
pub fn BootRegion::sectors_per_cluster(self : BootRegion) -> Int {
  1 << self.sectors_per_cluster_shift
}

///|
/// Bytes per cluster (up to 32 MiB).
pub fn BootRegion::cluster_size(self : BootRegion) -> Int {
  self.sector_size() << self.sectors_per_cluster_shift
}

///|
/// Byte offset of `cluster` (valid indices are 2..ClusterCount+1) relative to
/// the start of the boot region. Computed in 64-bit to avoid overflow on
/// large volumes.
pub fn BootRegion::cluster_offset(
  self : BootRegion,
  cluster : UInt,
) -> Int64 raise BootError {
  guard cluster >= 2U && cluster <= self.cluster_count + 1U else {
    raise BadClusterIndex(cluster)
  }
  let sectors = self.cluster_heap_offset.to_int64() +
    (cluster.to_int64() - 2L) * self.sectors_per_cluster().to_int64()
  sectors * self.sector_size().to_int64()
}

// ---- field readers use @util.le_u16 / le_u32 / le_u64 ----

///|
/// Parse and validate the Main Boot Sector at the start of `data`.
/// `data` may be longer than one sector (e.g. the whole boot region);
/// only the first sector is examined here.
pub fn parse_boot_sector(data : Bytes) -> BootRegion raise BootError {
  guard data.length() >= 512 else {
    raise Truncated("boot sector needs at least 512 bytes")
  }
  // JumpBoot shall be EB 76 90 (spec 3.1.1).
  guard data.at(0) == b'\xEB' && data.at(1) == b'\x76' && data.at(2) == b'\x90' else {
    raise BadJumpBoot
  }
  // FileSystemName shall be "EXFAT   " (spec 3.1.2).
  let name = b"EXFAT   "
  for i in 0..<8 {
    guard data.at(3 + i) == name.at(i) else {
      raise BadFileSystemName
    }
  }
  // MustBeZero: bytes 11..63 (spec 3.1.3).
  for i in 11..<64 {
    guard data.at(i) == b'\x00' else {
      raise NonZeroMustBeZero(i)
    }
  }
  let bps_shift = data.at(108).to_int()
  guard bps_shift >= 9 && bps_shift <= 12 else {
    raise BadSectorShift(bps_shift)
  }
  let size = 1 << bps_shift
  guard data.length() >= size else {
    raise Truncated("declared sector size \{size} exceeds buffer")
  }
  guard data.at(size - 2) == b'\x55' && data.at(size - 1) == b'\xAA' else {
    raise BadSignature(0)
  }
  let spc_shift = data.at(109).to_int()
  // BytesPerSectorShift + SectorsPerClusterShift <= 25 (max 32 MiB cluster).
  guard bps_shift + spc_shift <= 25 else {
    raise BadClusterShift(spc_shift)
  }
  let num_fats = data.at(110).to_int()
  guard num_fats == 1 || num_fats == 2 else {
    raise BadNumberOfFats(num_fats)
  }
  let percent = data.at(112).to_int()
  guard percent <= 100 || percent == 255 else {
    raise BadPercentInUse(percent)
  }
  let revision = @util.le_u16(data, 104)
  guard (revision >> 8) == 1 else {
    raise BadRevision(revision)
  }
  let fat_offset = @util.le_u32(data, 80)
  // FatOffset >= 24: both boot regions (12 sectors each) come first.
  guard fat_offset >= 24U else {
    raise BadFatOffset(fat_offset)
  }
  let fat_length = @util.le_u32(data, 84)
  let heap_offset = @util.le_u32(data, 88)
  let cluster_count = @util.le_u32(data, 92)
  let root_cluster = @util.le_u32(data, 96)
  let volume_length = @util.le_u64(data, 72)
  guard cluster_count >= 1U && cluster_count <= 0xFFFFFFF5U else {
    raise BadClusterCount(cluster_count)
  }
  guard root_cluster >= 2U && root_cluster <= cluster_count + 1U else {
    raise BadRootCluster(root_cluster)
  }
  // The FAT must hold one 4-byte entry per cluster plus 2 reserved entries.
  guard fat_length.to_int64() * size.to_int64() >=
        (cluster_count.to_int64() + 2L) * 4L else {
    raise BadFatLength(fat_length)
  }
  // ClusterHeapOffset >= FatOffset + FatLength * NumberOfFats.
  guard heap_offset.to_int64() >=
        fat_offset.to_int64() + fat_length.to_int64() * num_fats.to_int64() else {
    raise BadClusterHeapOffset(heap_offset)
  }
  // The cluster heap must fit inside the volume.
  let spc = 1 << spc_shift
  guard heap_offset.to_int64() + cluster_count.to_int64() * spc.to_int64() <=
        volume_length else {
    raise VolumeTooSmall(volume_length)
  }
  {
    partition_offset: @util.le_u64(data, 64),
    volume_length,
    fat_offset,
    fat_length,
    cluster_heap_offset: heap_offset,
    cluster_count,
    root_dir_cluster: root_cluster,
    volume_serial: @util.le_u32(data, 100),
    fs_revision: revision,
    volume_flags: @util.le_u16(data, 106),
    bytes_per_sector_shift: bps_shift,
    sectors_per_cluster_shift: spc_shift,
    number_of_fats: num_fats,
    drive_select: data.at(111).to_int(),
    percent_in_use: percent,
  }
}