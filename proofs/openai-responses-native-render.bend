import Base
import ../laws/openai-responses-native-render.bend as Laws

def Laws.payload_wrapper_preserves_primary_diagnostic(Reason, Source, Hook, leaves, cause): {==}
def Laws.response_cleanup_cannot_replace_primary_diagnostic(Reason, Source, Hook, leaves, cause, cleanup): {==}
def Laws.provider_retry_metadata_does_not_replace_original_diagnostic(Reason, Source, Hook, leaves, cause, message, status, retry, milliseconds, seconds): {==}
def Laws.ordinary_request_wrapper_preserves_primary_diagnostic(Reason, Source, Hook, leaves, cause): {==}
def Laws.read_wrapper_preserves_primary_diagnostic(Reason, Source, Hook, leaves, cause): {==}
def Laws.emit_wrapper_preserves_primary_diagnostic(Reason, Source, Hook, leaves, cause): {==}
def Laws.tier_resolution_wrapper_preserves_primary_diagnostic(Reason, Source, Hook, leaves, cause): {==}
def Laws.pricing_wrapper_preserves_primary_diagnostic(Reason, Source, Hook, leaves, cause): {==}
