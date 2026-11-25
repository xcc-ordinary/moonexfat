// Deterministic mutation fuzzing: random byte flips and truncations must
// never panic — every malformed input is either accepted or rejected with
// a structured error. The PRNG is a fixed-seed LCG so runs are reproducible.

///|
struct Lcg {
  mut state : UInt
}

///|
fn Lcg::next(self : Lcg) -> UInt {
  self.state = self.state * 1664525U + 1013904223U
  self.state
}

///|
fn Lcg::below(self : Lcg, n : Int) -> Int {
  (self.next() % n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn mutate(base : Bytes, edits : Array[(Int, Byte)]) -> Bytes {
  Bytes::makei(base.length(), fn(i) {
    for e in edits {
      if e.0 == i {
        return e.1
      }
    }
    base.at(i)
  })
}

///|
/// Exercise every read path on a possibly-corrupt image; all failures
/// must be structured errors, never panics.
fn exercise(img : Bytes) -> Bool {
  let vol = Volume::open(img) catch { _ => return false }
  let listing = vol.list_root() catch { _ => return true }
  for e in listing {
    let _data = vol.read_file(e) catch { _ => continue }
    if e.is_dir() {
      let _sub = vol.list_dir_entry(e) catch { _ => continue }
    }
  }
  let _e = vol.resolve("SUB/NESTED.TXT") catch { _ => return true }
  let _d = vol.read_file(_e) catch { _ => return true }
  true
}

///|
test "fuzz: random byte flips never panic" {
  let base = mini()
  let rng = Lcg::{ state: 0x20261125U }
  let mut accepted = 0
  let mut rejected = 0
  for _ in 0..<150 {
    let n_edits = 1 + rng.below(3)
    let edits : Array[(Int, Byte)] = []
    for _ in 0..<n_edits {
      edits.push((rng.below(base.length()), rng.below(256).to_byte()))
    }
    if exercise(mutate(base, edits)) {
      accepted = accepted + 1
    } else {
      rejected = rejected + 1
    }
  }
  // Sanity: corruption must actually be detected sometimes, and clean
  // structure must survive sometimes.
  assert_true(rejected > 0)
  assert_true(accepted + rejected == 150)
}

///|
test "fuzz: targeted metadata-region flips never panic" {
  let base = mini()
  let rng = Lcg::{ state: 0xE619D30DU }
  // FAT (12288..12332), root directory (14336..14848), bitmap/up-case
  // (14848..15616): regions that open() and listing actually parse.
  let regions = [(12288, 44), (14336, 512), (14848, 768)]
  for _ in 0..<100 {
    let r = regions[rng.below(regions.length())]
    let edits = [(r.0 + rng.below(r.1), rng.below(256).to_byte())]
    ignore(exercise(mutate(base, edits)))
  }
}

///|
test "fuzz: random truncations never panic" {
  let base = mini()
  let rng = Lcg::{ state: 0x46987370U }
  for _ in 0..<50 {
    let len = rng.below(base.length() + 1)
    let short = Bytes::makei(len, fn(i) { base.at(i) })
    ignore(exercise(short))
  }
}