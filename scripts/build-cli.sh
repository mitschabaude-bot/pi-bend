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
OUTPUT=${1:-build/pi-cli}
SOURCE=packages/coding-agent/src/main.bend
if [ "$#" -gt 0 ]; then shift; fi
PI_BEND_DEFAULT="$ROOT/build/bend-native-toolchain/bend2/main.ts"
[ -x "$PI_BEND_DEFAULT" ] || PI_BEND_DEFAULT="$HOME/.bend/bin/bend"
mkdir -p "$ROOT/build"
(cd "$ROOT" && "${BEND:-$PI_BEND_DEFAULT}" scripts/extension-sources.bend -o build/extension-sources.js)
DISCOVERED=$(bun "$ROOT/build/extension-sources.js")
GENERATED=$(printf '%s\n' "$DISCOVERED" | python3 "$ROOT/scripts/link-extensions.py" --sources-json "$@")
if [ -n "$GENERATED" ]; then
  SOURCE=${GENERATED%% *}
  REGISTRY=${GENERATED#* }
  trap 'rm -f "$ROOT/$SOURCE" "$ROOT/$REGISTRY"' EXIT
  trap 'exit 1' HUP INT TERM
fi
if [ "${BEND_INCREMENTAL:-1}" != 0 ]; then
  env BEND_CFLAGS="$FLAGS" sh "$ROOT/scripts/build-incremental.sh" "$SOURCE" "$OUTPUT"
  exit
fi
CORES=$(nproc 2>/dev/null || echo 4)
[ "$CORES" -gt 16 ] && CORES=16
env BEND_TUS="${BEND_TUS:-$CORES}" BEND_CFLAGS="$FLAGS" sh "$ROOT/scripts/build-pure.sh" "$SOURCE" "$OUTPUT"
