import Base
import ../laws/openai-http-error.bend as Laws

def Laws.diagnostic_read_failure_retains_cause(E, metadata, cause): {==}
def Laws.construction_retains_diagnostic(E, metadata, diagnostic, text): {==}
def Laws.encoding_failure_retains_diagnostic(E, metadata, diagnostic): {==}
def Laws.present_error_is_selected(fallback, error): {==}
def Laws.unrecognized_json_is_retained(value): {==}
def Laws.nonempty_message_text_is_retained(whole, head, tail): {==}
def Laws.retry_retains_original_error(metadata, diagnostic, message): {==}
def Laws.text_normalization_preserves_rendered_message(metadata, text, message): {==}
def Laws.json_normalization_retains_input(metadata, value, message): {==}
