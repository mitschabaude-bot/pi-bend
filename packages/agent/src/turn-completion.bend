import Base
import ./types.bend as T
import ./agent-loop.bend as Loop
import ./tool-batch.bend as Batch
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C

# Successful turn completion returns an immutable snapshot for prepareNextTurn.
# The caller has already recorded the assistant response in both histories.
type NextTurn<-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Finished{completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>}
  Continue{completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, pending: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>}

def toolMessages(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, results: List<&2, Ai.ToolResultMessage<Details>>) -> List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>:
  match results:
    case Nil{}: Nil{}
    case message <> rest: T.LlmMessage{Ai.ToolResult{message}} <> toolMessages(Parameters, Arguments, DiagnosticDetails, Details, Custom, rest)

def completedTurn(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, context: T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, newMessages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, +results: List<&2, Ai.ToolResultMessage<Details>>) -> T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>:
  match context:
    case T.AgentContext{messages, tools}:
      +added = toolMessages(Parameters, Arguments, DiagnosticDetails, Details, Custom, results)
      T.ShouldStopAfterTurnContext{assistant, results, T.AgentContext{List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>, messages, added), tools}, List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>, newMessages, added)}

def history(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>:
  match completed:
    case T.ShouldStopAfterTurnContext{_, _, _, messages}: messages

def nonempty(-A: Data, values: List<&2, A>) -> Bool:
  match values:
    case Nil{}: False{}
    case _ <> _: True{}

def ended(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, emitted: Result<&2, &2, Error, Unit>) -> Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>:
  match emitted:
    case Fail{error}: Fail{error}
    case Done{_}: Done{Finished{completed}}

def followed(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, +completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, queued: Result<&2, &2, Error, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match queued:
    case Fail{error}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case Done{Nil{}}:
      do IO<Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.AgentEnd{history(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed)})
        return ended(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed, emitted)
    case Done{head <> tail}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Continue{completed, head <> tail}})

def afterSteering(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, queued: Result<&2, &2, Error, Maybe<&2, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>>>, moreTools: Bool) -> IO(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match queued moreTools:
    case Fail{error} _: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case Done{None{}} _: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Finished{completed}})
    case Done{Some{pending}} True{}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Continue{completed, pending}})
    case Done{Some{head <> tail}} False{}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Done{Continue{completed, head <> tail}})
    case Done{Some{Nil{}}} False{}:
      do IO<Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        followUp : Result<&2, &2, Error, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>> <- Loop.pollFollowUpMessages(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config)
        followed(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed, sink, followUp)

def afterTurnEnd(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, +config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +completed: T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, +sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, moreTools: Bool, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match emitted:
    case Fail{error}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        queued : Result<&2, &2, Error, Maybe<&2, List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>>> <- Loop.finishCompletedTurn(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, T.AgentToolResult<Details>, T.AgentToolResult<Details>, config, completed, history(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, completed), sink)
        afterSteering(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config, completed, sink, queued, moreTools)

# Commit successful tool results to both histories before turn_end and the
# stop hook. Steering is checked after the stop hook; follow-ups are checked
# only when neither continuing tool calls nor steering keeps the inner loop alive.
def complete(-Parameters: Data, -Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, +assistant: Ai.AssistantMessage<Arguments, DiagnosticDetails>, newMessages: List<&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>>, config: T.AgentLoopConfig<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, +sink: C.Callback<T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, batch: Result<&2, &2, Error, Batch.Batch<T.AgentContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, Ai.ToolResultMessage<Details>>>) -> IO(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match batch:
    case Fail{error}: IO.pure(Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{error})
    case Done{Batch.Batch{context, +results, terminate}}:
      do IO<Result<&2, &2, Error, NextTurn<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        +completed : T.ShouldStopAfterTurnContext<Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> = completedTurn(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, assistant, context, newMessages, results)
        moreTools : Bool = nonempty(Ai.ToolCall<Arguments>, Loop.collectAssistantToolCalls(Arguments, DiagnosticDetails, assistant)) && Bool.not(terminate)
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Parameters, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.TurnEnd{T.LlmMessage{Ai.Assistant{assistant}}, results})
        afterTurnEnd(Parameters, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config, completed, sink, moreTools, emitted)
