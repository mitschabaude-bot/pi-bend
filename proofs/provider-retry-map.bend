import Base
import ../laws/provider-retry-map.bend as Laws
import ../packages/ai/src/utils/provider-retry.bend as Retry

def Laws.failure_identity(E, value):
  match value:
    case Retry.Other{cause}: {==}
    case Retry.Provider{Retry.ProviderError{cause, message, status, hint, milliseconds, seconds}}: {==}

def Laws.failure_composition(E, G, H, first, second, value):
  match value:
    case Retry.Other{cause}: {==}
    case Retry.Provider{Retry.ProviderError{cause, message, status, hint, milliseconds, seconds}}: {==}

def Laws.provider_metadata_retained(E, G, embed, cause, message, status, hint, milliseconds, seconds): {==}
def Laws.terminal_category_retained(E, G, embed, cause): {==}
def Laws.successful_owner_transfers(E, G, Owner, embed, owner): {==}
def Laws.failed_result_lifts_mapping(E, G, Owner, embed, cause): {==}
