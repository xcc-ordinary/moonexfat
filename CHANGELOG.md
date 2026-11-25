# Changelog

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