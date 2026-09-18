#!/bin/sh
# Regression checks for the native-value migration; not full-port acceptance.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
sh scripts/build-pure.sh tests/library-types.bend build/test-library-types
build/test-library-types
for suite in transcript event-stream json native-agent; do
  sh "tests/$suite.sh"
done
for threads in 1 4; do
  PI_BEND_TEST_THREADS="$threads" sh tests/runtime-concurrency.sh
done
for suite in record_vectors constrained_sampling_vectors tool_declaration_vectors tool_state_vectors tool_history_vectors model_types model_metadata_vectors model_cost_vectors agent_types provider_option_types loop_config_types tool_preparation_types tool_result_message tool_batch_vectors tool_batch_sequential_check tool_batch_parallel_check turn_completion_check tool_changes_check turn_preparation_check main_loop_check loop_entry_check default_stream_check loop_stream_check agent_state_check tool_selection_vectors before_tool_decision_vectors turn_update_vectors tool_result_vectors validation_primitives_vectors primitive_coercion_vectors schema_type_coercion_vectors schema_check unique_items_check schema_convert_check schema_container_check schema_builder_check schema_object_policy_check schema_string_check uri_component_check schema_references_check normalization_check recursive_coercion_check plain_validation_check validation_errors_check; do
  python3 "tests/$suite.py"
done
python3 scripts/test-inventory.py
