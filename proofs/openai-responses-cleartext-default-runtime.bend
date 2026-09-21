import Base
import ../laws/openai-responses-cleartext-default-runtime.bend as Laws

def Laws.initialization_failure_retires_date_before_returning_cause(Reason, Source, date, cause): {==}
def Laws.initialization_success_transfers_both_owners(Reason, Source, date, runtime): {==}
def Laws.borrow_preserves_owners_and_dependencies(Reason, Source, date, runtime, dependencies): {==}
def Laws.retry_runtime_retires_before_date_callback(Reason, Source, date, runtime): {==}
