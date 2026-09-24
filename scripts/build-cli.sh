#!/bin/sh
# Build the pi CLI. It owns its whole command line (`pi --help`,
# `pi --model x`): the Bend runtime reads no flags from it, and BEND_THREADS
# sets the worker count (patches/bend-app-argv.patch).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec env BEND_CFLAGS="${BEND_CFLAGS:-} -DBEND_APP_ARGV" sh "$ROOT/scripts/build-pure.sh" packages/coding-agent/src/main.bend "${1:-build/pi-cli}"
