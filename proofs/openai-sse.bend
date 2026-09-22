import Base
import ../packages/ai/src/api/openai-sse.bend as Sse
import ../laws/openai-sse.bend as Laws

def Laws.done_marker_suppresses_later_frames(synthesize, event): {==}
def Laws.done_prefix_enters_done_state(synthesize, name, raw): {==}
def Laws.thread_events_bypass_error_detection(synthesize, event, data, raw, value): {==}
def Laws.thread_event_json_failures_target_the_console(synthesize, event, data, raw, cause): {==}
def Laws.data_json_failures_target_the_client_logger(synthesize, event, data, raw, cause): {==}
def Laws.null_error_field_is_a_message(synthesize, event, data): {==}
def Laws.false_error_field_is_a_message(synthesize, event, data): {==}
def Laws.empty_text_error_field_is_a_message(synthesize, event, data): {==}
def Laws.object_error_field_rejects_the_stream(synthesize, event, data, fields): {==}
def Laws.array_error_field_rejects_the_stream(synthesize, event, data, items): {==}
def Laws.nonempty_text_error_field_rejects_the_stream(synthesize, event, data, head, tail): {==}
def Laws.synthesized_delivery_carries_the_event_name(event, data): {==}
