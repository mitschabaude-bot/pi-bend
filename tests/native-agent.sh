#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
for suite in tool-changes-clock turn-preparation turn-completion tool-execution-dispatch tool-call-parallel tool-call-parallel-gated tool-call-sequential validated-tool-execution tool-preparation-pipeline tool-execution tool-execution-stream agent-event-stream tool-finalization native-loop native-turn-hooks tool-preparation tool-emission truncated-calls assistant-snapshot; do
  sh scripts/build-pure.sh "packages/agent/test/$suite.bend" "build/test-$suite"
  for threads in 1 4; do
    timeout 40 "build/test-$suite" --threads "$threads"
  done
done
python3 tests/failed_turn_vectors.py

python3 tests/tool_update_scope.py
