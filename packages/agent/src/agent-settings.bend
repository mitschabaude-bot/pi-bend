import Base
import ./types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/f64.bend as F

# Immutable public request settings; each run captures its own value.
type Settings is Data:
  Settings{sessionId: Maybe<&2, String>, thinkingBudgets: Maybe<&2, Ai.ThinkingBudgets>, transport: Ai.Transport, maxRetryDelayMs: Maybe<&2, F.F64>, toolExecution: T.ToolExecutionMode}
type Change is Data:
  SetSessionId{value: Maybe<&2, String>}
  SetThinkingBudgets{value: Maybe<&2, Ai.ThinkingBudgets>}
  SetTransport{value: Ai.Transport}
  SetMaxRetryDelayMs{value: Maybe<&2, F.F64>}
  SetToolExecution{value: T.ToolExecutionMode}

def apply(settings: Settings, change: Change) -> Settings:
  match settings change:
    case Settings{_, thinkingBudgets, transport, maxRetryDelayMs, toolExecution} SetSessionId{value}: Settings{value, thinkingBudgets, transport, maxRetryDelayMs, toolExecution}
    case Settings{sessionId, _, transport, maxRetryDelayMs, toolExecution} SetThinkingBudgets{value}: Settings{sessionId, value, transport, maxRetryDelayMs, toolExecution}
    case Settings{sessionId, thinkingBudgets, _, maxRetryDelayMs, toolExecution} SetTransport{value}: Settings{sessionId, thinkingBudgets, value, maxRetryDelayMs, toolExecution}
    case Settings{sessionId, thinkingBudgets, transport, _, toolExecution} SetMaxRetryDelayMs{value}: Settings{sessionId, thinkingBudgets, transport, value, toolExecution}
    case Settings{sessionId, thinkingBudgets, transport, maxRetryDelayMs, _} SetToolExecution{value}: Settings{sessionId, thinkingBudgets, transport, maxRetryDelayMs, value}
def getSessionId(settings: Settings) -> Maybe<&2, String>:
  match settings:
    case Settings{value, _, _, _, _}: value
def getThinkingBudgets(settings: Settings) -> Maybe<&2, Ai.ThinkingBudgets>:
  match settings:
    case Settings{_, value, _, _, _}: value
def getTransport(settings: Settings) -> Ai.Transport:
  match settings:
    case Settings{_, _, value, _, _}: value
def getMaxRetryDelayMs(settings: Settings) -> Maybe<&2, F.F64>:
  match settings:
    case Settings{_, _, _, value, _}: value
def getToolExecution(settings: Settings) -> T.ToolExecutionMode:
  match settings:
    case Settings{_, _, _, _, value}: value
