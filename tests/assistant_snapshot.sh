#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
flock /tmp/pi-bend-build.lock sh scripts/build-pure.sh packages/agent/test/assistant-snapshot.bend build/test-assistant-snapshot
for threads in 1 4; do
  timeout 30 build/test-assistant-snapshot --threads "$threads"
done
