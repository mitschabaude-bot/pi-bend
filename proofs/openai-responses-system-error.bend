import Base
import ../laws/openai-responses-system-error.bend as Laws

def Laws.acquisition_success_transfers_owner_unchanged(Reason, Hook, Owner, owner): {==}
def Laws.acquisition_failure_preserves_complete_typed_cause(Reason, Hook, Owner, cause): {==}
def Laws.release_failure_preserves_complete_typed_cause(Reason, Hook, cause): {==}
