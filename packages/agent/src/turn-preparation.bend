import Base
import ./types.bend as T
import ./agent-loop.bend as Loop
import ./tool-changes.bend as Changes
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C

# Ready for the provider boundary: updated context/config and committed history.
type RequestState<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  RequestState{context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>}

type DeliveryStep<-Message: Data, -Error: Data> is Data:
  Next{}
  Started{message: Message, emitted: Result<&2, &2, Error, Unit>}
  Ended{message: Message, emitted: Result<&2, &2, Error, Unit>}

# Each Next consumes a declared message. Commit only after both events settle,
# preserving source order and skipping every later event on listener failure.
@unsafe
def deliver(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, state: RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, remaining: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, +sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, step: DeliveryStep<T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, Error>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match state:
    case RequestState{context, config, newMessages}:
      match remaining step:
        case Nil{} Next{}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Done{RequestState{context, config, newMessages}})
        case +message <> rest Next{}:
          do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.MessageStart{message})
            deliver(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, RequestState{context, config, newMessages}, rest, sink, Started{message, emitted})
        case _ Started{_, Fail{error}}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
        case rest Started{+message, Done{_}}:
          do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
            emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.MessageEnd{message})
            deliver(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, RequestState{context, config, newMessages}, rest, sink, Ended{message, emitted})
        case _ Ended{_, Fail{error}}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
        case rest Ended{+message, Done{_}}:
          deliver(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, RequestState{Loop.copyContextMessages(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, message <> Nil{}), config, List.append(&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, newMessages, message <> Nil{})}, rest, sink, Next{})

def declared(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, state: RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, outcome: Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match outcome:
    case Declaration.Failure{error}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{declarationError(error)})
    case Declaration.Success{messages}: deliver(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, state, messages, sink, Next{})

def declare(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
    +current : T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> = context
    outcome : Declaration.DeclarationResult<List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- Changes.declareToolChanges(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, current, messages)
    declared(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, RequestState{current, config, newMessages}, sink, declarationError, outcome)

def started(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, messages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, emitted: Result<&2, &2, Error, Unit>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match emitted:
    case Fail{error}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
    case Done{_}: declare(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, newMessages, messages, sink, declarationError)

def queued(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, prepared: Loop.PreparedTurnState<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, +sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, pending: Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match prepared pending:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
    case Loop.PreparedTurnState{context, config, messages} Done{steering}:
      do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
        emitted : Result<&2, &2, Error, Unit> <- C.call(T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>, sink, T.TurnStart{})
        started(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, newMessages, List.append(&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>, messages, steering), sink, declarationError, emitted)

def afterPreparation(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, pending: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error, outcome: Result<&2, &2, Error, Loop.PreparedTurnState<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  match outcome:
    case Fail{error}: IO.pure(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>, Fail{error})
    case Done{Loop.PreparedTurnState{context, +config, messages}}:
      do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
        steering : Result<&2, &2, Error, List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>> <- Loop.repollSteeringMessages(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, config, pending)
        queued(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, Loop.PreparedTurnState{context, config, messages}, newMessages, sink, declarationError, steering)

# A retained steering item must not consume another one-at-a-time queue item.
# Preparation updates context/model/reasoning before any turn_start event.
def next(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, completed: T.PrepareNextTurnContext(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error), newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, pending: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  do IO<Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>>:
    outcome : Result<&2, &2, Error, Loop.PreparedTurnState<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>> <- Loop.prepareNextTurn(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, completed)
    afterPreparation(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, newMessages, pending, sink, declarationError, outcome)

# The initial turn_start belongs to runAgentLoop/runAgentLoopContinue. The first
# inner iteration declares and delivers already-polled steering without a hook
# or another turn_start event.
def initial(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, newMessages: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, pending: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>, sink: C.Callback<T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>, Result<&2, &2, Error, Unit>>, declarationError: Declaration.DeclarationError -> Error) -> IO(Result<&2, &2, Error, RequestState<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>>):
  declare(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch, context, config, newMessages, pending, sink, declarationError)
