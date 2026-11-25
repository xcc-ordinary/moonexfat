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

## Deleted-file recovery: 18 / 18 recovered & match

The sample's `audio2` / `movie2` / `pic2` / `text2` directories were deleted
after copying. moonexfat parses the deleted entry sets (InUse bit cleared:
0x05/0x40/0x41), confirms their former clusters are still free in the
allocation bitmap, and reads the data contiguously (`recover`). All 18
deleted files match their upstream originals byte-for-byte:

| File | Bytes | SHA-256 |
|---|---:|---|
| audio2/deleted.mp3 | 28970 | d069980970a2a054b5428b46c5acbbdbae6de8c951c83156d067c63029b19e9f |
| audio2/deleted.ogg | 26282 | b461ebbcc60946b0944689f2cc17b48ea34f922d4c46ae9b29d694c00b0ff6ba |
| audio2/deleted.wav | 183678 | 24ae095ca72500539599665db3b8beeabda43f57a33883c2a65bf9fb172c6432 |
| movie2/movie-hello.avi | 2781426 | eac488b5793f5428ea70f064abbf28941b4ede26824aec1808fcb528c64b1587 |
| movie2/movie-hello.mp4 | 4288306 | 68162af4e15b20fb61261e55de79e989f53d6295f6226b4bda1905b8c40e9676 |
| movie2/movie-hello.mpeg | 1054720 | 6a7de01a1606c17b819f6548f2c89d30512a8e7528c529141409c51c3bd141a6 |
| movie2/movie-hello.ogg | 767624 | 20e0b2d1c2c6a8c06fa3c2f165036be5a4cad8b6150bff76966a8e64e2541ea7 |
| pic2/d-debian.jpg | 159927 | da6ae48fbcde42dcef2d6795bb169da5a62d9d54c98df2a5e33df90e93a62e2f |
| pic2/d-debian.png | 423494 | d8edcef4a655717afb028db6593a92055dcc90e0e4cbc5bf038545f6ab1818f7 |
| pic2/d-debian.ppm | 1440061 | 1bf6d6aa183f20d8a55bab110e8a053a4f46e11313cf55f1d46f7687035b0863 |
| pic2/d-debian.xcf | 479718 | 8a3109d19cf072e2d453574d1978429a2c3922f1bba5ec3e42766f7d24f95fca |
| pic2/IMG_20191224_234846.jpg | 6266853 | 653193b3238e0c056cc834c8144aa9801419516e751f8682daa425d7f3dacc5c |
| pic2/IMG_20200124_231153.jpg | 2680169 | 850048a1eb65a2147ea05927976aa927c03926c85f880c2f9d2196380bf10403 |
| pic2/IMG_20200608_111614.jpg | 4857710 | 1f23a3bd64e685f9364046b1ff05b2953071c18e90b2bfb3f9a1e0d6ad234bf5 |
| text2/d-text.docx | 4406 | 79bff7bc58cb07f94a0eda820ae2ddafbd42fef7c270288ea46178350ebc2b29 |
| text2/d-text.odt | 9204 | 2a0b1c8962164a22bb5ffbaaab7eb60e6037e328d3aafb56beb49a2f285b556d |
| text2/d-text.pdf | 18992 | 8f6144fd20a9e8a977ff8fc3ea8a8ddab287171444e1e0676ea7bf7e7a2355a9 |
| text2/test.sh | 42 | 924b9ba34acfccbd36da4f3b18f372051467d4a832d74b336f1bffd4d9ea6442 |

Recovery is best-effort by design: once clusters are reallocated and
overwritten the data is gone; `deleted` reports `intact` vs `reused` from
the bitmap so the caller knows which case they are in.

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