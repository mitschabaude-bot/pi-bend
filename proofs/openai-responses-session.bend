import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-session.bend as Session
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/utils/event-stream.bend as Events
import ../packages/runtime/src/callback.bend as C
import ../laws/openai-responses-session.bend as Laws

def Laws.publication_preserves_event(A, G, E, stream, event): {==}

def Laws.end_supplies_final_snapshot(A, G, stream, output): {==}

def Laws.borrow_running_preserves_task_and_stream(A, G, E, stream, task): {==}

def Laws.borrow_finished_preserves_result_and_stream(A, G, E, stream, result): {==}

def Laws.completion_retains_run_result(A, G, E, stream, result): {==}

def Laws.finished_wait_has_no_effects(A, G, E, stream, result): {==}

def Laws.running_wait_joins_before_completion(A, G, E, stream, task): {==}

def Laws.callbacks_retire_before_run_result(A, G, E, sink, finish, result): {==}

def Laws.finished_disposal_preserves_result(A, G, E, stream, result): {==}

def Laws.running_disposal_joins_before_stream_retirement(A, G, E, stream, task): {==}

def Laws.dependency_cleanup_precedes_unchanged_result(A, G, E, result, cleanup): {==}
