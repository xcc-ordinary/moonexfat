#!/usr/bin/env bash
# Cross-validate moonexfat against a real mkfs.exfat-formatted image.
#
# Image source : Debian package forensics-samples-exfat (fs.exfat.xz, MIT),
#                a 50 MiB disk with one exFAT partition at sector 2048.
# Ground truth : original-files/ from the upstream repository
#                (CC-BY-SA-4.0 / MIT, Joao Eriberto Mota Filho).
#
# For every surviving file, `moonexfat extract` output is compared
# byte-for-byte with the upstream original. Exits non-zero on any mismatch.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

DEB_URL="https://deb.debian.org/debian/pool/main/f/forensics-samples/forensics-samples-exfat_1.1.4-5_all.deb"
RAW="https://raw.githubusercontent.com/eribertomota/forensics-samples/master/original-files"

echo "== downloading real exFAT sample (Debian forensics-samples) =="
curl -fsSL "$DEB_URL" -o "$WORK/samples.deb"

# .deb is an ar archive; pull out data.tar.* without external ar tools.
python3 - "$WORK" <<'PY'
import sys, pathlib
work = pathlib.Path(sys.argv[1])
data = (work / 'samples.deb').read_bytes()
pos = 8
while pos < len(data):
    name = data[pos:pos+16].decode().strip()
    size = int(data[pos+48:pos+58].decode().strip())
    if name.startswith('data.tar'):
        (work / name).write_bytes(data[pos+60:pos+60+size])
    pos += 60 + size + (size % 2)
PY
tar -xf "$WORK"/data.tar.* -C "$WORK"

# Decompress and carve the exFAT partition (starts at sector 2048).
python3 - "$WORK" <<'PY'
import sys, lzma, pathlib
work = pathlib.Path(sys.argv[1])
img = lzma.open(work / 'usr/share/forensics-samples/fs.exfat.xz').read()
(work / 'real.exfat').write_bytes(img[2048*512:])
PY

FILES="
audio1/debian.mp3
audio1/debian.ogg
audio1/debian.wav
movie1/VID_20191220_170832.mp4
pic1/debian_logo.jpg
pic1/debian_logo.png
pic1/debian.png
pic1/debian.ppm
pic1/debian.xcf
pic1/empty.jpg
pic1/IMG_1054.JPG
pic1/IMG-20191006-WA0002.jpg
pic1/IMG_20200827_231612.jpg
text1/a-text.docx
text1/a-text.odt
text1/a-text-pass-A5d.pdf
text1/a-text-pass-peanuts.pdf
text1/a-text.pdf
"

echo "== inspect =="
moon run cmd/moonexfat --target wasm -- inspect "$WORK/real.exfat"
echo "== ls =="
moon run cmd/moonexfat --target wasm -- ls "$WORK/real.exfat"

ok=0; fail=0
for f in $FILES; do
  curl -fsSL "$RAW/$f" -o "$WORK/orig"
  moon run cmd/moonexfat --target wasm -- extract "$WORK/real.exfat" "$f" "$WORK/out" > /dev/null
  if cmp -s "$WORK/orig" "$WORK/out"; then
    echo "MATCH     $f ($(stat -c%s "$WORK/out") bytes)"
    ok=$((ok+1))
  else
    echo "MISMATCH  $f"
    fail=$((fail+1))
  fi
done

echo "== $ok matched, $fail failed =="

# Deleted-file recovery: directories ending in 2 were deleted after
# copying; their entry sets and (unreused) data survive in the image.
DELETED_FILES="
audio2/deleted.mp3
audio2/deleted.ogg
audio2/deleted.wav
movie2/movie-hello.avi
movie2/movie-hello.mp4
movie2/movie-hello.mpeg
movie2/movie-hello.ogg
pic2/d-debian.jpg
pic2/d-debian.png
pic2/d-debian.ppm
pic2/d-debian.xcf
pic2/IMG_20191224_234846.jpg
pic2/IMG_20200124_231153.jpg
pic2/IMG_20200608_111614.jpg
text2/d-text.docx
text2/d-text.odt
text2/d-text.pdf
text2/test.sh
"

echo "== deleted-file recovery =="
rok=0; rfail=0
for f in $DELETED_FILES; do
  curl -fsSL "$RAW/$f" -o "$WORK/orig"
  moon run cmd/moonexfat --target wasm -- recover "$WORK/real.exfat" "$f" "$WORK/out" > /dev/null
  if cmp -s "$WORK/orig" "$WORK/out"; then
    echo "RECOVERED  $f ($(stat -c%s "$WORK/out") bytes)"
    rok=$((rok+1))
  else
    echo "RECOVERY-MISMATCH  $f"
    rfail=$((rfail+1))
  fi
done
echo "== $rok recovered & matched, $rfail failed =="

[ "$fail" -eq 0 ] && [ "$rfail" -eq 0 ]