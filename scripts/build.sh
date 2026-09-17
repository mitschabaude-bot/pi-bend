#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
mkdir -p build
BEND=${BEND:-$HOME/.bend/bin/bend}
SOURCE=${1:-src/main.bend}
OUTPUT=${2:-build/pi-bend}
"$BEND" "$SOURCE" -o "$OUTPUT.c"
python3 scripts/entry.py "$OUTPUT.c"
if pkg-config --exists libcurl; then
  CURL_CFLAGS=$(pkg-config --cflags libcurl)
  CURL_LIBS=$(pkg-config --libs libcurl)
else
  CURL_CFLAGS=-Ivendor/curl-dev/usr/include/x86_64-linux-gnu
  CURL_LIBS=-l:libcurl.so.4
fi
# pkg-config returns compiler word lists, intentionally split here.
"${CC:-clang}" -std=c11 "${PI_BEND_OPT:--O1}" -g $CURL_CFLAGS "$OUTPUT.c" -lpthread -lm $CURL_LIBS -o "$OUTPUT"
