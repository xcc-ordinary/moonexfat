# Real-image cross-validation report

Date: 2026-11-25 · moonexfat 0.4.0 · target: wasm

## Method

Instead of formatting anything locally, we use a **public, real-world exFAT
image** with published ground truth:

- **Image**: Debian package `forensics-samples-exfat` 1.1.4-5 (`fs.exfat.xz`,
  MIT license) — a 50 MiB disk created with `mkfs.exfat`, one partition at
  sector 2048, populated with real media files. We decompress it and carve
  the partition at byte offset 1048576; no mount, no root, no formatting.
- **Ground truth**: the upstream `original-files/` directory
  (CC-BY-SA-4.0 / MIT, Joao Eriberto Mota Filho). Directories ending in `2`
  were deleted after copying, so exactly 18 files survive in 4 directories.
- **Check**: for each surviving file, `moonexfat extract` output is compared
  byte-for-byte (SHA-256) with the upstream original.

Reproduce: `bash scripts/cross-validate.sh` (also runs in CI).

## Volume geometry (parsed by moonexfat, boot checksum verified)

| Field | Value |
|---|---|
| Sector size | 512 B |
| Cluster size | 4096 B (8 sectors) |
| Volume length | 100352 sectors |
| FAT offset / length | 128 / 104 sectors |
| Cluster heap offset | 232 sectors |
| Cluster count | 12515 |
| Root directory cluster | 5 |
| Volume serial | 0xF86769A7 |
| Up-case table | 65536 entries, compressed, checksum verified |
| Allocated clusters | 2291 / 12515 |

## Result: 18 / 18 files match

| File | Bytes | SHA-256 |
|---|---:|---|
| audio1/debian.mp3 | 69727 | 3f39870230035b3861f411eef1ba623b7a6d1b74399badb15b641e6ebc54d8a0 |
| audio1/debian.ogg | 59748 | f86d633d642f978ae16ead64af41a0b9d2c9da65f8a6f470c274e22813a595af |
| audio1/debian.wav | 477158 | f922bcad473e037fb017b7946886ca50b2541f60441cf3a60b7bbc6c94c3a90b |
| movie1/VID_20191220_170832.mp4 | 2942343 | 9b0710a436413f75cc3cd1c1048aa3c4d7c28f76f51ef6a25413d0018d22ec99 |
| pic1/debian_logo.jpg | 36885 | 373206709037a7e561ebe5e9ee346dcbd56c35b1a8f9ff657d205a84b49ef36b |
| pic1/debian_logo.png | 1734 | bdfc92b4d89e37681003a7cc34bd7a0b3fc2aab780fe523f05b355bf25abb335 |
| pic1/debian.png | 83972 | a331c17e8e1c28e734937353b633708b8e0c0816ee5ff1926e89cff957a68f08 |
| pic1/debian.ppm | 1440061 | 70cfb0288203cdb94fbaa298e6627abdb6967fc5f3453d6b5df62b9725ffe3d8 |
| pic1/debian.xcf | 61239 | eecc9b18cb047b0fe22a327bc6623dcb8e7e80b397be0a47f4fcbccf1453c68d |
| pic1/empty.jpg | 1142 | d9935dd2a609fd816f8f3f0b9cc2ceeeb6899c959fb85cbd648be1ce713b107a |
| pic1/IMG_1054.JPG | 689275 | 76204f90870d97c2d462c58e113f8a90f2edf4b6fbd95ac2f0f876bb4e61b311 |
| pic1/IMG-20191006-WA0002.jpg | 166304 | 8f31fbc45826c8eaea2d60e61fb9810db38a66704adba3b7db05dd04b87eeb13 |
| pic1/IMG_20200827_231612.jpg | 3207823 | 29694a6e485e9bc523c08cc3333ffd17570ab61a94a41419fa9db81ff05e9ad0 |
| text1/a-text.docx | 4385 | 362194a5e2a7514513e8358c045dddec3e68e95e7e2b6bfe78e54494d8efaeec |
| text1/a-text.odt | 9159 | ff87e5d78849476f5d2d349efbc24e6afbfadef085fb2c4b05710692e02b0c9c |
| text1/a-text-pass-A5d.pdf | 18678 | 0debbcd5fe5dba76137d227fb304ed9da994d5796ba3fb16b4ae078c39c604be |
| text1/a-text-pass-peanuts.pdf | 18677 | 58b9b196ada172962630834cb8f0458eafb9163545c9abf58a79207291900d0d |
| text1/a-text.pdf | 18505 | f8fedcd36b43ffa7b7b6d5d66bd3992c9bdab89f8e1025db41f77a9e3a7c629c |

The largest files span hundreds of 4 KiB clusters through real FAT chains,
so this exercises chain walking, multi-cluster reads and DataLength
truncation on authentic on-disk layout — not just synthetic fixtures.

## Two spec bugs this validation caught (and fixed)

1. **Up-case table compression (§7.2.5).** Real formatters emit the
   recommended *compressed* table: `0xFFFF` followed by a count marks an
   identity run, and a bare trailing `0xFFFF` is the literal identity
   mapping of code point 0xFFFF. The initial implementation rejected
   `0xFFFF` outright; it now expands compression and validates the
   expanded table (65536 entries, checksum verified on the real image).
2. **SetChecksum accumulator width (§7.4.1.2).** The entry-set checksum
   uses a **16-bit** rotate-right-1 accumulator — not a 32-bit accumulator
   truncated to 16 bits (the carry rotates into bit 15, not bit 31).
   Synthetic fixtures had been self-consistent with the wrong width; the
   real image exposed it immediately. Corrected independent vector:
   HELLO.TXT SetChecksum = `0x357E`.

## Fuzzing

`volume/fuzz_wbtest.mbt` runs 300 deterministic mutations (fixed-seed LCG):
150 random 1–3 byte flips over the whole image, 100 targeted flips in the
FAT / root-directory / bitmap / up-case regions, and 50 random
truncations. Every input is either parsed or rejected with a structured
error — zero panics. Runs as part of `moon test` on both targets.

## Benchmarks (`moon bench --target wasm`, Windows x64, 2026-11-25)

| Operation | Mean ± σ |
|---|---|
| `Volume::open` (256 KiB mini volume, full chain) | 23.34 µs ± 766 ns |
| `list_root` (3 entry sets, checksums + name hashes) | 3.09 µs ± 44 ns |
| `read_file` NoFatChain (27 B) | 65.7 ns ± 2 ns |
| `read_file` FAT chain (1200 B, 3 clusters) | 7.14 µs ± 56 ns |
| `boot_checksum` (11 sectors) | 11.70 µs ± 58 ns |