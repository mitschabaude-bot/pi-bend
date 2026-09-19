import Base
import ../../../runtime/src/callback.bend as Cb
import ../../../runtime/src/sse-reader.bend as SSE
import ../../../runtime/src/sse-decoder.bend as Event
import ./openai-sse-json.bend as Json

# Transport adapters classify cancellation explicitly, without string matching.
type ReadError<-E: Data> is Data:
  Failure{cause: E}
  Aborted{}

type Error<-E: Data> is Data:
  TransportFailure{cause: E}
  DispatchFailure{cause: Json.Error}
  DiagnosticFailure{cause: E}

type Hooks<-E: Data> is Data:
  Hooks{abort: Cb.Callback<Unit, Unit>, diagnostic: Cb.Callback<Json.Error, Result<&2, &2, ReadError<E>, Unit>>}

type Phase is Data:
  Fresh{}
  Active{}
  Closed{}

# One acquired stream, with borrowed callbacks. Its affine successor prevents
# concurrent pulls and reuse of predecessor cursors. The owner supplies an
# already acquired source; stream factories and tee are separate interfaces.
type Cursor<-E: Data> is Type:
  Cursor{reader: SSE.Cursor<ReadError<E>>, hooks: Hooks<E>, synthesize: Bool, phase: Phase}

type Next<-E: Data> is Type:
  Next{cursor: Cursor<E>, result: Result<&2, &2, Error<E>, Maybe<&2, Json.Message>>}

type CloseResult<-E: Data> is Type:
  CloseResult{cursor: Cursor<E>, result: Result<&2, &2, Error<E>, Unit>}

type Decision<-E: Data> is Data:
  ReadMore{state: Json.State}
  Deliver{message: Json.Message}
  Finish{result: Result<&2, &2, Error<E>, Maybe<&2, Json.Message>>, abort: Bool, diagnostic: Maybe<&2, Json.Error>}

type Transition<-E: Data> is Type:
  Transition{reader: SSE.Cursor<ReadError<E>>, decision: Decision<E>}

def create(-E: Data, source: SSE.Source<ReadError<E>>, hooks: Hooks<E>, synthesize: Bool) -> Cursor<E>:
  Cursor{SSE.create(ReadError<E>, source), hooks, synthesize, Fresh{}}

def incomplete(state: Json.State) -> Bool:
  match state:
    case Json.Receiving{}: True{}
    case Json.DoneMarker{}: False{}

def rejected(-E: Data, error: Json.Error) -> Decision<E>:
  match error:
    case Json.InvalidJson{+cause, +data, +raw, +target}:
      Finish{Fail{DispatchFailure{Json.InvalidJson{cause, data, raw, target}}}, True{}, Some{Json.InvalidJson{cause, data, raw, target}}}
    case other: Finish{Fail{DispatchFailure{other}}, True{}, None{}}

def dispatched(-E: Data, step: Json.Step) -> Decision<E>:
  match step:
    case Json.Skip{state}: ReadMore{state}
    case Json.YieldMessage{message}: Deliver{message}
    case Json.Reject{error}: rejected(E, error)

def received(-E: Data, state: Json.State, synthesize: Bool, result: Result<&2, &2, ReadError<E>, Maybe<&2, Event.ServerSentEvent>>) -> Decision<E>:
  match result:
    case Fail{Aborted{}}: Finish{Done{None{}}, incomplete(state), None{}}
    case Fail{Failure{cause}}: Finish{Fail{TransportFailure{cause}}, incomplete(state), None{}}
    case Done{None{}}: Finish{Done{None{}}, False{}, None{}}
    case Done{Some{event}}: dispatched(E, Json.step(state, synthesize, event))

def transition(-E: Data, state: Json.State, synthesize: Bool, next: SSE.Next<ReadError<E>>) -> Transition<E>:
  match next:
    case SSE.Next{reader, result}: Transition{reader, received(E, state, synthesize, result)}

def abortRequest(-E: Data, hooks: Hooks<E>, abort: Bool) -> IO(Unit):
  match hooks abort:
    case Hooks{callback, _} True{}: Cb.call(Unit, Unit, callback, Unit{})
    case _ False{}: IO.pure(Unit, Unit{})

def diagnose(-E: Data, hooks: Hooks<E>, error: Maybe<&2, Json.Error>) -> IO(Result<&2, &2, ReadError<E>, Unit>):
  match hooks error:
    case _ None{}: IO.pure(Result<&2, &2, ReadError<E>, Unit>, Done{Unit{}})
    case Hooks{_, callback} Some{error}: Cb.call(Json.Error, Result<&2, &2, ReadError<E>, Unit>, callback, error)

def diagnosed(-E: Data, original: Result<&2, &2, Error<E>, Maybe<&2, Json.Message>>, diagnostic: Result<&2, &2, ReadError<E>, Unit>) -> Result<&2, &2, Error<E>, Maybe<&2, Json.Message>>:
  match diagnostic:
    case Done{_}: original
    case Fail{Aborted{}}: Done{None{}}
    case Fail{Failure{cause}}: Fail{DiagnosticFailure{cause}}

# A body/diagnostic failure retains precedence over a failing source return.
# A failed source next is already closed by the lower reader and is not returned.
def finished(-E: Data, +hooks: Hooks<E>, synthesize: Bool, result: Result<&2, &2, Error<E>, Maybe<&2, Json.Message>>, abort: Bool, closed: SSE.CloseResult<ReadError<E>>) -> IO(Next<E>):
  match closed:
    case SSE.CloseResult{reader, _}:
      do IO<Next<E>>:
        abortRequest(E, hooks, abort)
        return Next{Cursor{reader, hooks, synthesize, Closed{}}, result}

# Input controls progress, including draining all input after a DONE marker.
@unsafe def drive(-E: Data, +hooks: Hooks<E>, +synthesize: Bool, step: Transition<E>) -> IO(Next<E>):
  match step:
    case Transition{reader, ReadMore{+state}}:
      do IO<Next<E>>:
        next : SSE.Next<ReadError<E>> <- SSE.next(ReadError<E>, reader)
        drive(E, hooks, synthesize, transition(E, state, synthesize, next))
    case Transition{reader, Deliver{message}}:
      IO.pure(Next<E>, Next{Cursor{reader, hooks, synthesize, Active{}}, Done{Some{message}}})
    case Transition{reader, Finish{result, abort, diagnostic}}:
      do IO<Next<E>>:
        reported : Result<&2, &2, ReadError<E>, Unit> <- diagnose(E, hooks, diagnostic)
        closed : SSE.CloseResult<ReadError<E>> <- SSE.close(ReadError<E>, reader)
        finished(E, hooks, synthesize, diagnosed(E, result, reported), abort, closed)

def next(-E: Data, cursor: Cursor<E>) -> IO(Next<E>):
  match cursor:
    case Cursor{reader, hooks, synthesize, Closed{}}:
      IO.pure(Next<E>, Next{Cursor{reader, hooks, synthesize, Closed{}}, Done{None{}}})
    case Cursor{reader, hooks, synthesize, _}: drive(E, hooks, synthesize, Transition{reader, ReadMore{Json.Receiving{}}})

def closeError(-E: Data, result: Result<&2, &2, ReadError<E>, Unit>) -> Result<&2, &2, Error<E>, Unit>:
  match result:
    case Fail{Failure{cause}}: Fail{TransportFailure{cause}}
    case _: Done{Unit{}}

def closed(-E: Data, +hooks: Hooks<E>, synthesize: Bool, phase: Phase, result: SSE.CloseResult<ReadError<E>>) -> IO(CloseResult<E>):
  match phase result:
    case Active{} SSE.CloseResult{reader, result}:
      do IO<CloseResult<E>>:
        abortRequest(E, hooks, True{})
        return CloseResult{Cursor{reader, hooks, synthesize, Closed{}}, closeError(E, result)}
    case _ SSE.CloseResult{reader, result}:
      IO.pure(CloseResult<E>, CloseResult{Cursor{reader, hooks, synthesize, Closed{}}, closeError(E, result)})

def close(-E: Data, cursor: Cursor<E>) -> IO(CloseResult<E>):
  match cursor:
    case Cursor{reader, hooks, synthesize, phase}:
      do IO<CloseResult<E>>:
        result : SSE.CloseResult<ReadError<E>> <- SSE.close(ReadError<E>, reader)
        closed(E, hooks, synthesize, phase, result)
