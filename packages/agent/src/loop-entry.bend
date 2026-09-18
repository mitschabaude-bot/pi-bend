import Base
import ./types.bend as T
import ./stream-fn.bend as StreamFn
import ./main-loop.bend as Main
import ./turn-preparation.bend as Preparation
import ./tool-changes.bend as Changes
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C

type ContinueError is Data:
  NoMessages{}
  AssistantLast{}

def errorMessage(error: ContinueError) -> String:
  match error:
    case NoMessages{}: "Cannot continue: no messages in context"
    case AssistantLast{}: "Cannot continue from message role: assistant"

# Validate only the agent message role. Conversion belongs at the provider
# boundary; custom messages remain the caller's responsibility, as in pi.
def validateContinuation(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> Maybe<&2, ContinueError>:
  match messages:
    case Nil{}: Some{NoMessages{}}
    case T.LlmMessage{Ai.Assistant{_}} <> Nil{}: Some{AssistantLast{}}
    case _ <> Nil{}: None{}
    case _ <> rest: validateContinuation(Arguments, DiagnosticDetails, Details, Custom, rest)

type Capture<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Capture{services: Main.Services<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, stream: StreamFn.Selection<Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error>}

def explicit(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, capture: Main.Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>:
  match capture:
    case Main.Capture{services, stream}: Capture{services, StreamFn.Explicit{stream}}

def resolved(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, services: Main.Services<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, state: Preparation.RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, stream: Result<&2, &2, StreamFn.MissingDefault, T.StreamFn(Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error)>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match state stream:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{streamError(error)})
    case Preparation.RequestState{context, config, messages} Done{provider}: Main.runLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, Main.Capture{services, provider}, context, config, messages)

def enter(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, prepared: Result<&2, &2, Error, Preparation.RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture prepared:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
    case Capture{services, selection} Done{state}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        stream : Result<&2, &2, StreamFn.MissingDefault, T.StreamFn(Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error)> <- StreamFn.resolve(Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error, selection)
        resolved(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, services, state, stream)

def afterTurnStart(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, +capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
    case Capture{Main.Services{_, _, _, _, sink, _, _, _}, _} Done{_}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        prepared : Result<&2, &2, Error, Preparation.RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>> <- Preparation.deliver(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, Preparation.RequestState{context, config, Nil{}}, messages, sink, Preparation.Next{})
        enter(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, prepared)

def afterAgentStart(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, +capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture emitted:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{error})
    case Capture{Main.Services{_, _, _, _, sink, _, _, _}, _} Done{_}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        started : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.TurnStart{})
        afterTurnStart(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, messages, started)

def start(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, +capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match capture:
    case Capture{Main.Services{_, _, _, _, sink, _, _, _}, _}:
      do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.AgentStart{})
        afterAgentStart(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, messages, emitted)

def declared(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, messages: Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match messages:
    case Declaration.Failure{error}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{declarationError(error)})
    case Declaration.Success{initial}: start(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, initial)

# Reconcile prompt declarations before emitting the initial event prefix.
# Callback/update/batch ownership follows Main.runLoop's explicit lifetime.
def runAgentLoop(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, prompts: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, +context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  do IO<Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
    messages : Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- Changes.declareToolChanges(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, prompts)
    declared(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, messages)

def continueValidated(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, error: Maybe<&2, ContinueError>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match error:
    case Some{cause}: IO.pure(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>, Fail{entryError(cause)})
    case None{}: start(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, capture, context, config, Nil{})

def runAgentLoopContinue(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: ContinueError -> Error, +context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, capture: Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match context:
    case T.AgentContext{messages, _}: continueValidated(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, capture, context, config, validateContinuation(Arguments, DiagnosticDetails, Details, Custom, messages))
