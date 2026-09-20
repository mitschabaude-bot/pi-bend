import Base
import ../laws/provider-request.bend as Laws

def Laws.absent_replacement_retains_payload(P, E, original): {==}
def Laws.present_replacement_is_exact(P, E, original, replacement): {==}
def Laws.payload_failure_is_preserved(P, E, original, cause): {==}
def Laws.absent_payload_hook_has_no_effects(P, M, E, original, model): {==}
def Laws.successful_response_hook_retains_owner(E, Owner, release, owner): {==}
def Laws.failed_response_hook_retires_owner_first(E, Owner, release, owner, cause): {==}
def Laws.failed_request_bypasses_response_hook(M, E, Owner, model, hook, inspect, release, cause):
  match hook:
    case None{}: {==}
    case Some{_}: {==}
def Laws.absent_response_hook_retains_owner_without_effects(M, E, Owner, model, inspect, release, owner): {==}
