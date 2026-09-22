import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/simple-options.bend as Options
import ../packages/ai/src/utils/thinking-levels.bend as Levels
import ../packages/runtime/src/f64.bend as F

# Reasoning effort clamping for providers that stop at "high".

law clamped_reasoning_never_exceeds_high:
  for level: T.ThinkingLevel
  {U32.is_le(Levels.rank(T.Thinking{Options.clampLevel(level)}), 4) == True{} : Bool}

law clamping_is_idempotent:
  for level: T.ThinkingLevel
  {Options.clampLevel(Options.clampLevel(level)) == Options.clampLevel(level) : T.ThinkingLevel}

law clamping_keeps_levels_up_to_high:
  for level: T.ThinkingLevel
  for low: {U32.is_le(Levels.rank(T.Thinking{level}), 4) == True{} : Bool}
  {Options.clampLevel(level) == level : T.ThinkingLevel}

# Thinking budgets: explicit budgets win, empty custom budgets equal the
# defaults, and fitting the budget never changes the response ceiling.

def budgetFor(level: T.ThinkingLevel, minimal: F64, low: F64, medium: F64, high: F64) -> F64:
  match level:
    case T.Minimal{}: minimal
    case T.Low{}: low
    case T.Medium{}: medium
    case _: high

law explicit_budgets_are_used:
  for level: T.ThinkingLevel
  for minimal: F64
  for low: F64
  for medium: F64
  for high: F64
  {Options.selectBudget(level, T.ThinkingBudgets{Some{minimal}, Some{low}, Some{medium}, Some{high}}) == budgetFor(level, minimal, low, medium, high) : F64}

law empty_custom_budgets_equal_the_defaults:
  for level: T.ThinkingLevel
  {Options.thinkingBudgetForLevel(level, Some{T.ThinkingBudgets{None{}, None{}, None{}, None{}}}) == Options.thinkingBudgetForLevel(level, None{}) : F64}

def allocationMax(allocation: Options.ThinkingTokenAllocation) -> F64:
  match allocation:
    case Options.ThinkingTokenAllocation{maxTokens, _}: maxTokens

law fitting_the_budget_keeps_the_ceiling:
  for order: Maybe<&2, Cmp>
  for +maxTokens: F64
  for thinkingBudget: F64
  {allocationMax(Options.fitBudget(order, maxTokens, thinkingBudget)) == maxTokens : F64}

law a_budget_below_the_ceiling_is_kept:
  for +maxTokens: F64
  for thinkingBudget: F64
  {Options.fitBudget(Some{GT{}}, maxTokens, thinkingBudget) == Options.ThinkingTokenAllocation{maxTokens, thinkingBudget} : Options.ThinkingTokenAllocation}
