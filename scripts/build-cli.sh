#!/bin/sh
# Build the pi CLI. It owns its whole command line (`pi --help`,
# `pi --model x`): the Bend runtime reads no flags from it
# (patches/bend-app-argv.patch). It runs one worker unless BEND_THREADS says
# otherwise (patches/bend-default-threads.patch).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# One translation unit per core, at most 16 (about 1.5 GB of Clang memory each).
CORES=$(nproc 2>/dev/null || echo 4)
[ "$CORES" -gt 16 ] && CORES=16
exec env BEND_TUS="${BEND_TUS:-$CORES}" BEND_CFLAGS="${BEND_CFLAGS:-} -DBEND_APP_ARGV -DBEND_DEFAULT_THREADS=1" sh "$ROOT/scripts/build-pure.sh" packages/coding-agent/src/main.bend "${1:-build/pi-cli}"
