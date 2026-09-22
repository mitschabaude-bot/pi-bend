import Base
import ./http-message.bend as Head
import ./callback.bend as C
import ./bounded-bytes.bend as Bytes
import ./utf8-strict.bend as UTF8
import ./json-parse.bend as JSON
import ./schema-value.bend as Value
import ./sse.bend as SSE
import ./serial-resource.bend as Serial
import ./abort.bend as Abort
import ./deadline.bend as Deadline

type ResponsePlan is Data:
  Informational{}
  Final{framing: Head.Framing, exposeBody: Bool}

type PolicyError is Data:
  UnsupportedVersion{major: U32, minor: U32}
  InvalidStatus{status: U32}
  UnexpectedContinue{}
  UnsupportedUpgrade{}
  FramingError{error: Head.FramingFieldsFieldError}

# Accepted HTTP/1 parser version labels; accepting "2.0" here does not provide
# the HTTP/2 binary protocol. Request method normalization occurs upstream.
def supportedVersion(major: U32, minor: U32) -> Bool:
  match major minor:
    case 0 9: True{}
    case 1 0: True{}
    case 1 1: True{}
    case 2 0: True{}
    case _ _: False{}

def nullBody(status: U32) -> Bool:
  match status:
    case 204: True{}
    case 205: True{}
    case 304: True{}
    case _: False{}

def wireNoBody(status: U32) -> Bool:
  match status:
    case 204: True{}
    case 304: True{}
    case _: False{}

def finalPlan(headMethod: Bool, +status: U32, fields: Head.Fields) -> ResponsePlan:
  match headMethod:
    case True{}: Final{Head.NoBody{}, False{}}
    case False{}:
      Final{Bool.pick(Head.Framing, wireNoBody(status), Head.NoBody{}, Head.bodyFraming(fields)), Bool.not(nullBody(status))}

def checkedStatus(valid: Bool, +status: U32, method: String, fields: Head.Fields) -> Result<&2, &2, PolicyError, ResponsePlan>:
  match valid status:
    case False{} _: Fail{InvalidStatus{status}}
    case True{} 100: Fail{UnexpectedContinue{}}
    case True{} 101: Fail{UnsupportedUpgrade{}}
    case True{} other:
      Done{Bool.pick(ResponsePlan, U32.is_lt(other, 200), Informational{}, finalPlan(String.eq(method, "HEAD"), other, fields))}

def analyzed(result: Result<&2, &2, Head.FramingFieldsFieldError, Head.Fields>, +status: U32, method: String) -> Result<&2, &2, PolicyError, ResponsePlan>:
  match result:
    case Fail{error}: Fail{FramingError{error}}
    case Done{fields}: checkedStatus(U32.is_ge(status, 100) && U32.is_le(status, 999), status, method, fields)

def checkedVersion(valid: Bool, major: U32, minor: U32, status: U32, fields: List<&2, Head.Header>, method: String) -> Result<&2, &2, PolicyError, ResponsePlan>:
  match valid:
    case False{}: Fail{UnsupportedVersion{major, minor}}
    case True{}: analyzed(Head.analyze(fields), status, method)

# Policy for ordinary Fetch requests, after request-method validation. Upgrade
# requests and CONNECT tunnels have separate transport contracts.
def plan(method: String, head: Head.ResponseHead) -> Result<&2, &2, PolicyError, ResponsePlan>:
  match head:
    case Head.ResponseHead{Head.StatusLine{+major, +minor, status, _}, fields}:
      checkedVersion(supportedVersion(major, minor), major, minor, status, fields, method)

# HTTP connection tokens control whether a reset may finish the parser.
# This policy never converts arbitrary transport errors or aborts into EOF.
type Connection is Data:
  Connection{close: Bool, keepAlive: Bool}

def token(value: String, state: Connection) -> Connection:
  match value state:
    case "close" Connection{_, keepAlive}: Connection{True{}, keepAlive}
    case "keep-alive" Connection{close, _}: Connection{close, True{}}
    case _ previous: previous

def tokens(values: List<&2, String>, state: Connection) -> Connection:
  match values:
    case Nil{}: state
    case value <> rest: tokens(rest, token(Head.lowercase(Head.trimHeader(value)), state))

def field(name: String, value: String, state: Connection) -> Connection:
  match name:
    case "connection": tokens(String.split(value, ','), state)
    case _: state

def fieldsResponseTermination(values: List<&2, Head.Header>, state: Connection) -> Connection:
  match values:
    case Nil{}: state
    case Head.Header{name, value} <> rest: fieldsResponseTermination(rest, field(Head.lowercase(name), value, state))

def persistent(modern: Bool, state: Connection) -> Bool:
  match state:
    case Connection{close, keepAlive}: Bool.pick(Bool, modern, Bool.not(close), keepAlive)

# EOF-delimited framing is nonpersistent even with a keep-alive field. For
# self-delimited bodies, HTTP/1.1 defaults to persistence; older versions opt in.
def allowsReset(framing: Head.Framing, head: Head.ResponseHead) -> Bool:
  match framing head:
    case Head.UntilClose{} _: True{}
    case _ Head.ResponseHead{Head.StatusLine{major, minor, _, _}, values}:
      Bool.not(persistent(U32.is_gt(major, 0) && U32.is_gt(minor, 0), fieldsResponseTermination(values, Connection{False{}, False{}})))

type Limits is Data:
  Limits{headLineBytes: Nat, headBytes: Nat, headFields: Nat, informationalHeads: Nat, body: Head.Limits}

type Context is Data:
  Context{method: String, limits: Limits, remainingInformational: Nat, resetEOF: Bool}

type Phase is Data:
  ReadingHead{reader: Head.HeadReader}
  ReadingBody{reader: Head.Reader, expose: Bool}

type Reader is Data:
  Reader{phase: Phase, context: Context}

type StreamEvent is Data:
  InformationalHead{head: Head.ResponseHead}
  FinalHead{head: Head.ResponseHead, exposeBody: Bool}
  BodyData{bytes: List<&2, U32>}
  Completed{trailers: List<&2, Head.Header>}

type ResponseStreamReadError is Data:
  HeadError{error: Head.ReadError}
  ResponseStreamPolicyError{error: PolicyError}
  BodyError{error: Head.BodyError}
  TooManyInformational{}
  IncompleteResponse{}

type ResponseStreamReadResult is Data:
  More{reader: Reader, events: List<&2, StreamEvent>}
  ResponseStreamComplete{events: List<&2, StreamEvent>, rest: List<&2, U32>}
  ResponseStreamFailed{error: ResponseStreamReadError, events: List<&2, StreamEvent>}

def headReader(limits: Limits) -> Head.HeadReader:
  match limits:
    case Limits{line, bytes, fields, _, _}: Head.newHead(line, bytes, fields)

def bodyReader(framing: Head.Framing, limits: Limits) -> Head.Reader:
  match limits:
    case Limits{_, _, _, _, body}: Head.newBody(framing, body)

def new(method: String, +limits: Limits) -> Reader:
  match limits:
    case Limits{_, _, _, info, _}: Reader{ReadingHead{headReader(limits)}, Context{method, limits, info, False{}}}

type ScanState is Data:
  Running{reader: Reader, reversed: List<&2, StreamEvent>}
  Broken{error: ResponseStreamReadError, reversed: List<&2, StreamEvent>}

def informational(head: Head.ResponseHead, context: Context, reversed: List<&2, StreamEvent>) -> ScanState:
  match context:
    case Context{_, _, Zero{}, _}: Broken{TooManyInformational{}, reversed}
    case Context{method, +limits, Succ{remaining}, _}:
      Running{Reader{ReadingHead{headReader(limits)}, Context{method, limits, remaining, False{}}}, InformationalHead{head} <> reversed}

def planned(result: Result<&2, &2, PolicyError, ResponsePlan>, +head: Head.ResponseHead, context: Context, reversed: List<&2, StreamEvent>) -> ScanState:
  match result context:
    case Fail{error} _: Broken{ResponseStreamPolicyError{error}, reversed}
    case Done{Informational{}} value: informational(head, value, reversed)
    case Done{Final{+framing, +expose}} Context{method, +limits, remaining, _}:
      Running{Reader{ReadingBody{bodyReader(framing, limits), expose}, Context{method, limits, remaining, allowsReset(framing, head)}}, FinalHead{head, expose} <> reversed}

def completedHead(+head: Head.ResponseHead, context: Context, reversed: List<&2, StreamEvent>) -> ScanState:
  match context:
    case Context{+method, limits, remaining, _}:
      planned(plan(method, head), head, Context{method, limits, remaining, False{}}, reversed)

def consumedHead(result: Head.HeadReadResult, context: Context, reversed: List<&2, StreamEvent>) -> ScanState:
  match result:
    case Head.HeadFailed{error}: Broken{HeadError{error}, reversed}
    case Head.HeadMore{reader}: Running{Reader{ReadingHead{reader}, context}, reversed}
    # This helper receives only one byte, so a completed head has no remainder.
    case Head.HeadComplete{head, _}: completedHead(head, context, reversed)

def emitted(expose: Bool, bytes: List<&2, U32>, reversed: List<&2, StreamEvent>) -> List<&2, StreamEvent>:
  match expose bytes:
    case False{} _: reversed
    case True{} Nil{}: reversed
    case True{} head <> rest: BodyData{head <> rest} <> reversed

def consumedBody(result: Head.ReadResult, +expose: Bool, context: Context, reversed: List<&2, StreamEvent>) -> ResponseStreamReadResult:
  match result:
    case Head.More{reader, bytes}: More{Reader{ReadingBody{reader, expose}, context}, List.reverse(&2, StreamEvent, emitted(expose, bytes, reversed))}
    case Head.Complete{bytes, trailers, rest}: ResponseStreamComplete{List.reverse(&2, StreamEvent, Completed{trailers} <> emitted(expose, bytes, reversed)), rest}
    case Head.Failed{error, bytes}: ResponseStreamFailed{BodyError{error}, List.reverse(&2, StreamEvent, emitted(expose, bytes, reversed))}

# Heads advance bytewise to allow informational resets. Once a body starts,
# hand the whole remaining chunk to its decoder, avoiding per-byte data events.
def collect(bytes: List<&2, U32>, state: ScanState) -> ResponseStreamReadResult:
  match bytes state:
    case _ Broken{error, reversed}: ResponseStreamFailed{error, List.reverse(&2, StreamEvent, reversed)}
    case input Running{Reader{ReadingBody{reader, expose}, context}, reversed}: consumedBody(Head.read(reader, input), expose, context, reversed)
    case Nil{} Running{reader, reversed}: More{reader, List.reverse(&2, StreamEvent, reversed)}
    case byte <> rest Running{Reader{ReadingHead{reader}, context}, reversed}:
      collect(rest, consumedHead(Head.readHead(reader, byte <> Nil{}), context, reversed))

def readResponseStream(reader: Reader, bytes: List<&2, U32>) -> ResponseStreamReadResult:
  collect(bytes, Running{reader, Nil{}})

def bodyEOF(result: Result<&2, &2, Head.BodyError, Unit>) -> ResponseStreamReadResult:
  match result:
    case Done{_}: ResponseStreamComplete{Completed{Nil{}} <> Nil{}, Nil{}}
    case Fail{error}: ResponseStreamFailed{BodyError{error}, Nil{}}

# Finish on clean EOF or a reset admitted by the retained HTTP framing policy.
# Abort and unrelated transport errors must remain failures.
def finish(reader: Reader) -> ResponseStreamReadResult:
  match reader:
    case Reader{ReadingHead{_}, _}: ResponseStreamFailed{IncompleteResponse{}, Nil{}}
    case Reader{ReadingBody{body, _}, _}: bodyEOF(Head.finish(body))

# Computed once when the final head is parsed, not by rescanning headers for
# each body chunk. Before a final response head, reset cannot finish a message.
def permitsResetEOF(reader: Reader) -> Bool:
  match reader:
    case Reader{_, Context{_, _, _, allowed}}: allowed

# Borrowed, reusable transport operations. Each invocation obtains a fresh
# affine closure; the caller retains ownership of both callback factories.
def Read(-E: Data, -State: Type) -> Data:
  C.Callback<State, State & Result<&2, &2, E, Maybe<&2, StreamEvent>>>

def Close(-E: Data, -State: Type) -> Data:
  C.Callback<State, Result<&2, &2, E, Unit>>

def readTransportCallbacks(-E: Data, -State: Type, callback: Read(E, State), state: State) -> IO(State & Result<&2, &2, E, Maybe<&2, StreamEvent>>):
  C.call(State, State & Result<&2, &2, E, Maybe<&2, StreamEvent>>, callback, state)

def closeTransportCallbacks(-E: Data, -State: Type, callback: Close(E, State), state: State) -> IO(Result<&2, &2, E, Unit>):
  C.call(State, Result<&2, &2, E, Unit>, callback, state)

# Static-operation convenience: factories live for this entire IO operation,
# including recursive reads, and retire before its result is returned. The
# action borrows the handles; it must not return them or spawn escaping calls.
def with(~E: Data, ~State: Type, ~Output: Type, ~readTransportCallbacks: State -> IO(State & Result<&2, &2, E, Maybe<&2, StreamEvent>>), ~closeTransportCallbacks: State -> IO(Result<&2, &2, E, Unit>), action: Read(E, State) -> Close(E, State) -> IO(Output)) -> IO(Output):
  do IO<Output>:
    +reader : Read(E, State) <- C.create(~Unit, ~State, ~(State & Result<&2, &2, E, Maybe<&2, StreamEvent>>), ~(unused => state => readTransportCallbacks(state)), Unit{})
    +closer : Close(E, State) <- C.create(~Unit, ~State, ~Result<&2, &2, E, Unit>, ~(unused => state => closeTransportCallbacks(state)), Unit{})
    result : Output <- action(reader, closer)
    C.dispose(State, State & Result<&2, &2, E, Maybe<&2, StreamEvent>>, reader)
    C.dispose(State, Result<&2, &2, E, Unit>, closer)
    return result

type Metadata is Data:
  Metadata{head: Head.ResponseHead, fields: Head.Headers, exposeBody: Bool}

# Received fields are already validated. Preserve their bytes/append order;
# caller-input normalization must not trim a received value a second time.
def appendFields(fields: List<&2, Head.Header>, initial: Head.Headers) -> Head.Headers:
  match fields:
    case Nil{}: initial
    case first <> rest: appendFields(rest, Head.appendField(initial, first))

def fromHead(head: Head.ResponseHead, exposeBody: Bool) -> Metadata:
  match head:
    case Head.ResponseHead{line, +fields}: Metadata{Head.ResponseHead{line, fields}, appendFields(fields, Head.new()), exposeBody}

def original(value: Metadata) -> Head.ResponseHead:
  match value:
    case Metadata{head, _, _}: head

def headers(value: Metadata) -> Head.Headers:
  match value:
    case Metadata{_, fields, _}: fields

def bodyPresent(value: Metadata) -> Bool:
  match value:
    case Metadata{_, _, expose}: expose

def statusResponseMetadata(value: Metadata) -> U32:
  match value:
    case Metadata{Head.ResponseHead{Head.StatusLine{_, _, code, _}, _}, _, _}: code

def statusText(value: Metadata) -> String:
  match value:
    case Metadata{Head.ResponseHead{line, _}, _, _}: Head.statusText(line)

def successful(+code: U32) -> Bool:
  U32.is_ge(code, 200) && U32.is_lt(code, 300)

def ok(value: Metadata) -> Bool:
  successful(statusResponseMetadata(value))

type ResponseProgressPrimaryError<-E: Data> is Data:
  TransportFailure{error: E}
  MissingHead{}
  MissingCompletion{}
  UnexpectedEvent{event: StreamEvent}

type ResponseProgressError<-E: Data> is Data:
  ResponseProgressPrimaryFailure{error: ResponseProgressPrimaryError<E>}
  ResponseProgressCleanupFailure{error: E}
  ResponseProgressFailureWithCleanup{primary: ResponseProgressPrimaryError<E>, cleanup: E}

type HeadDecision<-E: Data> is Data:
  SeekHead{}
  Ready{metadata: Metadata}
  HeadFailure{error: ResponseProgressPrimaryError<E>}

type BodyDecision<-E: Data> is Data:
  ReadMore{}
  Chunk{bytes: List<&2, U32>}
  Complete{trailers: List<&2, Head.Header>}
  ResponseProgressBodyFailure{error: ResponseProgressPrimaryError<E>}

def headResponseProgress(-E: Data, result: Result<&2, &2, E, Maybe<&2, StreamEvent>>) -> HeadDecision<E>:
  match result:
    case Fail{error}: HeadFailure{TransportFailure{error}}
    case Done{None{}}: HeadFailure{MissingHead{}}
    case Done{Some{InformationalHead{_}}}: SeekHead{}
    case Done{Some{FinalHead{value, expose}}}: Ready{fromHead(value, expose)}
    case Done{Some{event}}: HeadFailure{UnexpectedEvent{event}}

def bodyResponseProgress(-E: Data, expose: Bool, result: Result<&2, &2, E, Maybe<&2, StreamEvent>>) -> BodyDecision<E>:
  match expose result:
    case _ Fail{error}: ResponseProgressBodyFailure{TransportFailure{error}}
    case _ Done{None{}}: ResponseProgressBodyFailure{MissingCompletion{}}
    case True{} Done{Some{BodyData{first <> rest}}}: Chunk{first <> rest}
    case _ Done{Some{BodyData{_}}}: ReadMore{}
    case _ Done{Some{Completed{fields}}}: Complete{fields}
    case _ Done{Some{event}}: ResponseProgressBodyFailure{UnexpectedEvent{event}}

# Cleanup always runs, and cannot overwrite the original read/protocol error.
def outcomeResponseProgress(-E: Data, primary: Maybe<&2, ResponseProgressPrimaryError<E>>, cleanup: Result<&2, &2, E, Unit>) -> Result<&2, &2, ResponseProgressError<E>, Unit>:
  match primary cleanup:
    case None{} Done{_}: Done{Unit{}}
    case Some{error} Done{_}: Fail{ResponseProgressPrimaryFailure{error}}
    case None{} Fail{error}: Fail{ResponseProgressCleanupFailure{error}}
    case Some{error} Fail{cleanup}: Fail{ResponseProgressFailureWithCleanup{error, cleanup}}

# State is the affine transport owner. Read returns its successor on every
# path; close relinquishes it even when reporting a cleanup error. Borrowed
# callback handles permit repeated invocation without copying affine closures.
type Body<-State: Type> is Type:
  Open{state: State, expose: Bool}
  Closed{trailers: Maybe<&2, List<&2, Head.Header>>}

type Response<-State: Type> is Type:
  Response{metadata: Metadata, body: Body<State>}

type Next<-E: Data, -State: Type> is Type:
  Next{body: Body<State>, result: Result<&2, &2, ResponseProgressError<E>, Maybe<&2, List<&2, U32>>>}

def failedStart(-E: Data, -State: Type, primary: ResponseProgressPrimaryError<E>, cleanup: Result<&2, &2, E, Unit>) -> Result<&2, &1, ResponseProgressError<E>, Response<State>>:
  match cleanup:
    case Done{_}: Fail{ResponseProgressPrimaryFailure{primary}}
    case Fail{error}: Fail{ResponseProgressFailureWithCleanup{primary, error}}

def headRead(-E: Data, -State: Type, pair: State & Result<&2, &2, E, Maybe<&2, StreamEvent>>) -> State & HeadDecision<E>:
  match pair:
    case (state, result): (state, headResponseProgress(E, result))

def bodyRead(-E: Data, -State: Type, expose: Bool, pair: State & Result<&2, &2, E, Maybe<&2, StreamEvent>>) -> State & BodyDecision<E>:
  match pair:
    case (state, result): (state, bodyResponseProgress(E, expose, result))

# An effectful source controls progress. The HTTP parser bounds informational
# heads; this generic adapter does not impose a second, unrelated budget.
@unsafe def seek(-E: Data, -State: Type, +read: Read(E, State), +close: Close(E, State), pair: State & HeadDecision<E>) -> IO(Result<&2, &1, ResponseProgressError<E>, Response<State>>):
  match pair:
    case (state, Ready{+metadata}): IO.pure(Result<&2, &1, ResponseProgressError<E>, Response<State>>, Done{Response{metadata, Open{state, bodyPresent(metadata)}}})
    case (state, HeadFailure{error}):
      do IO<Result<&2, &1, ResponseProgressError<E>, Response<State>>>:
        cleanup : Result<&2, &2, E, Unit> <- closeTransportCallbacks(E, State, close, state)
        return failedStart(E, State, error, cleanup)
    case (state, SeekHead{}):
      do IO<Result<&2, &1, ResponseProgressError<E>, Response<State>>>:
        pair : State & Result<&2, &2, E, Maybe<&2, StreamEvent>> <- readTransportCallbacks(E, State, read, state)
        seek(E, State, read, close, headRead(E, State, pair))

def start(-E: Data, -State: Type, read: Read(E, State), close: Close(E, State), state: State) -> IO(Result<&2, &1, ResponseProgressError<E>, Response<State>>):
  seek(E, State, read, close, (state, SeekHead{}))

def finished(-E: Data, -State: Type, trailers: Maybe<&2, List<&2, Head.Header>>, result: Result<&2, &2, ResponseProgressError<E>, Unit>) -> Next<E, State>:
  match result:
    case Done{_}: Next{Closed{trailers}, Done{None{}}}
    case Fail{error}: Next{Closed{trailers}, Fail{error}}

# Completion still closes the transport owner: a parser may have released the
# socket while buffered events and callback factories remain to be retired.
@unsafe def drive(-E: Data, -State: Type, +read: Read(E, State), +close: Close(E, State), +expose: Bool, pair: State & BodyDecision<E>) -> IO(Next<E, State>):
  match pair:
    case (state, Chunk{bytes}): IO.pure(Next<E, State>, Next{Open{state, expose}, Done{Some{bytes}}})
    case (state, Complete{fields}):
      do IO<Next<E, State>>:
        cleanup : Result<&2, &2, E, Unit> <- closeTransportCallbacks(E, State, close, state)
        return finished(E, State, Some{fields}, outcomeResponseProgress(E, None{}, cleanup))
    case (state, ResponseProgressBodyFailure{error}):
      do IO<Next<E, State>>:
        cleanup : Result<&2, &2, E, Unit> <- closeTransportCallbacks(E, State, close, state)
        return finished(E, State, None{}, outcomeResponseProgress(E, Some{error}, cleanup))
    case (state, ReadMore{}):
      do IO<Next<E, State>>:
        pair : State & Result<&2, &2, E, Maybe<&2, StreamEvent>> <- readTransportCallbacks(E, State, read, state)
        drive(E, State, read, close, expose, bodyRead(E, State, expose, pair))

def nextResponse(-E: Data, -State: Type, read: Read(E, State), close: Close(E, State), body: Body<State>) -> IO(Next<E, State>):
  match body:
    case Closed{fields}: IO.pure(Next<E, State>, Next{Closed{fields}, Done{None{}}})
    case Open{state, expose}: drive(E, State, read, close, expose, (state, ReadMore{}))

# Early close returns a closed successor and reports cleanup failure once.
def closeWith(-E: Data, -State: Type, close: State -> IO(Result<&2, &2, E, Unit>), body: Body<State>) -> IO(Next<E, State>):
  match body:
    case Closed{fields}: IO.pure(Next<E, State>, Next{Closed{fields}, Done{None{}}})
    case Open{state, _}:
      do IO<Next<E, State>>:
        cleanup : Result<&2, &2, E, Unit> <- close(state)
        return finished(E, State, None{}, outcomeResponseProgress(E, None{}, cleanup))

# Compile-time operations are lifted into owned factories for this call.
def startWith(~E: Data, ~State: Type, ~read: State -> IO(State & Result<&2, &2, E, Maybe<&2, StreamEvent>>), ~close: State -> IO(Result<&2, &2, E, Unit>), state: State) -> IO(Result<&2, &1, ResponseProgressError<E>, Response<State>>):
  with(~E, ~State, ~Result<&2, &1, ResponseProgressError<E>, Response<State>>, ~read, ~close, reader => closer => start(E, State, reader, closer, state))

def nextWith(~E: Data, ~State: Type, ~read: State -> IO(State & Result<&2, &2, E, Maybe<&2, StreamEvent>>), ~close: State -> IO(Result<&2, &2, E, Unit>), body: Body<State>) -> IO(Next<E, State>):
  with(~E, ~State, ~Next<E, State>, ~read, ~close, reader => closer => nextResponse(E, State, reader, closer, body))

# An acquired byte-source lease. The cursor owns its release obligation, while
# callback handles remain borrowed from their external owner. The source owner
# must grant this lease to only one cursor, and keep its callbacks alive until
# the cursor has closedResponseReader. This interface does not itself interrupt blocked reads.
type ReleaseReason is Data:
  MessageComplete{rest: List<&2, U32>}
  CleanEOF{}
  ResetEOF{}
  DecodeFailure{}
  ResponseReaderReadFailure{}
  EarlyClose{}

type Release is Data:
  Release{reason: ReleaseReason, head: Maybe<&2, Head.ResponseHead>}

# A reset remains distinct from EOF and ordinary failure until HTTP framing
# decides whether it can terminate this response. Preserve its original error.
type ReadResult<-E: Data> is Data:
  Bytes{bytes: List<&2, U32>}
  End{}
  Failed{error: E}
  Reset{error: E}

type Source<-E: Data> is Data:
  Source{nextResponseReader: C.Callback<Unit, Result<&2, &2, E, Maybe<&2, List<&2, U32>>>>, release: C.Callback<Release, Result<&2, &2, E, Unit>>}
  TransportSource{nextResponseReader: C.Callback<Unit, ReadResult<E>>, release: C.Callback<Release, Result<&2, &2, E, Unit>>}

type ResponseReaderPrimaryError<-E: Data> is Data:
  SourceError{error: E}
  DecodeError{error: ResponseStreamReadError}

type ReadError<-E: Data> is Data:
  ResponseReaderPrimaryFailure{error: ResponseReaderPrimaryError<E>}
  ReleaseFailure{error: E}
  FailureWithRelease{primary: ResponseReaderPrimaryError<E>, release: E}

type Position<-E: Data> is Data:
  Live{reader: Reader, pending: List<&2, StreamEvent>, head: Maybe<&2, Head.ResponseHead>}
  Drained{pending: List<&2, StreamEvent>, outcomeResponseReader: Result<&2, &2, ReadError<E>, Unit>}
  ResponseReaderClosed{}

type Cursor<-E: Data> is Type:
  Cursor{source: Source<E>, position: Position<E>}

type ResponseReaderNext<-E: Data> is Type:
  ResponseReaderNext{cursor: Cursor<E>, result: Result<&2, &2, ReadError<E>, Maybe<&2, StreamEvent>>}

type CloseResult<-E: Data> is Type:
  CloseResult{cursor: Cursor<E>, result: Result<&2, &2, ReadError<E>, Unit>}

type ResponseReaderDecision<-E: Data> is Data:
  Available{position: Position<E>, result: Result<&2, &2, ReadError<E>, Maybe<&2, StreamEvent>>}
  Pull{reader: Reader, head: Maybe<&2, Head.ResponseHead>}
  ReleaseSource{request: Release, pending: List<&2, StreamEvent>, primary: Maybe<&2, ResponseReaderPrimaryError<E>>}

def createResponseReader(-E: Data, source: Source<E>, method: String, limits: Limits) -> Cursor<E>:
  Cursor{source, Live{new(method, limits), Nil{}, None{}}}

def ended(-E: Data, outcomeResponseReader: Result<&2, &2, ReadError<E>, Unit>) -> ResponseReaderDecision<E>:
  match outcomeResponseReader:
    case Done{_}: Available{ResponseReaderClosed{}, Done{None{}}}
    case Fail{error}: Available{ResponseReaderClosed{}, Fail{error}}

def decide(-E: Data, position: Position<E>) -> ResponseReaderDecision<E>:
  match position:
    case Live{reader, Nil{}, head}: Pull{reader, head}
    case Live{reader, first <> rest, head}: Available{Live{reader, rest, head}, Done{Some{first}}}
    case Drained{Nil{}, outcomeResponseReader}: ended(E, outcomeResponseReader)
    case Drained{first <> rest, outcomeResponseReader}: Available{Drained{rest, outcomeResponseReader}, Done{Some{first}}}
    case ResponseReaderClosed{}: Available{ResponseReaderClosed{}, Done{None{}}}

def finalHead(events: List<&2, StreamEvent>, previous: Maybe<&2, Head.ResponseHead>) -> Maybe<&2, Head.ResponseHead>:
  match events:
    case Nil{}: previous
    case FinalHead{head, _} <> rest: finalHead(rest, Some{head})
    case _ <> rest: finalHead(rest, previous)

def withoutCompletion(events: List<&2, StreamEvent>) -> List<&2, StreamEvent>:
  match events:
    case Nil{}: Nil{}
    case Completed{_} <> rest: withoutCompletion(rest)
    case head <> rest: head <> withoutCompletion(rest)

def completionReason(ending: Maybe<&2, ReleaseReason>, rest: List<&2, U32>) -> ReleaseReason:
  match ending:
    case Some{reason}: reason
    case None{}: MessageComplete{rest}

def decoded(-E: Data, result: ResponseStreamReadResult, previous: Maybe<&2, Head.ResponseHead>, ending: Maybe<&2, ReleaseReason>) -> ResponseReaderDecision<E>:
  match result:
    case More{reader, +events}: decide(E, Live{reader, events, finalHead(events, previous)})
    case ResponseStreamComplete{+events, rest}: ReleaseSource{Release{completionReason(ending, rest), finalHead(events, previous)}, events, None{}}
    case ResponseStreamFailed{error, +events}: ReleaseSource{Release{DecodeFailure{}, finalHead(events, previous)}, events, Some{DecodeError{error}}}

def reset(-E: Data, allowed: Bool, reader: Reader, head: Maybe<&2, Head.ResponseHead>, error: E) -> ResponseReaderDecision<E>:
  match allowed:
    case True{}: decoded(E, finish(reader), head, Some{ResetEOF{}})
    case False{}: ReleaseSource{Release{ResponseReaderReadFailure{}, head}, Nil{}, Some{SourceError{error}}}

def received(-E: Data, +reader: Reader, head: Maybe<&2, Head.ResponseHead>, result: ReadResult<E>) -> ResponseReaderDecision<E>:
  match result:
    case Failed{error}: ReleaseSource{Release{ResponseReaderReadFailure{}, head}, Nil{}, Some{SourceError{error}}}
    case Reset{error}: reset(E, permitsResetEOF(reader), reader, head, error)
    case End{}: decoded(E, finish(reader), head, Some{CleanEOF{}})
    case Bytes{bytes}: decoded(E, readResponseStream(reader, bytes), head, None{})

def outcomeResponseReader(-E: Data, primary: Maybe<&2, ResponseReaderPrimaryError<E>>, released: Result<&2, &2, E, Unit>) -> Result<&2, &2, ReadError<E>, Unit>:
  match primary released:
    case None{} Done{_}: Done{Unit{}}
    case None{} Fail{error}: Fail{ReleaseFailure{error}}
    case Some{error} Done{_}: Fail{ResponseReaderPrimaryFailure{error}}
    case Some{primary} Fail{error}: Fail{FailureWithRelease{primary, error}}

def settledResponseReader(-E: Data, pending: List<&2, StreamEvent>, result: Result<&2, &2, ReadError<E>, Unit>) -> ResponseReaderDecision<E>:
  match result:
    case Done{_}: decide(E, Drained{pending, Done{Unit{}}})
    case Fail{error}: decide(E, Drained{withoutCompletion(pending), Fail{error}})

def fromResult(-E: Data, result: Result<&2, &2, E, Maybe<&2, List<&2, U32>>>) -> ReadResult<E>:
  match result:
    case Fail{error}: Failed{error}
    case Done{None{}}: End{}
    case Done{Some{bytes}}: Bytes{bytes}

def readSource(-E: Data, source: Source<E>) -> IO(ReadResult<E>):
  match source:
    case Source{nextResponseReader, _}:
      do IO<ReadResult<E>>:
        result : Result<&2, &2, E, Maybe<&2, List<&2, U32>>> <- C.call(Unit, Result<&2, &2, E, Maybe<&2, List<&2, U32>>>, nextResponseReader, Unit{})
        return fromResult(E, result)
    case TransportSource{nextResponseReader, _}: C.call(Unit, ReadResult<E>, nextResponseReader, Unit{})

def releaseSource(-E: Data, source: Source<E>, request: Release) -> IO(Result<&2, &2, E, Unit>):
  match source:
    case Source{_, release}: C.call(Release, Result<&2, &2, E, Unit>, release, request)
    case TransportSource{_, release}: C.call(Release, Result<&2, &2, E, Unit>, release, request)

# The source controls progress; an empty byte chunk may require another read.
@unsafe def driveResponseReader(-E: Data, +source: Source<E>, decision: ResponseReaderDecision<E>) -> IO(ResponseReaderNext<E>):
  match decision:
    case Available{position, result}: IO.pure(ResponseReaderNext<E>, ResponseReaderNext{Cursor{source, position}, result})
    case Pull{reader, head}:
      do IO<ResponseReaderNext<E>>:
        result : ReadResult<E> <- readSource(E, source)
        driveResponseReader(E, source, received(E, reader, head, result))
    case ReleaseSource{request, pending, primary}:
      do IO<ResponseReaderNext<E>>:
        result : Result<&2, &2, E, Unit> <- releaseSource(E, source, request)
        driveResponseReader(E, source, settledResponseReader(E, pending, outcomeResponseReader(E, primary, result)))

def nextResponseReader(-E: Data, cursor: Cursor<E>) -> IO(ResponseReaderNext<E>):
  match cursor:
    case Cursor{source, position}: driveResponseReader(E, source, decide(E, position))

def closedResponseReader(-E: Data, source: Source<E>, result: Result<&2, &2, E, Unit>) -> CloseResult<E>:
  CloseResult{Cursor{source, ResponseReaderClosed{}}, outcomeResponseReader(E, None{}, result)}

# Release callbacks must relinquish the lease even when they report an error.
# A failed release is not retried against a potentially retired/reused resource.
def closeResponseReader(-E: Data, cursor: Cursor<E>) -> IO(CloseResult<E>):
  match cursor:
    case Cursor{+source, Live{_, _, head}}:
      do IO<CloseResult<E>>:
        result : Result<&2, &2, E, Unit> <- releaseSource(E, source, Release{EarlyClose{}, head})
        return closedResponseReader(E, source, result)
    case Cursor{source, Drained{_, result}}: IO.pure(CloseResult<E>, CloseResult{Cursor{source, ResponseReaderClosed{}}, result})
    case Cursor{source, ResponseReaderClosed{}}: IO.pure(CloseResult<E>, CloseResult{Cursor{source, ResponseReaderClosed{}}, Done{Unit{}}})

# A lone transport failure may represent cancellation. Protocol failures and
# compound failures must not be hidden merely because one cause is an abort.
def primaryAbortClassification(-E: Data, classify: E -> Bool, error: ResponseProgressPrimaryError<E>) -> Bool:
  match error:
    case TransportFailure{cause}: classify(cause)
    case _: False{}

def standalone(-E: Data, classify: E -> Bool, error: ResponseProgressError<E>) -> Bool:
  match error:
    case ResponseProgressPrimaryFailure{cause}: primaryAbortClassification(E, classify, cause)
    case ResponseProgressCleanupFailure{cause}: classify(cause)
    case ResponseProgressFailureWithCleanup{_, _}: False{}

# A limit applies to decoded HTTP body bytes, not headers/chunk delimiters.
# It is supplied by the caller; overflow never becomes successful truncation.
type PrimaryError<-E: Data> is Data:
  ReadFailure{error: ResponseProgressError<E>}
  ByteLimitExceeded{}

type Error<-E: Data> is Data:
  PrimaryFailure{error: PrimaryError<E>}
  CleanupFailure{error: ResponseProgressError<E>}
  FailureWithCleanup{primary: PrimaryError<E>, cleanup: ResponseProgressError<E>}

type Decision<-E: Data> is Data:
  Continue{buffer: Bytes.State}
  Finished{result: Result<&2, &2, PrimaryError<E>, List<&2, U32>>}

def buffered(-E: Data, buffer: Bytes.State) -> Decision<E>:
  match buffer:
    case Bytes.State{_, _, True{}}: Finished{Fail{ByteLimitExceeded{}}}
    case other: Continue{other}

def completed(-E: Data, result: Result<&2, &2, Bytes.Error, List<&2, U32>>) -> Decision<E>:
  match result:
    case Fail{_}: Finished{Fail{ByteLimitExceeded{}}}
    case Done{bytes}: Finished{Done{bytes}}

def nextBodyBuffer(-E: Data, buffer: Bytes.State, result: Result<&2, &2, ResponseProgressError<E>, Maybe<&2, List<&2, U32>>>) -> Decision<E>:
  match result:
    case Fail{error}: Finished{Fail{ReadFailure{error}}}
    case Done{None{}}: completed(E, Bytes.finish(buffer))
    case Done{Some{bytes}}: buffered(E, Bytes.consumed(bytes, buffer))

# Preserve both causes if early close itself fails. Normal EOF/read failure
# already closes the response body; its second close is an idempotent no-op.
def outcome(-E: Data, result: Result<&2, &2, PrimaryError<E>, List<&2, U32>>, cleanup: Result<&2, &2, ResponseProgressError<E>, Unit>) -> Result<&2, &2, Error<E>, List<&2, U32>>:
  match result cleanup:
    case Done{bytes} Done{_}: Done{bytes}
    case Fail{error} Done{_}: Fail{PrimaryFailure{error}}
    case Done{_} Fail{error}: Fail{CleanupFailure{error}}
    case Fail{primary} Fail{cleanup}: Fail{FailureWithCleanup{primary, cleanup}}

def advance(-E: Data, -State: Type, buffer: Bytes.State, next: Next<E, State>) -> Body<State> & Decision<E>:
  match next:
    case Next{body, result}: (body, nextBodyBuffer(E, buffer, result))

def released(-E: Data, -State: Type, result: Result<&2, &2, PrimaryError<E>, List<&2, U32>>, next: Next<E, State>) -> Result<&2, &2, Error<E>, List<&2, U32>>:
  match next:
    case Next{_, Done{_}}: outcome(E, result, Done{Unit{}})
    case Next{_, Fail{error}}: outcome(E, result, Fail{error})

# The external transport determines termination. The explicit byte budget
# bounds retained payload; empty reads do not consume an invented fuel budget.
@unsafe def driveBodyConsume(-E: Data, -State: Type, +read: Read(E, State), +close: Close(E, State), state: Body<State> & Decision<E>) -> IO(Result<&2, &2, Error<E>, List<&2, U32>>):
  match state:
    case (body, Finished{result}):
      do IO<Result<&2, &2, Error<E>, List<&2, U32>>>:
        next : Next<E, State> <- closeWith(E, State, state => closeTransportCallbacks(E, State, close, state), body)
        return released(E, State, result, next)
    case (body, Continue{buffer}):
      do IO<Result<&2, &2, Error<E>, List<&2, U32>>>:
        next : Next<E, State> <- nextResponse(E, State, read, close, body)
        driveBodyConsume(E, State, read, close, advance(E, State, buffer, next))

def bytesUsing(-E: Data, -State: Type, read: Read(E, State), close: Close(E, State), limit: Nat, body: Body<State>) -> IO(Result<&2, &2, Error<E>, List<&2, U32>>):
  driveBodyConsume(E, State, read, close, (body, Continue{Bytes.create(limit)}))

type TextError<-E: Data> is Data:
  BodyFailure{error: Error<E>}
  InvalidUTF8{error: UTF8.Error}

def textResult(-E: Data, value: Result<&2, &2, UTF8.Error, String>) -> Result<&2, &2, TextError<E>, String>:
  match value:
    case Fail{error}: Fail{InvalidUTF8{error}}
    case Done{text}: Done{text}

def decodeText(-E: Data, value: Result<&2, &2, Error<E>, List<&2, U32>>) -> Result<&2, &2, TextError<E>, String>:
  match value:
    case Fail{error}: Fail{BodyFailure{error}}
    case Done{bytes}: textResult(E, UTF8.decode(bytes))

def textUsing(-E: Data, -State: Type, read: Read(E, State), close: Close(E, State), limit: Nat, body: Body<State>) -> IO(Result<&2, &2, TextError<E>, String>):
  do IO<Result<&2, &2, TextError<E>, String>>:
    bytes : Result<&2, &2, Error<E>, List<&2, U32>> <- bytesUsing(E, State, read, close, limit, body)
    return decodeText(E, bytes)

type JSONError<-E: Data> is Data:
  TextFailure{error: TextError<E>}
  InvalidJSON{error: JSON.Error}

def jsonResult(-E: Data, value: Result<&2, &2, JSON.Error, Value.Value>) -> Result<&2, &2, JSONError<E>, Value.Value>:
  match value:
    case Fail{error}: Fail{InvalidJSON{error}}
    case Done{json}: Done{json}

def decodeJSON(-E: Data, value: Result<&2, &2, TextError<E>, String>) -> Result<&2, &2, JSONError<E>, Value.Value>:
  match value:
    case Fail{error}: Fail{TextFailure{error}}
    case Done{text}: jsonResult(E, JSON.parse(text))

def jsonUsing(-E: Data, -State: Type, read: Read(E, State), close: Close(E, State), limit: Nat, body: Body<State>) -> IO(Result<&2, &2, JSONError<E>, Value.Value>):
  do IO<Result<&2, &2, JSONError<E>, Value.Value>>:
    text : Result<&2, &2, TextError<E>, String> <- textUsing(E, State, read, close, limit, body)
    return decodeJSON(E, text)

def bytesWith(~E: Data, ~State: Type, ~read: State -> IO(State & Result<&2, &2, E, Maybe<&2, StreamEvent>>), ~close: State -> IO(Result<&2, &2, E, Unit>), limit: Nat, body: Body<State>) -> IO(Result<&2, &2, Error<E>, List<&2, U32>>):
  with(~E, ~State, ~Result<&2, &2, Error<E>, List<&2, U32>>, ~read, ~close, reader => closer => bytesUsing(E, State, reader, closer, limit, body))

def textWith(~E: Data, ~State: Type, ~read: State -> IO(State & Result<&2, &2, E, Maybe<&2, StreamEvent>>), ~close: State -> IO(Result<&2, &2, E, Unit>), limit: Nat, body: Body<State>) -> IO(Result<&2, &2, TextError<E>, String>):
  with(~E, ~State, ~Result<&2, &2, TextError<E>, String>, ~read, ~close, reader => closer => textUsing(E, State, reader, closer, limit, body))

def jsonWith(~E: Data, ~State: Type, ~read: State -> IO(State & Result<&2, &2, E, Maybe<&2, StreamEvent>>), ~close: State -> IO(Result<&2, &2, E, Unit>), limit: Nat, body: Body<State>) -> IO(Result<&2, &2, JSONError<E>, Value.Value>):
  with(~E, ~State, ~Result<&2, &2, JSONError<E>, Value.Value>, ~read, ~close, reader => closer => jsonUsing(E, State, reader, closer, limit, body))

# One acquired byte source. Borrowed callbacks serialize access to the affine
# body; the caller retires all aliases/calls before disposing this owner.
type Owner<-State: Type, -E: Data> is Type:
  Owner{resource: Serial.Owner<Body<State>>, source: SSE.Source<E>, release: Body<State> -> IO(Result<&2, &2, E, Unit>)}

def chunk(-T: Data, -E: Data, map: ResponseProgressError<T> -> E, result: Result<&2, &2, ResponseProgressError<T>, Maybe<&2, List<&2, U32>>>) -> Result<&2, &2, E, Maybe<&2, SSE.Chunk>>:
  match result:
    case Fail{error}: Fail{map(error)}
    case Done{None{}}: Done{None{}}
    case Done{Some{bytes}}: Done{Some{SSE.Bytes{bytes}}}

def pulled(-T: Data, -State: Type, -E: Data, map: ResponseProgressError<T> -> E, value: Next<T, State>) -> Body<State> & Result<&2, &2, E, Maybe<&2, SSE.Chunk>>:
  match value:
    case Next{body, result}: (body, chunk(T, E, map, result))

def closeResult(-T: Data, -E: Data, map: ResponseProgressError<T> -> E, result: Result<&2, &2, ResponseProgressError<T>, Maybe<&2, List<&2, U32>>>) -> Result<&2, &2, E, Unit>:
  match result:
    case Fail{error}: Fail{map(error)}
    case Done{_}: Done{Unit{}}

def closed(-T: Data, -State: Type, -E: Data, map: ResponseProgressError<T> -> E, value: Next<T, State>) -> Body<State> & Result<&2, &2, E, Unit>:
  match value:
    case Next{body, result}: (body, closeResult(T, E, map, result))

def pull(~T: Data, ~State: Type, ~read: State -> IO(State & Result<&2, &2, T, Maybe<&2, StreamEvent>>), ~close: State -> IO(Result<&2, &2, T, Unit>), -E: Data, map: ResponseProgressError<T> -> E, body: Body<State>) -> IO(Body<State> & Result<&2, &2, E, Maybe<&2, SSE.Chunk>>):
  do IO<Body<State> & Result<&2, &2, E, Maybe<&2, SSE.Chunk>>>:
    value : Next<T, State> <- nextWith(~T, ~State, ~read, ~close, body)
    return pulled(T, State, E, map, value)

def closeBody(-T: Data, -State: Type, -E: Data, map: ResponseProgressError<T> -> E, close: State -> IO(Result<&2, &2, T, Unit>), body: Body<State>) -> IO(Body<State> & Result<&2, &2, E, Unit>):
  do IO<Body<State> & Result<&2, &2, E, Unit>>:
    value : Next<T, State> <- closeWith(T, State, close, body)
    return closed(T, State, E, map, value)

def nextCallback(~T: Data, ~State: Type, ~E: Data, ~map: ResponseProgressError<T> -> E, ~read: State -> IO(State & Result<&2, &2, T, Maybe<&2, StreamEvent>>), ~close: State -> IO(Result<&2, &2, T, Unit>), handle: Serial.Handle<Body<State>>, unused: Unit) -> IO(Result<&2, &2, E, Maybe<&2, SSE.Chunk>>):
  Serial.run(Body<State>, Result<&2, &2, E, Maybe<&2, SSE.Chunk>>, handle, body => pull(~T, ~State, ~read, ~close, E, map, body))

def closeCallback(~T: Data, ~State: Type, ~E: Data, ~map: ResponseProgressError<T> -> E, ~close: State -> IO(Result<&2, &2, T, Unit>), handle: Serial.Handle<Body<State>>, unused: Unit) -> IO(Result<&2, &2, E, Unit>):
  Serial.run(Body<State>, Result<&2, &2, E, Unit>, handle, body => closeBody(T, State, E, map, close, body))

def releasedBodySource(-T: Data, -State: Type, -E: Data, map: ResponseProgressError<T> -> E, value: Next<T, State>) -> Result<&2, &2, E, Unit>:
  match value:
    case Next{_, result}: closeResult(T, E, map, result)

def releaseBody(-T: Data, -State: Type, -E: Data, map: ResponseProgressError<T> -> E, close: State -> IO(Result<&2, &2, T, Unit>), body: Body<State>) -> IO(Result<&2, &2, E, Unit>):
  do IO<Result<&2, &2, E, Unit>>:
    value : Next<T, State> <- closeWith(T, State, close, body)
    return releasedBodySource(T, State, E, map, value)

def acquired(~T: Data, ~State: Type, ~E: Data, ~map: ResponseProgressError<T> -> E, ~read: State -> IO(State & Result<&2, &2, T, Maybe<&2, StreamEvent>>), ~close: State -> IO(Result<&2, &2, T, Unit>), resource: Serial.Owner<Body<State>>) -> IO(Owner<State, E>):
  match resource:
    case Serial.Owner{+handle}:
      do IO<Owner<State, E>>:
        next : C.Callback<Unit, Result<&2, &2, E, Maybe<&2, SSE.Chunk>>> <- C.create(~Serial.Handle<Body<State>>, ~Unit, ~Result<&2, &2, E, Maybe<&2, SSE.Chunk>>, ~(nextCallback(~T, ~State, ~E, ~map, ~read, ~close)), handle)
        closeSource : C.Callback<Unit, Result<&2, &2, E, Unit>> <- C.create(~Serial.Handle<Body<State>>, ~Unit, ~Result<&2, &2, E, Unit>, ~(closeCallback(~T, ~State, ~E, ~map, ~close)), handle)
        return Owner{Serial.Owner{handle}, SSE.Source{next, closeSource}, body => releaseBody(T, State, E, map, close, body)}

def create(~T: Data, ~State: Type, ~E: Data, ~map: ResponseProgressError<T> -> E, ~read: State -> IO(State & Result<&2, &2, T, Maybe<&2, StreamEvent>>), ~close: State -> IO(Result<&2, &2, T, Unit>), body: Body<State>) -> IO(Owner<State, E>):
  do IO<Owner<State, E>>:
    resource : Serial.Owner<Body<State>> <- Serial.create(Body<State>, body)
    acquired(~T, ~State, ~E, ~map, ~read, ~close, resource)

def borrow(-State: Type, -E: Data, owner: Owner<State, E>) -> Owner<State, E> & SSE.Source<E>:
  match owner:
    case Owner{resource, +source, release}: (Owner{resource, source, release}, source)

# Fresh SSE cursors do not call return on close. Disposal still closes the
# body, even if no callback was ever invoked or iteration already terminated.
def dispose(-State: Type, -E: Data, owner: Owner<State, E>) -> IO(Result<&2, &2, E, Unit>):
  match owner:
    case Owner{resource, SSE.Source{next, close}, release}:
      do IO<Result<&2, &2, E, Unit>>:
        C.dispose(Unit, Result<&2, &2, E, Maybe<&2, SSE.Chunk>>, next)
        C.dispose(Unit, Result<&2, &2, E, Unit>, close)
        body : Body<State> <- Serial.retire(Body<State>, resource)
        release(body)

# A transport may retain the borrowed child signal until its owner is closed.
# The fetch timer ends at headers; parent cancellation lasts through the body.
type State<-Reason: Data, -Transport: Type> is Type:
  State{transport: Transport, scope: Deadline.Scope<Reason>}

type FetchScopeError<-Reason: Data, -E: Data> is Data:
  Aborted{reason: Abort.AbortReason<Deadline.Cause<Reason>>}
  DispatchFailure{cause: E, abort: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

def attach(-Reason: Data, -Transport: Type, scope: Deadline.Scope<Reason>, response: Response<Transport>) -> IO(Response<State<Reason, Transport>>):
  match response:
    case Response{metadata, Open{transport, expose}}:
      IO.pure(Response<State<Reason, Transport>>, Response{metadata, Open{State{transport, scope}, expose}})
    case Response{metadata, Closed{trailers}}:
      do IO<Response<State<Reason, Transport>>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Response{metadata, Closed{trailers}}

def settled(-Reason: Data, -E: Data, -Transport: Type, scope: Deadline.Scope<Reason>, result: Result<&2, &1, E, Response<Transport>>) -> IO(Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>):
  match result:
    case Fail{cause}:
      do IO<Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Fail{DispatchFailure{cause, reason}}
    case Done{response}:
      do IO<Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>>:
        scope : Deadline.Scope<Reason> <- Deadline.disarm(Reason, scope)
        response : Response<State<Reason, Transport>> <- attach(Reason, Transport, scope, response)
        return Done{response}

def checked(-Reason: Data, -E: Data, -Transport: Type, dispatch: Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, E, Response<Transport>>), scope: Deadline.Scope<Reason>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> IO(Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>):
  match reason:
    case Some{why}:
      do IO<Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>>:
        retired : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Fail{Aborted{why}}
    case None{}:
      do IO<Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>>:
        result : Result<&2, &1, E, Response<Transport>> <- dispatch(signal)
        settled(Reason, E, Transport, scope, result)

def borrowed(-Reason: Data, -E: Data, -Transport: Type, dispatch: Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, E, Response<Transport>>), pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>):
  match pair:
    case (scope, +signal):
      do IO<Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        checked(Reason, E, Transport, dispatch, scope, signal, reason)

# A failed dispatch must retire its internal resources and signal observations
# before returning. A successful dispatch transfers their ownership in response.
# Milliseconds are literal U32; provider-level numeric validation is separate.
def startFetchScope(-Reason: Data, -E: Data, -Transport: Type, milliseconds: U32, parent: Abort.AbortSignal<Reason>, dispatch: Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, E, Response<Transport>>)) -> IO(Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>):
  do IO<Result<&2, &1, FetchScopeError<Reason, E>, Response<State<Reason, Transport>>>>:
    scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
    borrowed(Reason, E, Transport, dispatch, Deadline.borrow(Reason, scope))

def readResult(-Reason: Data, -E: Data, -Transport: Type, scope: Deadline.Scope<Reason>, pair: Transport & Result<&2, &2, E, Maybe<&2, StreamEvent>>) -> State<Reason, Transport> & Result<&2, &2, E, Maybe<&2, StreamEvent>>:
  match pair:
    case (transport, result): (State{transport, scope}, result)

def read(-Reason: Data, -E: Data, -Transport: Type, next: Transport -> IO(Transport & Result<&2, &2, E, Maybe<&2, StreamEvent>>), state: State<Reason, Transport>) -> IO(State<Reason, Transport> & Result<&2, &2, E, Maybe<&2, StreamEvent>>):
  match state:
    case State{transport, scope}:
      do IO<State<Reason, Transport> & Result<&2, &2, E, Maybe<&2, StreamEvent>>>:
        pair : Transport & Result<&2, &2, E, Maybe<&2, StreamEvent>> <- next(transport)
        return readResult(Reason, E, Transport, scope, pair)

# Close the transport first so no signal borrower outlives the child controller.
# Its typed cleanup result is preserved even when disposal reports failure.
def closeFetchScope(-Reason: Data, -E: Data, -Transport: Type, release: Transport -> IO(Result<&2, &2, E, Unit>), state: State<Reason, Transport>) -> IO(Result<&2, &2, E, Unit>):
  match state:
    case State{transport, scope}:
      do IO<Result<&2, &2, E, Unit>>:
        result : Result<&2, &2, E, Unit> <- release(transport)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return result
