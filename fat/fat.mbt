// exFAT FAT (File Allocation Table) reading and cluster-chain walking.
// Spec section 5: FAT entries are 4-byte little-endian values; valid
// cluster indices run 2..ClusterCount+1.

///|
/// Classification of a raw FAT entry value (spec §5.2).
#derive(Debug, Eq)
pub enum FatEntry {
  Free
  Next(UInt)
  Bad
  MediaDescriptor
  EndOfChain
  Reserved(UInt)
}

///|
#derive(Debug, Eq)
pub suberror FatError {
  FatTooSmall(Int, Int64)
  StartOutOfRange(UInt)
  CycleAt(UInt)
  BadClusterInChain(UInt)
  InvalidEntry(UInt, UInt)
}

///|
pub fn FatError::message(self : FatError) -> String {
  match self {
    FatTooSmall(have, need) => "FAT buffer has \{have} bytes, needs \{need}"
    StartOutOfRange(c) => "cluster \{c} out of range 2..ClusterCount+1"
    CycleAt(c) => "cluster chain cycles back to cluster \{c}"
    BadClusterInChain(c) => "chain hits bad-cluster marker at cluster \{c}"
    InvalidEntry(c, v) =>
      "invalid FAT entry at cluster \{c}: 0x\{v.to_string(radix=16)}"
  }
}

///|
/// A read-only view over the bytes of one FAT.
#derive(Debug, Eq)
pub struct FatView {
  data : Bytes
  cluster_count : UInt
}

///|
pub fn FatView::new(
  data : Bytes,
  cluster_count : UInt,
) -> FatView raise FatError {
  let need = (cluster_count.to_int64() + 2L) * 4L
  guard data.length().to_int64() >= need else {
    raise FatTooSmall(data.length(), need)
  }
  { data, cluster_count }
}

///|
/// Read and classify the FAT entry for `index` (0..ClusterCount+1).
pub fn FatView::entry(self : FatView, index : UInt) -> FatEntry raise FatError {
  guard index <= self.cluster_count + 1U else {
    raise StartOutOfRange(index)
  }
  let off64 = index.to_int64() * 4L
  guard off64 + 4L <= self.data.length().to_int64() else {
    raise FatTooSmall(self.data.length(), off64 + 4L)
  }
  let v = @util.le_u32(self.data, off64.to_int())
  if v == 0U {
    Free
  } else if v == 0xFFFFFFF7U {
    Bad
  } else if v == 0xFFFFFFF8U {
    MediaDescriptor
  } else if v == 0xFFFFFFFFU {
    EndOfChain
  } else if v >= 2U && v <= self.cluster_count + 1U {
    Next(v)
  } else {
    Reserved(v)
  }
}

///|
/// Walk the cluster chain starting at `start`, returning every cluster in
/// order. Detects cycles, bad-cluster markers and invalid entries instead
/// of looping forever on corrupt images.
pub fn FatView::chain(
  self : FatView,
  start : UInt,
) -> Array[UInt] raise FatError {
  guard start >= 2U && start <= self.cluster_count + 1U else {
    raise StartOutOfRange(start)
  }
  let visited = Array::make(self.cluster_count.reinterpret_as_int() + 2, false)
  let out : Array[UInt] = []
  let mut cur = start
  while true {
    if visited[cur.reinterpret_as_int()] {
      raise CycleAt(cur)
    }
    visited[cur.reinterpret_as_int()] = true
    out.push(cur)
    match self.entry(cur) {
      EndOfChain => break
      Next(n) => cur = n
      Bad => raise BadClusterInChain(cur)
      Free => raise InvalidEntry(cur, 0U)
      MediaDescriptor => raise InvalidEntry(cur, 0xFFFFFFF8U)
      Reserved(v) => raise InvalidEntry(cur, v)
    }
  }
  out
}