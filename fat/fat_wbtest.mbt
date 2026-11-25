// FAT tests: entry classification, chain walking, corruption detection.

///|
fn mk_fat(entries : Array[UInt]) -> Bytes {
  Bytes::makei(entries.length() * 4, fn(i) {
    ((entries[i / 4] >> ((i % 4) * 8)) & 0xFFU).to_byte()
  })
}

///|
#warnings("-result_error_return")
fn new_result(data : Bytes, count : UInt) -> Result[FatView, FatError] {
  let f = FatView::new(data, count) catch { e => return Err(e) }
  Ok(f)
}

///|
#warnings("-result_error_return")
fn entry_r(f : FatView, i : UInt) -> Result[FatEntry, FatError] {
  let v = f.entry(i) catch { e => return Err(e) }
  Ok(v)
}

///|
#warnings("-result_error_return")
fn chain_result(f : FatView, start : UInt) -> Result[Array[UInt], FatError] {
  let c = f.chain(start) catch { e => return Err(e) }
  Ok(c)
}

///|
fn fat_of(entries : Array[UInt], count : UInt) -> FatView {
  FatView::new(mk_fat(entries), count) catch {
    _ => abort("fat setup failed")
  }
}

///|
test "entry classification" {
  let f = fat_of([0xFFFFFFF8U, 0xFFFFFFFFU, 3U, 0xFFFFFFF7U, 0U, 1U], 4U)
  assert_eq(entry_r(f, 0U), Ok(MediaDescriptor))
  assert_eq(entry_r(f, 1U), Ok(EndOfChain))
  assert_eq(entry_r(f, 2U), Ok(Next(3U)))
  assert_eq(entry_r(f, 3U), Ok(Bad))
  assert_eq(entry_r(f, 4U), Ok(Free))
  assert_eq(entry_r(f, 5U), Ok(Reserved(1U)))
  assert_eq(entry_r(f, 6U), Err(StartOutOfRange(6U)))
}

///|
test "walk a healthy chain" {
  let f = fat_of([0xFFFFFFF8U, 0xFFFFFFFFU, 3U, 4U, 0xFFFFFFFFU, 0U], 4U)
  assert_eq(chain_result(f, 2U), Ok([2U, 3U, 4U]))
  assert_eq(chain_result(f, 4U), Ok([4U]))
}

///|
test "detect a cycle" {
  let f = fat_of([0xFFFFFFF8U, 0xFFFFFFFFU, 3U, 2U, 0U, 0U], 4U)
  assert_eq(chain_result(f, 2U), Err(CycleAt(2U)))
}

///|
test "detect self-cycle" {
  let f = fat_of([0xFFFFFFF8U, 0xFFFFFFFFU, 2U, 0U, 0U, 0U], 4U)
  assert_eq(chain_result(f, 2U), Err(CycleAt(2U)))
}

///|
test "detect bad cluster in chain" {
  let f = fat_of([0xFFFFFFF8U, 0xFFFFFFFFU, 0xFFFFFFF7U, 0U, 0U, 0U], 4U)
  assert_eq(chain_result(f, 2U), Err(BadClusterInChain(2U)))
}

///|
test "detect free entry mid-chain" {
  let f = fat_of([0xFFFFFFF8U, 0xFFFFFFFFU, 3U, 0U, 0U, 0U], 4U)
  assert_eq(chain_result(f, 2U), Err(InvalidEntry(3U, 0U)))
}

///|
test "detect reserved value mid-chain" {
  let f = fat_of([0xFFFFFFF8U, 0xFFFFFFFFU, 1U, 0U, 0U, 0U], 4U)
  assert_eq(chain_result(f, 2U), Err(InvalidEntry(2U, 1U)))
}

///|
test "reject out-of-range start" {
  let f = fat_of([0xFFFFFFF8U, 0xFFFFFFFFU, 0xFFFFFFFFU, 0U, 0U], 3U)
  assert_eq(chain_result(f, 1U), Err(StartOutOfRange(1U)))
  assert_eq(chain_result(f, 5U), Err(StartOutOfRange(5U)))
}

///|
test "reject undersized FAT buffer" {
  assert_eq(new_result(Bytes::make(8, b'\x00'), 4U), Err(FatTooSmall(8, 24L)))
}