import Base
import ../types.bend as T
import ../../../runtime/src/f64.bend as F

# Shared response-budget policy. Context estimation and buildBaseOptions are
# separate remaining pieces of this upstream module.
type ThinkingTokenAllocation is Data:
  ThinkingTokenAllocation{maxTokens: F.F64, thinkingBudget: F.F64}

def MIN_ANSWER_TOKENS() -> F.F64: F.fromU32(1024)

def DEFAULT_THINKING_BUDGETS() -> T.ThinkingBudgets:
  T.ThinkingBudgets{Some{F.fromU32(1024)}, Some{F.fromU32(2048)}, Some{F.fromU32(8192)}, Some{F.fromU32(16384)}}

def clampLevel(effort: T.ThinkingLevel) -> T.ThinkingLevel:
  match effort:
    case T.XHigh{}: T.High{}
    case T.Max{}: T.High{}
    case other: other

def clampReasoning(effort: Maybe<&2, T.ThinkingLevel>) -> Maybe<&2, T.ThinkingLevel>:
  match effort:
    case None{}: None{}
    case Some{level}: Some{clampLevel(level)}

def orDefault(value: Maybe<&2, F.F64>, fallback: U32) -> F.F64:
  match value:
    case None{}: F.fromU32(fallback)
    case Some{number}: number

def selectBudget(level: T.ThinkingLevel, budgets: T.ThinkingBudgets) -> F.F64:
  match level budgets:
    case T.Minimal{} T.ThinkingBudgets{value, _, _, _}: orDefault(value, 1024)
    case T.Low{} T.ThinkingBudgets{_, value, _, _}: orDefault(value, 2048)
    case T.Medium{} T.ThinkingBudgets{_, _, value, _}: orDefault(value, 8192)
    case _ T.ThinkingBudgets{_, _, _, value}: orDefault(value, 16384)

def thinkingBudgetForLevel(reasoningLevel: T.ThinkingLevel, customBudgets: Maybe<&2, T.ThinkingBudgets>) -> F.F64:
  match customBudgets:
    case None{}: selectBudget(reasoningLevel, DEFAULT_THINKING_BUDGETS())
    case Some{budgets}: selectBudget(reasoningLevel, budgets)

# Unordered numeric inputs propagate NaN. Equal values need no identity or
# signed-zero distinction for a token count.
def minimumOrdered(order: Maybe<&2, Cmp>, left: F.F64, right: F.F64) -> F.F64:
  match order:
    case None{}: F.nan()
    case Some{GT{}}: right
    case _: left

def minimum(+left: F.F64, +right: F.F64) -> F.F64:
  minimumOrdered(F.compare(left, right), left, right)

def maximumOrdered(order: Maybe<&2, Cmp>, left: F.F64, right: F.F64) -> F.F64:
  match order:
    case None{}: F.nan()
    case Some{LT{}}: right
    case _: left

def maximum(+left: F.F64, +right: F.F64) -> F.F64:
  maximumOrdered(F.compare(left, right), left, right)

def clampThinkingBudgetToAnswerRoom(thinkingBudget: F.F64, ceiling: F.F64) -> F.F64:
  minimum(thinkingBudget, maximum(F.fromU32(0), F.subtract(ceiling, MIN_ANSWER_TOKENS())))

def responseCeiling(baseMaxTokens: Maybe<&2, F.F64>, modelMaxTokens: F.F64, thinkingBudget: F.F64) -> F.F64:
  match baseMaxTokens:
    case None{}: modelMaxTokens
    case Some{base}: minimum(F.add(base, thinkingBudget), modelMaxTokens)

def fitBudget(order: Maybe<&2, Cmp>, +maxTokens: F.F64, thinkingBudget: F.F64) -> ThinkingTokenAllocation:
  match order:
    case Some{LT{}}: ThinkingTokenAllocation{maxTokens, clampThinkingBudgetToAnswerRoom(thinkingBudget, maxTokens)}
    case Some{EQ{}}: ThinkingTokenAllocation{maxTokens, clampThinkingBudgetToAnswerRoom(thinkingBudget, maxTokens)}
    case _: ThinkingTokenAllocation{maxTokens, thinkingBudget}

def adjustMaxTokensForThinking(baseMaxTokens: Maybe<&2, F.F64>, modelMaxTokens: F.F64, reasoningLevel: T.ThinkingLevel, customBudgets: Maybe<&2, T.ThinkingBudgets>) -> ThinkingTokenAllocation:
  +thinkingBudget = thinkingBudgetForLevel(reasoningLevel, customBudgets)
  +maxTokens = responseCeiling(baseMaxTokens, modelMaxTokens, thinkingBudget)
  fitBudget(F.compare(maxTokens, thinkingBudget), maxTokens, thinkingBudget)
