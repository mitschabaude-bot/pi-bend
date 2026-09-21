import Base
import ../laws/openai-responses-default-session.bend as Laws
import ../packages/ai/src/api/openai-responses-default-session.bend as Default

def Laws.prepared_grammar_is_preserved(key, url, headers, payload, compat, grammar, retention): {==}
def Laws.default_pricing_precedes_dependency_retirement(E, owner, dependencies): {==}
def Laws.owned_pricing_reaches_processor_context(Reason, SourceError, HookError, dependencies, pricing):
  match dependencies:
    case Default.Dependencies{_, _, _, _, _, _, _}: {==}
