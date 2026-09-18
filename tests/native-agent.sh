#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
for suite in agent agent-behavior agent-await agent-signal agent-busy agent-declarations agent-turn-options agent-late-updates agent-settings agent-input-callbacks agent-api-key agent-provider-callbacks agent-events agent-listener-start agent-runtime-concurrency agent-lifecycle agent-loop agent-loop-tools agent-loop-arguments agent-loop-parallel agent-loop-steering agent-loop-turns agent-loop-termination tool-changes-clock turn-preparation turn-completion tool-execution-dispatch tool-call-parallel tool-call-parallel-gated tool-call-sequential validated-tool-execution tool-preparation-pipeline tool-execution tool-execution-stream agent-event-stream tool-finalization native-loop native-turn-hooks tool-preparation tool-emission truncated-calls assistant-snapshot; do
  sh scripts/build-pure.sh "packages/agent/test/$suite.bend" "build/test-$suite"
  for threads in 1 4; do
    timeout 40 "build/test-$suite" --threads "$threads"
  done
done
python3 tests/failed_turn_vectors.py

python3 tests/tool_update_scope.py

node tests/agent_settings_reference.mts
node tests/agent_input_callbacks_reference.mts
node tests/agent_api_key_reference.mts
node tests/agent_provider_callbacks_reference.mts
