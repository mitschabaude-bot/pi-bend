import Base
import ./types.bend as T
import ./agent-loop.bend as Loop
import ./main-loop.bend as Main
import ./loop-entry.bend as Entry
import ./stream-fn.bend as StreamFn
import ./tool-call.bend as Call
import ./event-emission.bend as E
import ../../ai/src/utils/event-stream.bend as S
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C

def Messages(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data) -> Data: List<&2, T.AgentMessage<Schema.Value, Arguments, DiagnosticDetails, Details, Custom>>
def Event(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data) -> Data: T.AgentEvent<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>>
def Outcome(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data) -> Data: Result<&2, &2, Error, Messages(Arguments, DiagnosticDetails, Details, Custom)>
def Stream(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data) -> Data: S.EventStream<Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error)>

# Provider, validator, cancellation and configuration callbacks are borrowed.
# Keep them alive until disposal has drained the loop and its tool batches.
type Options<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, -Value: Data, -Telemetry: Data, -Fetch: Data> is Data:
  Options{signal: Maybe<&2, Signal>, validate: C.Callback<Loop.ToolValidationInput<Schema.Value, Arguments, Validated>, Result<&2, &2, Error, Validated>>, isAborted: C.Callback<Maybe<&2, Signal>, Bool>, emptyDetails: Details, stream: StreamFn.Selection<Schema.Value, Arguments, DiagnosticDetails, Details, Value, T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, Error>}

type Run<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data> is Data:
  Run{stream: Stream(Arguments, DiagnosticDetails, Details, Custom, Error), worker: Chan(Unit), emit: C.Callback<Event(Arguments, DiagnosticDetails, Details, Custom), E.Emission<Error>>, sink: C.Callback<Event(Arguments, DiagnosticDetails, Details, Custom), Result<&2, &2, Error, Unit>>, updates: Call.Owners(Details, Error), batches: Main.Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)}

type Start<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data> is Data:
  Prompt{messages: Messages(Arguments, DiagnosticDetails, Details, Custom)}
  Continue{}

def extract(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, unused: Unit, event: Event(Arguments, DiagnosticDetails, Details, Custom)) -> IO(Outcome(Arguments, DiagnosticDetails, Details, Custom, Error)):
  match event:
    case T.AgentEnd{messages}: IO.pure(Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), Done{messages})
    case _: IO.pure(Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), Done{Nil{}})

def createStream(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Error: Data) -> IO(Stream(Arguments, DiagnosticDetails, Details, Custom, Error)):
  do IO<Stream(Arguments, DiagnosticDetails, Details, Custom, Error)>:
    check : C.Callback<Event(Arguments, DiagnosticDetails, Details, Custom), Bool> <- C.create(~Unit, ~Event(Arguments, DiagnosticDetails, Details, Custom), ~Bool, ~(Loop.agentStreamComplete(Schema.Value, Arguments, DiagnosticDetails, Details, Custom, T.AgentToolResult<Details>, T.AgentToolResult<Details>)), Unit{})
    finish : C.Callback<Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error)> <- C.create(~Unit, ~Event(Arguments, DiagnosticDetails, Details, Custom), ~Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), ~(extract(Arguments, DiagnosticDetails, Details, Custom, Error)), Unit{})
    S.create(Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), check, finish)

def emit(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, stream: Stream(Arguments, DiagnosticDetails, Details, Custom, Error), event: Event(Arguments, DiagnosticDetails, Details, Custom)) -> IO(E.Emission<Error>):
  do IO<E.Emission<Error>>:
    S.push(Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream, event)
    return E.Ready{Done{Unit{}}}

def execute(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: Entry.ContinueError -> Error, start: Start<Arguments, DiagnosticDetails, Details, Custom>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, capture: Entry.Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Outcome(Arguments, DiagnosticDetails, Details, Custom, Error)):
  match start:
    case Prompt{messages}: Entry.runAgentLoop(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, messages, context, config, capture)
    case Continue{}: Entry.runAgentLoopContinue(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, context, config, capture)

# On success agent_end has already settled the result. On failure, end closes
# event iteration and settles a typed error without inventing an agent_end.
def work(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: Entry.ContinueError -> Error, start: Start<Arguments, DiagnosticDetails, Details, Custom>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, capture: Entry.Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, stream: Stream(Arguments, DiagnosticDetails, Details, Custom, Error)) -> IO(Unit):
  do IO<Unit>:
    outcome : Outcome(Arguments, DiagnosticDetails, Details, Custom, Error) <- execute(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, start, context, config, capture)
    S.end(Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream, Some{outcome})

def launch(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: Entry.ContinueError -> Error, start: Start<Arguments, DiagnosticDetails, Details, Custom>, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, options: Options<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>):
  match options:
    case Options{signal, validate, isAborted, emptyDetails, selection}:
      do IO<Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>:
        +stream : Stream(Arguments, DiagnosticDetails, Details, Custom, Error) <- createStream(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Error)
        +emitter : C.Callback<Event(Arguments, DiagnosticDetails, Details, Custom), E.Emission<Error>> <- C.create(~Stream(Arguments, DiagnosticDetails, Details, Custom, Error), ~Event(Arguments, DiagnosticDetails, Details, Custom), ~E.Emission<Error>, ~(emit(Arguments, DiagnosticDetails, Details, Custom, Error)), stream)
        +sink : C.Callback<Event(Arguments, DiagnosticDetails, Details, Custom), Result<&2, &2, Error, Unit>> <- Loop.createAwaitedEventSink(~Schema.Value, ~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~T.AgentToolResult<Details>, ~T.AgentToolResult<Details>, ~Error, emitter)
        +updates : Call.Owners(Details, Error) <- Call.newOwners(Details, Error)
        +batches : Main.Batches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error) <- Main.newBatches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error)
        capture : Entry.Capture<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch> = Entry.Capture{Main.Services{signal, validate, isAborted, emitter, sink, updates, batches, emptyDetails}, selection}
        worker : Chan(Unit) <- IO.fork(Unit, work(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, start, context, config, capture, stream))
        return Run{stream, worker, emitter, sink, updates, batches}

def agentLoop(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: Entry.ContinueError -> Error, prompts: Messages(Arguments, DiagnosticDetails, Details, Custom), context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, options: Options<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>):
  launch(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, Prompt{prompts}, context, config, options)

def continueValidated(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: Entry.ContinueError -> Error, context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, options: Options<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, error: Maybe<&2, Entry.ContinueError>) -> IO(Result<&2, &2, Error, Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match error:
    case Some{cause}: IO.pure(Result<&2, &2, Error, Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>, Fail{entryError(cause)})
    case None{}:
      do IO<Result<&2, &2, Error, Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>>:
        run : Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error> <- launch(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, Continue{}, context, config, options)
        return Done{run}

# Invalid continuation is rejected before allocating a stream or starting work.
def agentLoopContinue(~Arguments: Data, ~DiagnosticDetails: Data, ~Details: Data, ~Custom: Data, ~Validated: Data, ~Signal: Data, ~Error: Data, ~Value: Data, ~Telemetry: Data, ~Fetch: Data, ~renderError: Error -> String, ~declarationError: Declaration.DeclarationError -> Error, ~streamError: StreamFn.MissingDefault -> Error, ~entryError: Entry.ContinueError -> Error, +context: T.AgentContext<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, config: T.AgentLoopConfig<Schema.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>, options: Options<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, Value, Telemetry, Fetch>) -> IO(Result<&2, &2, Error, Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>>):
  match context:
    case T.AgentContext{messages, _}: continueValidated(~Arguments, ~DiagnosticDetails, ~Details, ~Custom, ~Validated, ~Signal, ~Error, ~Value, ~Telemetry, ~Fetch, ~renderError, ~declarationError, ~streamError, ~entryError, context, config, options, Entry.validateContinuation(Arguments, DiagnosticDetails, Details, Custom, messages))

def result(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Outcome(Arguments, DiagnosticDetails, Details, Custom, Error)):
  match run:
    case Run{stream, _, _, _, _, _}: S.resultValue(Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream)

def iterator(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(S.Iterator<Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error)>):
  match run:
    case Run{stream, _, _, _, _, _}: S.iterator(Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream)

# Single-owner disposal: retire iterators/result observers and retained tool
# update aliases first. Failed results may settle while sibling tools still run.
def disposeStream(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Error: Data, +stream: Stream(Arguments, DiagnosticDetails, Details, Custom, Error)) -> IO(Unit):
  match stream:
    case S.EventStream{_, _, check, finish}:
      do IO<Unit>:
        S.dispose(Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), stream)
        C.dispose(Event(Arguments, DiagnosticDetails, Details, Custom), Bool, check)
        C.dispose(Event(Arguments, DiagnosticDetails, Details, Custom), Outcome(Arguments, DiagnosticDetails, Details, Custom, Error), finish)

def dispose(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, run: Run<Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>) -> IO(Unit):
  match run:
    case Run{stream, worker, emitter, sink, updates, batches}:
      do IO<Unit>:
        joined : Unit <- IO.join(Unit, worker)
        Main.disposeBatches(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, batches)
        Call.disposeOwners(Details, Error, updates)
        C.dispose(Event(Arguments, DiagnosticDetails, Details, Custom), Result<&2, &2, Error, Unit>, sink)
        C.dispose(Event(Arguments, DiagnosticDetails, Details, Custom), E.Emission<Error>, emitter)
        disposeStream(Arguments, DiagnosticDetails, Details, Custom, Error, stream)
