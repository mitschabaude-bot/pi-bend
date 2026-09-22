import Base
import ../laws/openai-responses-stream.bend as Laws

def Laws.response_service_tier_overrides_the_request(tier, requested): {==}
def Laws.absent_response_service_tier_uses_the_request(requested): {==}
def Laws.terminal_failure_suppresses_pricing_and_stop_mapping(model, requested, response, status, reason, state, error): {==}
def Laws.max_output_truncation_is_a_length_stop(): {==}
def Laws.tool_calls_promote_a_plain_stop(): {==}
def Laws.tool_calls_never_change_other_stops(tool): {==}
def Laws.error_stops_ignore_tool_calls(tool): {==}
def Laws.stop_mapping_preserves_message_fields(G, content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp, reason, message): {==}
def Laws.end_without_terminal_response_is_an_error(): {==}
