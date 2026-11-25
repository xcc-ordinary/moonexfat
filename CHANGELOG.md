# Changelog

## 0.4.0 (2026-11-25)

Week 4 — real-image cross-validation, fuzzing, benchmarks.

- **Cross-validation**: 18/18 files extracted from a real `mkfs.exfat`
  image (Debian `forensics-samples-exfat`) match upstream originals
  byte-for-byte (SHA-256), including multi-MB files across hundreds of
  FAT-chained clusters. Reproducible via `scripts/cross-validate.sh`,
  also run in CI; full report in `docs/cross-validation.md`.
- **Fix: up-case table compression (§7.2.5)** — expand `0xFFFF` + count
  identity runs; a bare trailing `0xFFFF` is the literal mapping of code
  point 0xFFFF. The real image's recommended compressed table (65536
  entries) now parses and verifies.
- **Fix: SetChecksum accumulator width (§7.4.1.2)** — 16-bit rotate-right
  accumulate, not 32-bit truncated. Corrected independent vector:
  HELLO.TXT SetChecksum `0x357E` (was `0xEF86` under the wrong width);
  mini fixture patched accordingly.
- **Fuzzing**: 300 deterministic mutations (byte flips, targeted metadata
  flips, truncations) — zero panics, structured errors only.
- **Benchmarks**: `moon bench` suite for open / list / read / checksum.
- 67 tests (wasm + wasm-gc), 0 warnings.

## 0.3.0 (2026-11-25)

Week 3 — directory entry sets, path resolution and file reading.

- `entries`: file directory entry set parsing (File 0x85 + Stream Extension
  0xC0 + File Name 0xC1), SetChecksum (§6.3.3) and NameHash (§7.4.2)
  verification, deleted-set skipping, UTF-16 names with surrogate pairs,
  timestamp decoding; 7 new structured error variants.
- `volume`: `list_root` / `list_dir_entry`, case-insensitive `resolve`
  through subdirectories, `read_file` with contiguous (`NoFatChain`) and
  FAT-chain reads truncated to DataLength.
- CLI: new `ls`, `cat` (UTF-8) and `extract` subcommands.
- `testdata/mini.exfat` extended with real files: HELLO.TXT (single cluster,
  NoFatChain), DATA.BIN (1200 bytes across a 3-cluster FAT chain) and
  SUB/NESTED.TXT.
- 61 tests (wasm + wasm-gc); new independent vectors: HELLO.TXT SetChecksum
  0xEF86, NameHash 0x3046 / 0x6A4A. The mini boot checksum stays 0x46987370
  after PercentInUse changes — the spec's mutable-field exclusion in action.

## 0.2.0 (2026-11-25)

Week 2 — space management and volume metadata.

- `fat`: FAT entry classification and cluster-chain walking with cycle,
  bad-cluster and invalid-entry detection.
- `bitmap`: allocation bitmap with correct bit addressing and padding-bit
  masking in the allocated count.
- `upcase`: Up-case Table parsing with TableChecksum verification, ASCII
  mapping rule and 0xFFFF rejection; char/string case mapping.
- `entries`: root-directory scanning for Allocation Bitmap / Up-case Table /
  Volume Label entries; file entry sets skipped via SecondaryCount.
- `volume`: `Volume::open` integrates boot → FAT → root chain → bitmap +
  up-case; `cluster_chain` for inspection.
- `util`: shared little-endian readers, byte slicing, rotate checksum.
- CLI: `inspect` now reports volume metadata; new `chain` subcommand.
- 52 tests (wasm + wasm-gc); new independent vectors 0x46987370 (mini boot)
  and 0x88E38EE3 (up-case table); 256 KiB full mini-volume fixture.

## 0.1.0 (2026-11-25)

Initial release — week 1 of the 2026 MoonBit Hackathon (November season).

- `boot`: Main Boot Sector parsing with full spec-level validation
  (17 structured error variants), geometry helpers and 64-bit cluster offsets.
- `boot`: Boot Checksum per spec §3.4 (skips VolumeFlags / PercentInUse),
  full 12-sector boot-region verification including extended-sector signatures.
- `cmd/moonexfat`: `inspect` CLI — validates an image's boot region and
  prints its geometry; reports the exact checksum mismatch on corruption.
- 23 tests (wasm + wasm-gc), including an independently computed checksum
  vector (0x829BD81D) and a committed 6 KiB synthetic fixture.