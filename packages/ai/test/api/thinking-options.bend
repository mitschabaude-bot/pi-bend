import Base
import ../../src/api/simple-options.bend as S
import ../../src/types.bend as Ai
import ../../src/utils/thinking-levels.bend as Levels
import ../../../runtime/src/f64.bend as F
import ../../../runtime/test/schema.bend as T

def equalOrder(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def numberEqual(+left: F.F64, +right: F.F64) -> Bool:
  equalOrder(F.compare(left, right)) || (F.isNaN(left) && F.isNaN(right))

def sameLevel(level: Maybe<&2, Ai.ThinkingLevel>, expected: String) -> Bool:
  match level:
    case None{}: False{}
    case Some{value}: String.eq(Levels.name(Ai.Thinking{value}), expected)

def allocation(actual: S.ThinkingTokenAllocation, maxTokens: F.F64, thinkingBudget: F.F64) -> Bool:
  match actual:
    case S.ThinkingTokenAllocation{m, t}: numberEqual(m, maxTokens) && numberEqual(t, thinkingBudget)

def check(base: Maybe<&2, F.F64>, +model: F.F64, +level: Ai.ThinkingLevel, +custom: Maybe<&2, Ai.ThinkingBudgets>, expectedLevel: String, budget: F.F64, room: F.F64, maxTokens: F.F64, thinkingBudget: F.F64, label: String) -> IO(Unit):
  +actualBudget = S.thinkingBudgetForLevel(level, custom)
  T.assertion(sameLevel(S.clampReasoning(Some{level}), expectedLevel) && numberEqual(actualBudget, budget) && numberEqual(S.clampThinkingBudgetToAnswerRoom(actualBudget, model), room) && allocation(S.adjustMaxTokensForThinking(base, model, level, custom), maxTokens, thinkingBudget), label)

def absentReasoning(value: Maybe<&2, Ai.ThinkingLevel>) -> Bool:
  match value:
    case None{}: True{}
    case _: False{}

def absence() -> IO(Unit):
  T.assertion(absentReasoning(S.clampReasoning(None{})), "absent reasoning remains absent")
