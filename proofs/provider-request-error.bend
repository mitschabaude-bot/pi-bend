import Base
import ../laws/provider-request-error.bend as Laws

def Laws.response_cleanup_cannot_replace_primary_diagnostic(E, cause, cleanup, render): {==}
def Laws.hook_diagnostics_do_not_depend_on_stage(E, cause, render): {==}
def Laws.retry_keeps_its_diagnostic_policy(E, cause, render): {==}
