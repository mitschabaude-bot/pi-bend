import Base
import ./types.bend as T
import ../../runtime/src/ref.bend as R
import ../../ai/src/types.bend as Ai

# Internal outcome records from upstream agent-loop.ts. The result is a shared
# object: an absent hook return preserves it, while any supplied override
# object causes the source's spread expression to allocate a new result.
type ExecutedToolCallOutcome<-Details: Data> is Data:
  ExecutedToolCallOutcome{result: R.Ref<T.AgentToolResult<Details>>, isError: Bool}

type FinalizedToolCallOutcome<-Arguments: Data, -Details: Data> is Data:
  FinalizedToolCallOutcome{toolCall: T.AgentToolCall(Arguments), result: R.Ref<T.AgentToolResult<Details>>, isError: Bool}

def choose(-Value: Data, original: Value, replacement: Maybe<&2, Value>) -> Value:
  match replacement:
    case None{}: original
    case Some{value}: value

def chooseOptional(-Value: Data, original: Maybe<&2, Value>, replacement: Maybe<&2, Value>) -> Maybe<&2, Value>:
  match replacement:
    case None{}: original
    case Some{value}: Some{value}

# Details is the upstream unknown payload. Its runtime adapter supplies nullish
# classification; false, zero, empty text and empty objects must return false.
# None already represents omitted/undefined, so classification only runs for a
# supplied payload. This does not convert details to JSON or clone it.
def chooseDetails(-Details: Data, original: Details, replacement: Maybe<&2, Details>, isNullish: Details -> Bool) -> Details:
  match replacement:
    case None{}: original
    case Some{+value}: Bool.pick(Details, isNullish(value), original, value)

def mergeResult(-Details: Data, original: T.AgentToolResult<Details>, replacement: T.AfterToolCallResult<Details>, isNullish: Details -> Bool) -> T.AgentToolResult<Details> & Maybe<&2, Bool>:
  match original replacement:
    case T.AgentToolResult{content, details, usage, terminate} T.AfterToolCallResult{newContent, newDetails, newIsError, newUsage, newTerminate}:
      (T.AgentToolResult{choose(List<&2, Ai.TextImageContent>, content, newContent), chooseDetails(Details, details, newDetails, isNullish), chooseOptional(Ai.Usage, usage, newUsage), chooseOptional(Bool, terminate, newTerminate)}, newIsError)

def allocateMerged(-Details: Data, isError: Bool, merged: T.AgentToolResult<Details> & Maybe<&2, Bool>) -> IO(ExecutedToolCallOutcome<Details>):
  match merged:
    case Tuple{value, newIsError}:
      do IO<ExecutedToolCallOutcome<Details>>:
        result : R.Ref<T.AgentToolResult<Details>> <- R.new(T.AgentToolResult<Details>, value)
        return ExecutedToolCallOutcome{result, choose(Bool, isError, newIsError)}

# The merge portion of finalizeExecutedToolCall. Hook invocation, error catch,
# dynamic own-property spreading, emission and scheduling remain pending. The
# caller owns the original and any newly allocated result until aliases retire.
def applyAfterToolCallResult(-Details: Data, executed: ExecutedToolCallOutcome<Details>, replacement: Maybe<&2, T.AfterToolCallResult<Details>>, isNullish: Details -> Bool) -> IO(ExecutedToolCallOutcome<Details>):
  match executed replacement:
    case ExecutedToolCallOutcome{result, isError} None{}: IO.pure(ExecutedToolCallOutcome<Details>, ExecutedToolCallOutcome{result, isError})
    case ExecutedToolCallOutcome{result, isError} Some{patch}:
      do IO<ExecutedToolCallOutcome<Details>>:
        original : T.AgentToolResult<Details> <- R.read(T.AgentToolResult<Details>, result)
        allocateMerged(Details, isError, mergeResult(Details, original, patch, isNullish))
