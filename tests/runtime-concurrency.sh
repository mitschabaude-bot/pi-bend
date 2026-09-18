#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
for module in ref deferred deferred-cancellation callback abort; do
  sh scripts/build-pure.sh "packages/runtime/test/$module.bend" "build/test-$module"
  "build/test-$module" --threads "${PI_BEND_TEST_THREADS:-4}"
done
