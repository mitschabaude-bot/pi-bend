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
sh scripts/build.sh tests/unicode.bend build/test-unicode
python3 tests/unicode_test.py
sh scripts/build.sh tests/truncate.bend build/test-truncate
build/test-truncate
sh scripts/build.sh tests/truncate_runner.bend build/test-truncate-runner
python3 tests/upstream_truncate.py
