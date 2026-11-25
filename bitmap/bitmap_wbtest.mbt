// Allocation bitmap tests.

///|
#warnings("-result_error_return")
fn new_result(data : Bytes, count : UInt) -> Result[Bitmap, BitmapError] {
  let b = Bitmap::new(data, count) catch { e => return Err(e) }
  Ok(b)
}

///|
#warnings("-result_error_return")
fn alloc(bm : Bitmap, c : UInt) -> Result[Bool, BitmapError] {
  let v = bm.is_allocated(c) catch { e => return Err(e) }
  Ok(v)
}

///|
fn bitmap_of(data : Bytes, count : UInt) -> Bitmap {
  Bitmap::new(data, count) catch { _ => abort("bitmap setup failed") }
}

///|
test "bit addressing: bit i describes cluster i+2" {
  let bm = bitmap_of(Bytes::from_array([b'\x0B', b'\x05']), 12U)
  // byte0 = 0b00001011 -> clusters 2,3,5 allocated; cluster 4 free
  assert_eq(alloc(bm, 2U), Ok(true))
  assert_eq(alloc(bm, 3U), Ok(true))
  assert_eq(alloc(bm, 4U), Ok(false))
  assert_eq(alloc(bm, 5U), Ok(true))
  // byte1 = 0b00000101 -> clusters 10,12 allocated; cluster 11 free
  assert_eq(alloc(bm, 10U), Ok(true))
  assert_eq(alloc(bm, 11U), Ok(false))
  assert_eq(alloc(bm, 12U), Ok(true))
  assert_eq(alloc(bm, 13U), Ok(false))
  assert_eq(bm.allocated_count(), 5)
}

///|
test "out-of-range clusters are rejected" {
  let bm = bitmap_of(Bytes::from_array([b'\xFF', b'\xFF']), 12U)
  assert_eq(alloc(bm, 1U), Err(ClusterOutOfRange(1U)))
  assert_eq(alloc(bm, 14U), Err(ClusterOutOfRange(14U)))
}

///|
test "padding bits in the last byte are ignored" {
  // 12 clusters -> 2 bytes; only low 4 bits of byte1 are meaningful.
  let bm = bitmap_of(Bytes::from_array([b'\xFF', b'\xFF']), 12U)
  assert_eq(bm.allocated_count(), 12)
}

///|
test "undersized bitmap is rejected" {
  assert_eq(new_result(Bytes::make(1, b'\x00'), 12U), Err(BitmapTooSmall(1, 2)))
}