#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
for suite in event-stream assistant-event-stream event-stream-atomic; do
  sh scripts/build-pure.sh "packages/ai/test/$suite.bend" "build/test-$suite"
  for threads in 1 4; do
    timeout 40 "build/test-$suite" --threads "$threads"
  done
done
