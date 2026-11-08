#!/bin/sh
# Re-vendors xiph/rnnoise into this package.
#
# The upstream model ships as a 78 MB C source of float literals.
# We compile it once into a 14 MB binary blob (Resources) and build
# the C library with USE_WEIGHTS_FILE, so the big file never enters
# git.
#
# Usage: scripts/update.sh [git-ref]   (default: main)
set -eu

REF="${1:-main}"
PKG="$(cd "$(dirname "$0")/.." && pwd)"
C_DIR="$PKG/Sources/CRNNoise"
RES_DIR="$PKG/Sources/RNNoiseKit/Resources"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet https://github.com/xiph/rnnoise "$WORK/rnnoise"
cd "$WORK/rnnoise"
git checkout --quiet "$REF"
COMMIT="$(git rev-parse HEAD)"

HASH="$(cat model_version)"
MODEL="rnnoise_data-$HASH.tar.gz"
curl -sfLO "https://media.xiph.org/rnnoise/models/$MODEL"
echo "$HASH  $MODEL" | shasum -a 256 -c -
tar xzmf "$MODEL"

# Binary weights blob, loaded at runtime by RNNoiseModel.
cc -O2 -Iinclude -Isrc src/write_weights.c \
  src/parse_lpcnet_weights.c -o "$WORK/dump_weights"
(cd "$WORK" && ./dump_weights)

rm -rf "$C_DIR"
mkdir -p "$C_DIR/include" "$RES_DIR"
cp include/rnnoise.h "$C_DIR/include/"
for f in denoise rnn pitch kiss_fft celt_lpc nnet nnet_default \
         parse_lpcnet_weights rnnoise_tables; do
  cp "src/$f.c" "$C_DIR/"
done
cp src/*.h "$C_DIR/"
# vec.h includes this one unconditionally, even on ARM.
mkdir -p "$C_DIR/x86"
cp src/x86/x86_arch_macros.h "$C_DIR/x86/"

# Keep only init_rnnoise(); the weight arrays come from the blob.
{
  echo '#include "rnnoise_data.h"'
  sed -n '/^#ifndef DUMP_BINARY_WEIGHTS/,$p' src/rnnoise_data.c
} > "$C_DIR/rnnoise_data.c"

cp "$WORK/weights_blob.bin" "$RES_DIR/rnnoise_weights.bin"
cp COPYING "$PKG/LICENSE"
printf 'rnnoise %s\nmodel %s\n' "$COMMIT" "$HASH" > "$PKG/UPSTREAM"
echo "Vendored rnnoise $COMMIT"
