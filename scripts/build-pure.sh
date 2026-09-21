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
"$PI_BEND_CC" "$@" -std=c11 "${PI_BEND_OPT:--O1}" "$OUTPUT.c" -lpthread -lm -o "$OUTPUT"
