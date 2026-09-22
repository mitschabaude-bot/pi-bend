import Base
import ./openai-client.bend as Client
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/sse.bend as Bytes
import ../../../runtime/src/sse.bend as Event
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/json.bend as StringJSON
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/u64.bend as Word
import ../../../runtime/src/http-response.bend as Classify
import ../../../runtime/src/http-response.bend as Source
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/http-response.bend as Progress
import ../../../runtime/src/http-response.bend as Reader
import ../../../runtime/src/http-exchange.bend as Exchange
import ../../../runtime/src/http-exchange.bend as SocketSource
import ../../../runtime/src/socket.bend as Socket
import ../../../runtime/src/socket.bend as Upload

# The streaming side of the OpenAI SDK client: `Stream.fromSSEResponse` as a
# pure dispatch policy over decoded server-sent events, an affine cursor that
# drives it with borrowed transport and diagnostic hooks, and the concrete
# HTTP-body instantiation used by the Responses provider.

# Dispatch policy
# ---------------

type State is Data:
  Receiving{}
  DoneMarker{}

type Message is Data:
  JsonMessage{data: V.Value}
  EventMessage{event: Maybe<&2, String>, data: V.Value}

type DiagnosticTarget is Data:
  ClientLogger{}
  ConsoleLogger{}

type DispatchError is Data:
  InvalidJson{cause: Json.ParseError, data: String, raw: List<&2, String>, target: DiagnosticTarget}
  ApiErrorPayload{error: V.Value}

type Step is Data:
  Skip{state: State}
  YieldMessage{message: Message}
  Reject{error: DispatchError}

def threadEvent(event: Maybe<&2, String>) -> Bool:
  match event:
    case None{}: False{}
    case Some{name}: String.starts_with(name, "thread.")

def activeNumber(value: F.Decoded) -> Bool:
  match value:
    case F.NotANumber{}: False{}
    case F.Infinity{_}: True{}
    case F.Finite{_, _, significand}: Bool.not(Word.equal(significand, Word.zero()))

# The wire protocol treats null/false/zero/empty-text error fields as absent.
# Arrays and objects, including empty containers, are error payloads.
def activeError(value: V.Value) -> Bool:
  match value:
    case V.Null{}: False{}
    case V.Boolean{value}: value
    case V.Number{value}: activeNumber(F.decode(value))
    case V.Text{text}: Bool.not(String.is_empty(text))
    case _: True{}

def errorField(data: V.Value) -> Maybe<&2, V.Value>:
  match data:
    case V.ObjectValue{fields}: Record.get(V.Value, fields, "error")
    case _: None{}

def deliverMessage(envelope: Bool, event: Maybe<&2, String>, data: V.Value) -> Step:
  match envelope:
    case True{}: YieldMessage{EventMessage{event, data}}
    case False{}: YieldMessage{JsonMessage{data}}

def errorOrMessage(active: Bool, error: V.Value, synthesize: Bool, event: Maybe<&2, String>, data: V.Value) -> Step:
  match active:
    case True{}: Reject{ApiErrorPayload{error}}
    case False{}: deliverMessage(synthesize, event, data)

def checkedError(error: Maybe<&2, V.Value>, synthesize: Bool, event: Maybe<&2, String>, data: V.Value) -> Step:
  match error:
    case None{}: deliverMessage(synthesize, event, data)
    case Some{+value}: errorOrMessage(activeError(value), value, synthesize, event, data)

def parsed(thread: Bool, synthesize: Bool, event: Maybe<&2, String>, data: String, raw: List<&2, String>, result: Result<&2, &2, Json.ParseError, V.Value>) -> Step:
  match thread result:
    case True{} Fail{cause}: Reject{InvalidJson{cause, data, raw, ConsoleLogger{}}}
    case False{} Fail{cause}: Reject{InvalidJson{cause, data, raw, ClientLogger{}}}
    case True{} Done{value}: deliverMessage(True{}, event, value)
    case False{} Done{+value}: checkedError(errorField(value), synthesize, event, value)

def parseEvent(marker: Bool, synthesize: Bool, +event: Maybe<&2, String>, +data: String, raw: List<&2, String>) -> Step:
  match marker:
    case True{}: Skip{DoneMarker{}}
    case False{}: parsed(threadEvent(event), synthesize, event, data, raw, Json.parse(data))

# Done suppresses later values and JSON errors, but the cursor must continue
# draining input. Prefix matching deliberately accepts '[DONE]suffix'.
def step(state: State, synthesize: Bool, event: Event.ServerSentEvent) -> Step:
  match state event:
    case DoneMarker{} _: Skip{DoneMarker{}}
    case Receiving{} Event.ServerSentEvent{name, +data, raw}: parseEvent(String.starts_with(data, "[DONE]"), synthesize, name, data, raw)

# Cursor
# ------

# Transport adapters classify cancellation explicitly, without string matching.
type ReadError<-E: Data> is Data:
  Failure{cause: E}
  Aborted{}

type Error<-E: Data> is Data:
  TransportFailure{cause: E}
  DispatchFailure{cause: DispatchError}
  DiagnosticFailure{cause: E}

type Hooks<-E: Data> is Data:
  Hooks{abort: C.Callback<Unit, Unit>, diagnostic: C.Callback<DispatchError, Result<&2, &2, ReadError<E>, Unit>>}

type Phase is Data:
  Fresh{}
  Active{}
  Closed{}

# One acquired stream with borrowed callbacks. Its affine successor prevents
# concurrent pulls and reuse of predecessor cursors.
type Cursor<-E: Data> is Type:
  Cursor{reader: Bytes.Cursor<ReadError<E>>, hooks: Hooks<E>, synthesize: Bool, phase: Phase}

type Next<-E: Data> is Type:
  Next{cursor: Cursor<E>, result: Result<&2, &2, Error<E>, Maybe<&2, Message>>}

type CloseResult<-E: Data> is Type:
  CloseResult{cursor: Cursor<E>, result: Result<&2, &2, Error<E>, Unit>}

type Decision<-E: Data> is Data:
  ReadMore{state: State}
  Deliver{message: Message}
  Finish{result: Result<&2, &2, Error<E>, Maybe<&2, Message>>, abort: Bool, diagnostic: Maybe<&2, DispatchError>}

type Transition<-E: Data> is Type:
  Transition{reader: Bytes.Cursor<ReadError<E>>, decision: Decision<E>}

def create(-E: Data, source: Bytes.Source<ReadError<E>>, hooks: Hooks<E>, synthesize: Bool) -> Cursor<E>:
  Cursor{Bytes.createReader(ReadError<E>, source), hooks, synthesize, Fresh{}}

def incomplete(state: State) -> Bool:
  match state:
    case Receiving{}: True{}
    case DoneMarker{}: False{}

def rejected(-E: Data, error: DispatchError) -> Decision<E>:
  match error:
    case InvalidJson{+cause, +data, +raw, +target}: Finish{Fail{DispatchFailure{InvalidJson{cause, data, raw, target}}}, True{}, Some{InvalidJson{cause, data, raw, target}}}
    case other: Finish{Fail{DispatchFailure{other}}, True{}, None{}}

def dispatched(-E: Data, step: Step) -> Decision<E>:
  match step:
    case Skip{state}: ReadMore{state}
    case YieldMessage{message}: Deliver{message}
    case Reject{error}: rejected(E, error)

def received(-E: Data, state: State, synthesize: Bool, result: Result<&2, &2, ReadError<E>, Maybe<&2, Event.ServerSentEvent>>) -> Decision<E>:
  match result:
    case Fail{Aborted{}}: Finish{Done{None{}}, incomplete(state), None{}}
    case Fail{Failure{cause}}: Finish{Fail{TransportFailure{cause}}, incomplete(state), None{}}
    case Done{None{}}: Finish{Done{None{}}, False{}, None{}}
    case Done{Some{event}}: dispatched(E, step(state, synthesize, event))

def transition(-E: Data, state: State, synthesize: Bool, next: Bytes.Next<ReadError<E>>) -> Transition<E>:
  match next:
    case Bytes.Next{reader, result}: Transition{reader, received(E, state, synthesize, result)}

def abortRequest(-E: Data, hooks: Hooks<E>, abort: Bool) -> IO(Unit):
  match hooks abort:
    case Hooks{callback, _} True{}: C.call(Unit, Unit, callback, Unit{})
    case _ False{}: IO.pure(Unit, Unit{})

def diagnose(-E: Data, hooks: Hooks<E>, error: Maybe<&2, DispatchError>) -> IO(Result<&2, &2, ReadError<E>, Unit>):
  match hooks error:
    case _ None{}: IO.pure(Result<&2, &2, ReadError<E>, Unit>, Done{Unit{}})
    case Hooks{_, callback} Some{error}: C.call(DispatchError, Result<&2, &2, ReadError<E>, Unit>, callback, error)

def diagnosed(-E: Data, original: Result<&2, &2, Error<E>, Maybe<&2, Message>>, diagnostic: Result<&2, &2, ReadError<E>, Unit>) -> Result<&2, &2, Error<E>, Maybe<&2, Message>>:
  match diagnostic:
    case Done{_}: original
    case Fail{Aborted{}}: Done{None{}}
    case Fail{Failure{cause}}: Fail{DiagnosticFailure{cause}}

# A body/diagnostic failure retains precedence over a failing source return.
def finished(-E: Data, +hooks: Hooks<E>, synthesize: Bool, result: Result<&2, &2, Error<E>, Maybe<&2, Message>>, abort: Bool, closed: Bytes.CloseResult<ReadError<E>>) -> IO(Next<E>):
  match closed:
    case Bytes.CloseResult{reader, _}:
      do IO<Next<E>>:
        abortRequest(E, hooks, abort)
        return Next{Cursor{reader, hooks, synthesize, Closed{}}, result}

# Input controls progress, including draining all input after a DONE marker.
@unsafe def drive(-E: Data, +hooks: Hooks<E>, +synthesize: Bool, step: Transition<E>) -> IO(Next<E>):
  match step:
    case Transition{reader, ReadMore{+state}}:
      do IO<Next<E>>:
        pulled : Bytes.Next<ReadError<E>> <- Bytes.nextReader(ReadError<E>, reader)
        drive(E, hooks, synthesize, transition(E, state, synthesize, pulled))
    case Transition{reader, Deliver{message}}: IO.pure(Next<E>, Next{Cursor{reader, hooks, synthesize, Active{}}, Done{Some{message}}})
    case Transition{reader, Finish{result, abort, diagnostic}}:
      do IO<Next<E>>:
        reported : Result<&2, &2, ReadError<E>, Unit> <- diagnose(E, hooks, diagnostic)
        closed : Bytes.CloseResult<ReadError<E>> <- Bytes.closeReader(ReadError<E>, reader)
        finished(E, hooks, synthesize, diagnosed(E, result, reported), abort, closed)

def next(-E: Data, cursor: Cursor<E>) -> IO(Next<E>):
  match cursor:
    case Cursor{reader, hooks, synthesize, Closed{}}: IO.pure(Next<E>, Next{Cursor{reader, hooks, synthesize, Closed{}}, Done{None{}}})
    case Cursor{reader, hooks, synthesize, _}: drive(E, hooks, synthesize, Transition{reader, ReadMore{Receiving{}}})

def closeError(-E: Data, result: Result<&2, &2, ReadError<E>, Unit>) -> Result<&2, &2, Error<E>, Unit>:
  match result:
    case Fail{Failure{cause}}: Fail{TransportFailure{cause}}
    case _: Done{Unit{}}

def closedCursor(-E: Data, +hooks: Hooks<E>, synthesize: Bool, phase: Phase, result: Bytes.CloseResult<ReadError<E>>) -> IO(CloseResult<E>):
  match phase result:
    case Active{} Bytes.CloseResult{reader, result}:
      do IO<CloseResult<E>>:
        abortRequest(E, hooks, True{})
        return CloseResult{Cursor{reader, hooks, synthesize, Closed{}}, closeError(E, result)}
    case _ Bytes.CloseResult{reader, result}: IO.pure(CloseResult<E>, CloseResult{Cursor{reader, hooks, synthesize, Closed{}}, closeError(E, result)})

# Early close of an active stream aborts the request, like iterator.return.
def close(-E: Data, cursor: Cursor<E>) -> IO(CloseResult<E>):
  match cursor:
    case Cursor{reader, hooks, synthesize, phase}:
      do IO<CloseResult<E>>:
        result : Bytes.CloseResult<ReadError<E>> <- Bytes.closeReader(ReadError<E>, reader)
        closedCursor(E, hooks, synthesize, phase, result)

# Default hooks
# -------------

def quoted(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case first <> rest: StringJSON.quote(first) <> quoted(rest)

def rawLines(lines: List<&2, String>) -> String:
  "[" ++ String.join(quoted(lines), ",") ++ "]"

# Native diagnostics render raw lines as a JSON string list, preserving their
# contents and order without reproducing a JS object inspector.
def messages(error: DispatchError) -> List<&2, String>:
  match error:
    case InvalidJson{_, data, lines, _}: ("Could not parse message into JSON: " ++ data) <> ("From chunk: " ++ rawLines(lines)) <> Nil{}
    case ApiErrorPayload{_}: Nil{}

def print(lines: List<&2, String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print_err(first)
        print(rest)

# The scoped body source closes its owned fetch scope before notifying this
# hook, so there is no controller left to cancel; the caller's own signal must
# never be aborted as a side effect of iterator closure.
def ignoreAbort(environment: Unit, unused: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def printDiagnostic(~E: Data, environment: Unit, error: DispatchError) -> IO(Result<&2, &2, ReadError<E>, Unit>):
  do IO<Result<&2, &2, ReadError<E>, Unit>>:
    print(messages(error))
    return Done{Unit{}}

# Both SDK diagnostic targets use stderr by default.
def defaultHooks(~E: Data) -> IO(Hooks<E>):
  do IO<Hooks<E>>:
    abort : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~ignoreAbort, Unit{})
    diagnostic : C.Callback<DispatchError, Result<&2, &2, ReadError<E>, Unit>> <- C.create(~Unit, ~DispatchError, ~Result<&2, &2, ReadError<E>, Unit>, ~(printDiagnostic(~E)), Unit{})
    return Hooks{abort, diagnostic}

def disposeHooks(-E: Data, hooks: Hooks<E>) -> IO(Unit):
  match hooks:
    case Hooks{abort, diagnostic}:
      do IO<Unit>:
        C.dispose(DispatchError, Result<&2, &2, ReadError<E>, Unit>, diagnostic)
        C.dispose(Unit, Unit, abort)

# HTTP body streams
# -----------------

def TransportError(-Reason: Data) -> Data: Progress.ResponseProgressError<Client.ReadError(Reason)>

def socketAbort(-Reason: Data, error: Socket.SocketErrorOfSocket<Reason>) -> Bool:
  match error:
    case Socket.SocketAborted{_}: True{}
    case Socket.SocketSocketError{_, _}: False{}

def sourceAbort(-Reason: Data, error: SocketSource.SocketSourceError<Reason>) -> Bool:
  match error:
    case SocketSource.SocketSourceSocketFailure{cause}: socketAbort(Reason, cause)
    case SocketSource.UploadFailure{Upload.WriteFailure{cause, None{}}}: socketAbort(Reason, cause)
    case _: False{}

def readerAbort(-Reason: Data, error: Reader.ReadError<SocketSource.SocketSourceError<Reason>>) -> Bool:
  match error:
    case Reader.ResponseReaderPrimaryFailure{Reader.SourceError{cause}}: sourceAbort(Reason, cause)
    case Reader.ReleaseFailure{cause}: sourceAbort(Reason, cause)
    case _: False{}

def exchangeAbort(-Reason: Data, error: Exchange.ReadError<Reason>) -> Bool:
  match error:
    case Exchange.ResponseFailure{cause}: readerAbort(Reason, cause)
    case Exchange.DisposalFailure{cause}: sourceAbort(Reason, cause)
    case Exchange.ResponseWithDisposal{_, _}: False{}

def classified(-Reason: Data, aborted: Bool, error: TransportError(Reason)) -> ReadError<TransportError(Reason)>:
  match aborted:
    case True{}: Aborted{}
    case False{}: Failure{error}

# Cancellation is recognized from the typed transport error, never its text.
def classify(-Reason: Data, error: TransportError(Reason)) -> ReadError<TransportError(Reason)>:
  match error:
    case +value: classified(Reason, Classify.standalone(Client.ReadError(Reason), exchangeAbort(Deadline.Cause<Reason>), value), value)

# One acquired response body: the source owns the body's fetch scope and
# transport; the caller drives the returned cursor and retires it before the
# source. Borrowed hooks stay with their owner.
def Body(-Reason: Data) -> Type: Source.Owner<Client.State(Reason), ReadError<TransportError(Reason)>>

type CloseError<-Reason: Data> is Data:
  CursorFailure{error: Error<TransportError(Reason)>}
  BodyFailure{error: ReadError<TransportError(Reason)>}
  BothFailures{cursor: Error<TransportError(Reason)>, body: ReadError<TransportError(Reason)>}

def acquired(-Reason: Data, hooks: Hooks<TransportError(Reason)>, synthesize: Bool, pair: Body(Reason) & Bytes.Source<ReadError<TransportError(Reason)>>) -> Body(Reason) & Cursor<TransportError(Reason)>:
  match pair:
    case (source, bytes): (source, create(TransportError(Reason), bytes, hooks, synthesize))

def fromBody(~Reason: Data, body: Response.Body<Client.State(Reason)>, hooks: Hooks<TransportError(Reason)>, synthesize: Bool) -> IO(Body(Reason) & Cursor<TransportError(Reason)>):
  do IO<Body(Reason) & Cursor<TransportError(Reason)>>:
    source : Body(Reason) <- Source.create(~(Client.ReadError(Reason)), ~(Client.State(Reason)), ~ReadError<TransportError(Reason)>, ~(classify(Reason)), ~(Client.read(Reason)), ~(Client.close(Reason)), body)
    return acquired(Reason, hooks, synthesize, Source.borrow(Client.State(Reason), ReadError<TransportError(Reason)>, source))

def outcome(-Reason: Data, cursor: Result<&2, &2, Error<TransportError(Reason)>, Unit>, body: Result<&2, &2, ReadError<TransportError(Reason)>, Unit>) -> Result<&2, &2, CloseError<Reason>, Unit>:
  match cursor body:
    case Done{_} Done{_}: Done{Unit{}}
    case Fail{error} Done{_}: Fail{CursorFailure{error}}
    case Done{_} Fail{error}: Fail{BodyFailure{error}}
    case Fail{first} Fail{second}: Fail{BothFailures{first, second}}

def disposed(-Reason: Data, source: Body(Reason), result: CloseResult<TransportError(Reason)>) -> IO(Result<&2, &2, CloseError<Reason>, Unit>):
  match result:
    case CloseResult{Cursor{_, _, _, _}, first}:
      do IO<Result<&2, &2, CloseError<Reason>, Unit>>:
        second : Result<&2, &2, ReadError<TransportError(Reason)>, Unit> <- Source.dispose(Client.State(Reason), ReadError<TransportError(Reason)>, source)
        return outcome(Reason, first, second)

# Disposal closes a still-active stream (aborting the request) and then the
# body, even when the stream was never read.
def dispose(-Reason: Data, source: Body(Reason), cursor: Cursor<TransportError(Reason)>) -> IO(Result<&2, &2, CloseError<Reason>, Unit>):
  do IO<Result<&2, &2, CloseError<Reason>, Unit>>:
    result : CloseResult<TransportError(Reason)> <- close(TransportError(Reason), cursor)
    disposed(Reason, source, result)
