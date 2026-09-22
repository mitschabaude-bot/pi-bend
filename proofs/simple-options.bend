import Base
import ../laws/simple-options.bend as Laws
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/simple-options.bend as Options

def Laws.clamped_reasoning_never_exceeds_high(level):
  match level:
    case T.Minimal{}: {==}
    case T.Low{}: {==}
    case T.Medium{}: {==}
    case T.High{}: {==}
    case T.XHigh{}: {==}
    case T.Max{}: {==}

def Laws.clamping_is_idempotent(level):
  match level:
    case T.Minimal{}: {==}
    case T.Low{}: {==}
    case T.Medium{}: {==}
    case T.High{}: {==}
    case T.XHigh{}: {==}
    case T.Max{}: {==}

# A contradictory Bool hypothesis is eliminated through a type-valued motive.
def Truth(flag: Bool) -> Type:
  match flag:
    case False{}: Unit
    case True{}: Empty

def contradiction(e: {False{} == True{} : Bool}) -> Empty:
  %e : Truth(_); Unit{}

def Laws.clamping_keeps_levels_up_to_high(level, low):
  match level:
    case T.Minimal{}: {==}
    case T.Low{}: {==}
    case T.Medium{}: {==}
    case T.High{}: {==}
    case T.XHigh{}: Empty.absurd({Options.clampLevel(T.XHigh{}) == T.XHigh{} : T.ThinkingLevel}, contradiction(low))
    case T.Max{}: Empty.absurd({Options.clampLevel(T.Max{}) == T.Max{} : T.ThinkingLevel}, contradiction(low))

def Laws.explicit_budgets_are_used(level, minimal, low, medium, high):
  match level:
    case T.Minimal{}: {==}
    case T.Low{}: {==}
    case T.Medium{}: {==}
    case T.High{}: {==}
    case T.XHigh{}: {==}
    case T.Max{}: {==}

def Laws.empty_custom_budgets_equal_the_defaults(level):
  match level:
    case T.Minimal{}: {==}
    case T.Low{}: {==}
    case T.Medium{}: {==}
    case T.High{}: {==}
    case T.XHigh{}: {==}
    case T.Max{}: {==}

def Laws.fitting_the_budget_keeps_the_ceiling(order, maxTokens, thinkingBudget):
  match order:
    case None{}: {==}
    case Some{LT{}}: {==}
    case Some{EQ{}}: {==}
    case Some{GT{}}: {==}

def Laws.a_budget_below_the_ceiling_is_kept(maxTokens, thinkingBudget): {==}
