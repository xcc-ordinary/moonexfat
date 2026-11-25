// exFAT Allocation Bitmap (spec §7.1): bit i describes cluster i+2,
// 1 = allocated, 0 = free. The bitmap is ceil(ClusterCount / 8) bytes.

///|
#derive(Debug, Eq)
pub suberror BitmapError {
  BitmapTooSmall(Int, Int)
  ClusterOutOfRange(UInt)
}

///|
pub fn BitmapError::message(self : BitmapError) -> String {
  match self {
    BitmapTooSmall(have, need) => "bitmap has \{have} bytes, needs \{need}"
    ClusterOutOfRange(c) => "cluster \{c} out of bitmap range"
  }
}

///|
#derive(Debug, Eq)
pub struct Bitmap {
  data : Bytes
  cluster_count : UInt
}

///|
pub fn Bitmap::new(
  data : Bytes,
  cluster_count : UInt,
) -> Bitmap raise BitmapError {
  let need = (cluster_count.reinterpret_as_int() + 7) / 8
  guard data.length() >= need else {
    raise BitmapTooSmall(data.length(), need)
  }
  { data, cluster_count }
}

///|
pub fn Bitmap::is_allocated(
  self : Bitmap,
  cluster : UInt,
) -> Bool raise BitmapError {
  guard cluster >= 2U && cluster <= self.cluster_count + 1U else {
    raise ClusterOutOfRange(cluster)
  }
  let idx = (cluster - 2U).reinterpret_as_int()
  (self.data.at(idx / 8).to_int() & (1 << (idx % 8))) != 0
}

///|
/// Number of allocated clusters. Bits beyond ClusterCount in the final
/// byte are ignored, as the spec requires.
pub fn Bitmap::allocated_count(self : Bitmap) -> Int {
  let count = self.cluster_count.reinterpret_as_int()
  let nbytes = (count + 7) / 8
  let mut total = 0
  for i in 0..<nbytes {
    let b = self.data.at(i).to_int()
    let b = if i == nbytes - 1 && count % 8 != 0 {
      b & ((1 << (count % 8)) - 1)
    } else {
      b
    }
    total = total + b.popcnt()
  }
  total
}