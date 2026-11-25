// Cluster-run (extent) analysis: how a file's data is laid out on disk.

///|
/// The contiguous cluster runs of a file's data, in logical order:
/// (first_cluster, run_length). A single run means the file is
/// unfragmented; NoFatChain files always have exactly one run.
pub fn Volume::cluster_runs(
  self : Volume,
  entry : @entries.FileEntry,
) -> Array[(UInt, Int)] raise VolumeError {
  let dl = entry.data_length
  if dl <= 0L {
    return []
  }
  let csize = self.boot.cluster_size()
  let n = ((dl + csize.to_int64() - 1L) / csize.to_int64()).to_int()
  if entry.no_fat_chain {
    return [(entry.first_cluster, n)]
  }
  let chain = self.fat.chain(entry.first_cluster) catch {
    e => raise FatFailed(e.message())
  }
  guard chain.length() >= n else {
    raise DataLengthInvalid(dl)
  }
  let runs : Array[(UInt, Int)] = []
  for i in 0..<n {
    let c = chain[i]
    if runs.length() > 0 {
      let (start, len) = runs[runs.length() - 1]
      if start.to_int64() + len.to_int64() == c.to_int64() {
        runs[runs.length() - 1] = (start, len + 1)
        continue
      }
    }
    runs.push((c, 1))
  }
  runs
}