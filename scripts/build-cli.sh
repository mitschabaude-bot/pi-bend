#!/bin/sh
# Build the pi CLI. It owns its whole command line (`pi --help`,
# `pi --model x`): the Bend runtime reads no flags from it
# (patches/bend-app-argv.patch). It runs one worker unless BEND_THREADS says
# otherwise (patches/bend-default-threads.patch).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# The CLI builds incrementally (scripts/build-incremental.sh: 64 units, a
# shared object cache); BEND_INCREMENTAL=0 compiles the one C file as
# BEND_TUS units instead, one per core, at most 16.
FLAGS="${BEND_CFLAGS:-} -DBEND_APP_ARGV -DBEND_DEFAULT_THREADS=1"
if [ "${BEND_INCREMENTAL:-1}" != 0 ]; then
  exec env BEND_CFLAGS="$FLAGS" sh "$ROOT/scripts/build-incremental.sh" packages/coding-agent/src/main.bend "${1:-build/pi-cli}"
fi
CORES=$(nproc 2>/dev/null || echo 4)
[ "$CORES" -gt 16 ] && CORES=16
exec env BEND_TUS="${BEND_TUS:-$CORES}" BEND_CFLAGS="$FLAGS" sh "$ROOT/scripts/build-pure.sh" packages/coding-agent/src/main.bend "${1:-build/pi-cli}"
