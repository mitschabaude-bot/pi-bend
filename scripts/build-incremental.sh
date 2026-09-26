#!/bin/sh
# Build a Bend program incrementally: the compiler keeps segment and
# constructor ids stable between builds (BEND_IDS, patches/
# bend-incremental-ids.patch) and deals each definition to a fixed
# translation unit, so an edit changes few units' C. Each unit is
# preprocessed and hashed with the flags and Clang's version, and compiled
# only when the object cache has no object with that hash. The cache is
# shared by every worktree (objects are addressed by content); objects
# unused for three days are removed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

SOURCE=${1:?Bend entry point required}
OUTPUT=${2:?Output path required}
mkdir -p "$(dirname -- "$OUTPUT")"
CACHE=${BEND_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/pi-bend}
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
  touch "$CACHE/obj/$h.o"
  ln -f "$CACHE/obj/$h.o" "$OUTPUT.$k.o" 2>/dev/null || cp "$CACHE/obj/$h.o" "$OUTPUT.$k.o"
  rm -f "$i"'
objects=""
k=0
while [ "$k" -lt "$UNITS" ]; do objects="$objects $OUTPUT.$k.o"; k=$((k + 1)); done
"$CC" $objects -lpthread -lm -o "$OUTPUT"
rm -f $objects
find "$CACHE/obj" -name '*.o' -mtime +3 -delete
