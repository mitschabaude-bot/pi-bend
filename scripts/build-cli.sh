#!/bin/sh
# Build the pi CLI. It owns its whole command line (`pi --help`,
# `pi --model x`): the Bend runtime reads no flags from it
# (patches/bend-app-argv.patch). It runs one worker unless BEND_THREADS says
# otherwise (patches/bend-default-threads.patch).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec env BEND_CFLAGS="${BEND_CFLAGS:-} -DBEND_APP_ARGV -DBEND_DEFAULT_THREADS=1" sh "$ROOT/scripts/build-pure.sh" packages/coding-agent/src/main.bend "${1:-build/pi-cli}"
