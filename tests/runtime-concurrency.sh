#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
for module in ref identity deferred deferred-cancellation callback concurrent-all clock abort; do
  flock /tmp/pi-bend-build.lock sh scripts/build-pure.sh "packages/runtime/test/$module.bend" "build/test-$module"
  "build/test-$module" --threads "${PI_BEND_TEST_THREADS:-4}"
done
