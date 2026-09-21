import Base
import ../laws/openai-responses-cleartext-system-runtime.bend as Laws
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as System

def Laws.resolver_failure_skips_hosts_loading(files, cause):
  match files:
    case System.Files{_, _, _, _, _, _}: {==}
def Laws.configuration_failure_allocates_no_runtime(options, cause): {==}
def Laws.initialization_failure_retains_cause(Reason, snapshot, cause): {==}
def Laws.initialized_owner_retains_full_snapshot(Reason, snapshot, runtime): {==}
def Laws.borrowing_retains_snapshot_and_dependencies(Reason, snapshot, runtime, dependencies): {==}
