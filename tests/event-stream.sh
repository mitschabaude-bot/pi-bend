#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
sh scripts/build-pure.sh packages/ai/test/event-stream.bend build/test-event-stream
for threads in 1 4; do
  timeout 40 build/test-event-stream --threads "$threads"
done
