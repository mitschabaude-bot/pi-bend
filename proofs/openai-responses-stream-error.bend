import Base
import ../laws/openai-responses-stream-error.bend as Laws

def Laws.parse_message_independent_of_diagnostic_context(cause, data, raw, target): {==}
def Laws.transport_message_survives_reader_wrapping(E, render, cause): {==}
def Laws.diagnostic_failure_preserves_its_own_cause(E, render, cause): {==}
def Laws.read_preserves_callback_diagnostic(E, render, cause): {==}
def Laws.tier_resolution_preserves_callback_diagnostic(E, render, cause): {==}
def Laws.terminal_message_preserved(E, render, cause): {==}
def Laws.emit_preserves_callback_diagnostic(E, render, cause): {==}
def Laws.pricing_preserves_callback_diagnostic(E, render, cause): {==}
