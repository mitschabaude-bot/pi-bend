#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
python3 tests/json_stringify_vectors.py
flock /tmp/pi-bend-build.lock sh scripts/build-pure.sh packages/ai/test/json.bend build/test-json
for threads in 1 4; do
  timeout 40 build/test-json --threads "$threads"
done
