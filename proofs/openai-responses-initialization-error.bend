import Base
import ../packages/ai/src/api/openai-responses-initialization-error.bend as D
import ../laws/openai-responses-initialization-error.bend as Laws

def Laws.resolver_failure_retains_os_cause(code, message): {==}
def Laws.retry_failure_retains_os_cause(code, message): {==}
def Laws.short_seed_retains_actual_count(bytes): {==}
def Laws.configuration_diagnostics_preserved(cause): {==}
def Laws.runtime_diagnostic_preserved(cause): {==}
def Laws.single_diagnostic_displayed_unchanged(message):
  match message:
    case SNil{}: {==}
    case SCon{+char, +rest}:
      Equal.cong(String, String, tail => SCon{char, tail}, D.display(rest <> Nil{}), rest, Laws.single_diagnostic_displayed_unchanged(rest))
