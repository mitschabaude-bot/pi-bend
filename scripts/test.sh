#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
sh scripts/build.sh tests/json.bend build/test-json
build/test-json
sh scripts/build.sh tests/sse.bend build/test-sse
build/test-sse
sh scripts/build.sh tests/runtime.bend build/test-runtime
python3 tests/runtime_fixture.py
