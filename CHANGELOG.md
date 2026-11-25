# Changelog

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