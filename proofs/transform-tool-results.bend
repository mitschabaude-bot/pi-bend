import Base
import ../laws/transform-tool-results.bend as Laws
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/api/transform-tool-results.bend as Repair

def Laws.errored_assistant_turns_are_not_replayed(P, A, G, D, content, api, provider, model, responseModel, responseId, level, diagnostics, usage, deferred, error, rawReason, endTurn, timestamp, output): {==}

def Laws.aborted_assistant_turns_are_not_replayed(P, A, G, D, content, api, provider, model, responseModel, responseId, level, diagnostics, usage, deferred, error, rawReason, endTurn, timestamp, output): {==}

def Laws.replayable_assistant_turns_track_their_tool_calls(P, A, G, D, content, api, provider, model, responseModel, responseId, level, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp, output, replayable):
  Equal.cong(Bool, Repair.State<P, A, G, D>, keep => Repair.assistantSelected(P, A, G, D, keep, Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}, Repair.toolCalls(A, content), output), Repair.replayable(reason), True{}, replayable)

def Laws.tool_results_answer_their_call(P, A, G, D, id, name, content, details, usage, isError, timestamp, pending, seen, held, output): {==}

def Laws.system_messages_wait_for_pending_results(P, A, G, D, system, call, pending, seen, held, output): {==}

def Laws.system_messages_pass_when_nothing_is_pending(P, A, G, D, system, seen, held, output): {==}

def Laws.answered_calls_are_left_alone(call, output): {==}

def Laws.unanswered_calls_get_an_error_result(id, name, arguments, signature, namespace, output): {==}

def Laws.flush_without_pending_calls_releases_held_messages(seen, held, output): {==}

def Laws.user_turns_release_held_messages_first(user, seen, held, output): {==}

def Laws.assistant_turns_release_held_messages_first(source, seen, held, output): {==}
