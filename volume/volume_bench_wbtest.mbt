// Benchmarks: run with `moon bench --target wasm`.

///|
fn open_keep(img : Bytes) -> Volume? {
  let v = Volume::open(img) catch { _ => return None }
  Some(v)
}

///|
test "bench Volume::open (256 KiB mini volume)" (it : @bench.T) {
  let img = mini()
  it.bench(fn() { it.keep(open_keep(img)) })
}

///|
test "bench list_root (3 entry sets)" (it : @bench.T) {
  let vol = opened()
  it.bench(fn() {
    let l = vol.list_root() catch { _ => return }
    it.keep(l)
  })
}

///|
test "bench read_file NoFatChain (27 B)" (it : @bench.T) {
  let vol = opened()
  let e = vol.resolve("HELLO.TXT") catch { _ => abort("setup") }
  it.bench(fn() {
    let d = vol.read_file(e) catch { _ => return }
    it.keep(d)
  })
}

///|
test "bench read_file FAT chain (1200 B, 3 clusters)" (it : @bench.T) {
  let vol = opened()
  let e = vol.resolve("DATA.BIN") catch { _ => abort("setup") }
  it.bench(fn() {
    let d = vol.read_file(e) catch { _ => return }
    it.keep(d)
  })
}

///|
test "bench boot_checksum (11 sectors)" (it : @bench.T) {
  let img = mini()
  it.bench(fn() {
    let s = @boot.boot_checksum(img, 512) catch { _ => return }
    it.keep(s)
  })
}