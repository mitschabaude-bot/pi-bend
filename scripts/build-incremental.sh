#!/bin/sh
# Incremental native build (prototype). The compiler keeps segment and
# constructor ids stable between builds (BEND_IDS) and deals each def to a
# fixed translation unit; each unit's preprocessed C is hashed with the
# flags, and its object is compiled only when no cached object has that hash.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

SOURCE=${1:?Bend entry point required}
OUTPUT=${2:?Output path required}
mkdir -p "$(dirname -- "$OUTPUT")"
CACHE=${BEND_CACHE:-$ROOT/build/bend-cache}
mkdir -p "$CACHE/obj"
UNITS=${BEND_TUS:-64}
export BEND_TUS="$UNITS"
export BEND_IDS="${BEND_IDS:-$CACHE/ids-$(printf %s "$SOURCE" | tr '/.' '__').json}"
PI_BEND_DEFAULT="$ROOT/build/bend-native-toolchain/bend2/main.ts"
"${BEND:-$PI_BEND_DEFAULT}" "$SOURCE" -o "$OUTPUT.c"
CC=${CC:-clang}
FLAGS="-fbracket-depth=2048 ${BEND_CFLAGS:-} -std=c11 ${PI_BEND_OPT:--O1} -DBEND_TUS=$UNITS"
SALT=$("$CC" --version | head -1)
export CC FLAGS SALT CACHE OUTPUT
seq 0 $((UNITS - 1)) | xargs -P "$(nproc)" -I{} sh -c '
  k={}; i="$OUTPUT.$k.i"
  $CC $FLAGS -DBEND_TU=$k -E -P "$OUTPUT.c" -o "$i"
  h=$( { printf "%s\n%s\n" "$SALT" "$FLAGS"; cat "$i"; } | sha256sum | cut -c1-40)
  if [ ! -f "$CACHE/obj/$h.o" ]; then
    $CC $FLAGS -x cpp-output -c "$i" -o "$CACHE/obj/$h.o.$$" && mv "$CACHE/obj/$h.o.$$" "$CACHE/obj/$h.o"
    echo "unit $k compiled"
  fi
  ln -f "$CACHE/obj/$h.o" "$OUTPUT.$k.o"
  rm -f "$i"'
objects=""
k=0
while [ "$k" -lt "$UNITS" ]; do objects="$objects $OUTPUT.$k.o"; k=$((k + 1)); done
"$CC" $objects -lpthread -lm -o "$OUTPUT"
rm -f $objects
