#!/bin/sh
# Compile a Bend entry point without prototype effects or foreign libraries.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
SOURCE=${1:?Bend entry point required}
OUTPUT=${2:?Output path required}
mkdir -p "$(dirname -- "$OUTPUT")"
PI_BEND_DEFAULT="$ROOT/build/bend-native-toolchain/bend2/main.ts"
[ -x "$PI_BEND_DEFAULT" ] || PI_BEND_DEFAULT="$HOME/.bend/bin/bend"
"${BEND:-$PI_BEND_DEFAULT}" "$SOURCE" -o "$OUTPUT.c"
# Generic records can produce C match trees deeper than Clang's default 256.
# This changes only the generated-code parser limit, not runtime behavior.
PI_BEND_CC=${CC:-clang}
case "$("$PI_BEND_CC" --version)" in
  *clang*) set -- -fbracket-depth=2048 ;;
  *) set -- ;;
esac
# BEND_TUS=N (also read by the compiler when it emits C) compiles the one
# generated source as N translation units in parallel and links them.
UNITS=${BEND_TUS:-1}
if [ "$UNITS" -gt 1 ]; then
  k=0
  while [ "$k" -lt "$UNITS" ]; do
    "$PI_BEND_CC" "$@" -std=c11 "${PI_BEND_OPT:--O1}" -DBEND_TUS="$UNITS" -DBEND_TU="$k" -c "$OUTPUT.c" -o "$OUTPUT.$k.o" &
    k=$((k + 1))
  done
  wait
  k=0; objects=""
  while [ "$k" -lt "$UNITS" ]; do objects="$objects $OUTPUT.$k.o"; k=$((k + 1)); done
  "$PI_BEND_CC" $objects -lpthread -lm -o "$OUTPUT"
  rm -f $objects
else
  "$PI_BEND_CC" "$@" -std=c11 "${PI_BEND_OPT:--O1}" "$OUTPUT.c" -lpthread -lm -o "$OUTPUT"
fi
