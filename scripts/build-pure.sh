#!/bin/sh
# Compile a Bend entry point without prototype effects or foreign libraries.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
SOURCE=${1:?Bend entry point required}
OUTPUT=${2:?Output path required}
mkdir -p "$(dirname -- "$OUTPUT")"
"${BEND:-$HOME/.bend/bin/bend}" "$SOURCE" -o "$OUTPUT.c"
"${CC:-clang}" -std=c11 "${PI_BEND_OPT:--O1}" "$OUTPUT.c" -lpthread -lm -o "$OUTPUT"
