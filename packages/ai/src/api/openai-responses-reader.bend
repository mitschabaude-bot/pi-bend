import Base
import ./openai-sse-reader.bend as SSE
import ./openai-sse-json.bend as Json
import ./openai-responses-stream.bend as Stream
import ./openai-responses-wire.bend as Wire
import ../../../runtime/src/json-decode.bend as Decode
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/callback.bend as Cb

# The caller maps these transport-boundary failures into its own error domain,
# which can also represent sink/pricing errors in processResponsesStream.
type Error<-T: Data> is Data:
  StreamingFailure{cause: SSE.Error<T>}
  ProtocolFailure{cause: Decode.Error}

type Owner<-T: Data, -E: Data> is Type:
  Owner{resource: Serial.Owner<SSE.Cursor<T>>, reader: Stream.Reader<E>}

def closedAfterFailure(-T: Data, error: Decode.Error, closed: SSE.CloseResult<T>) -> SSE.Cursor<T> & Result<&2, &2, Error<T>, Maybe<&2, Stream.ResponseStreamEvent>>:
  match closed:
    case SSE.CloseResult{cursor, _}: (cursor, Fail{ProtocolFailure{error}})

# Decode failures occur inside this acquired iterator, so they close the lower
# stream before returning failure. A failing close never replaces that error.
def decoded(-T: Data, cursor: SSE.Cursor<T>, result: Result<&2, &2, Decode.Error, Stream.ResponseStreamEvent>) -> IO(SSE.Cursor<T> & Result<&2, &2, Error<T>, Maybe<&2, Stream.ResponseStreamEvent>>):
  match result:
    case Done{event}: IO.pure(SSE.Cursor<T> & Result<&2, &2, Error<T>, Maybe<&2, Stream.ResponseStreamEvent>>, (cursor, Done{Some{event}}))
    case Fail{error}:
      do IO<SSE.Cursor<T> & Result<&2, &2, Error<T>, Maybe<&2, Stream.ResponseStreamEvent>>>:
        closed : SSE.CloseResult<T> <- SSE.close(T, cursor)
        return closedAfterFailure(T, error, closed)

def received(-T: Data, next: SSE.Next<T>) -> IO(SSE.Cursor<T> & Result<&2, &2, Error<T>, Maybe<&2, Stream.ResponseStreamEvent>>):
  match next:
    case SSE.Next{cursor, Fail{error}}: IO.pure(SSE.Cursor<T> & Result<&2, &2, Error<T>, Maybe<&2, Stream.ResponseStreamEvent>>, (cursor, Fail{StreamingFailure{error}}))
    case SSE.Next{cursor, Done{None{}}}: IO.pure(SSE.Cursor<T> & Result<&2, &2, Error<T>, Maybe<&2, Stream.ResponseStreamEvent>>, (cursor, Done{None{}}))
    case SSE.Next{cursor, Done{Some{message}}}: decoded(T, cursor, Wire.fromMessage(message))

def mapped(-T: Data, -E: Data, -A: Data, map: Error<T> -> E, result: Result<&2, &2, Error<T>, A>) -> Result<&2, &2, E, A>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{map(error)}

def mappedNext(-T: Data, -E: Data, map: Error<T> -> E, result: SSE.Cursor<T> & Result<&2, &2, Error<T>, Maybe<&2, Stream.ResponseStreamEvent>>) -> SSE.Cursor<T> & Result<&2, &2, E, Maybe<&2, Stream.ResponseStreamEvent>>:
  match result:
    case Tuple{cursor, result}: (cursor, mapped(T, E, Maybe<&2, Stream.ResponseStreamEvent>, map, result))

def pull(-T: Data, -E: Data, map: Error<T> -> E, cursor: SSE.Cursor<T>) -> IO(SSE.Cursor<T> & Result<&2, &2, E, Maybe<&2, Stream.ResponseStreamEvent>>):
  do IO<SSE.Cursor<T> & Result<&2, &2, E, Maybe<&2, Stream.ResponseStreamEvent>>>:
    next : SSE.Next<T> <- SSE.next(T, cursor)
    result : SSE.Cursor<T> & Result<&2, &2, Error<T>, Maybe<&2, Stream.ResponseStreamEvent>> <- received(T, next)
    return mappedNext(T, E, map, result)

def mappedClose(-T: Data, -E: Data, map: Error<T> -> E, result: SSE.CloseResult<T>) -> SSE.Cursor<T> & Result<&2, &2, E, Unit>:
  match result:
    case SSE.CloseResult{cursor, Done{value}}: (cursor, Done{value})
    case SSE.CloseResult{cursor, Fail{error}}: (cursor, Fail{map(StreamingFailure{error})})

def closeCursor(-T: Data, -E: Data, map: Error<T> -> E, cursor: SSE.Cursor<T>) -> IO(SSE.Cursor<T> & Result<&2, &2, E, Unit>):
  do IO<SSE.Cursor<T> & Result<&2, &2, E, Unit>>:
    closed : SSE.CloseResult<T> <- SSE.close(T, cursor)
    return mappedClose(T, E, map, closed)

def nextCallback(~T: Data, ~E: Data, ~map: Error<T> -> E, handle: Serial.Handle<SSE.Cursor<T>>, unused: Unit) -> IO(Result<&2, &2, E, Maybe<&2, Stream.ResponseStreamEvent>>):
  Serial.run(SSE.Cursor<T>, Result<&2, &2, E, Maybe<&2, Stream.ResponseStreamEvent>>, handle, cursor => pull(T, E, map, cursor))

def closeCallback(~T: Data, ~E: Data, ~map: Error<T> -> E, handle: Serial.Handle<SSE.Cursor<T>>, unused: Unit) -> IO(Result<&2, &2, E, Unit>):
  Serial.run(SSE.Cursor<T>, Result<&2, &2, E, Unit>, handle, cursor => closeCursor(T, E, map, cursor))

def acquired(~T: Data, ~E: Data, ~map: Error<T> -> E, resource: Serial.Owner<SSE.Cursor<T>>) -> IO(Owner<T, E>):
  match resource:
    case Serial.Owner{+handle}:
      do IO<Owner<T, E>>:
        next : Cb.Callback<Unit, Result<&2, &2, E, Maybe<&2, Stream.ResponseStreamEvent>>> <- Cb.create(~Serial.Handle<SSE.Cursor<T>>, ~Unit, ~Result<&2, &2, E, Maybe<&2, Stream.ResponseStreamEvent>>, ~(nextCallback(~T, ~E, ~map)), handle)
        close : Cb.Callback<Unit, Result<&2, &2, E, Unit>> <- Cb.create(~Serial.Handle<SSE.Cursor<T>>, ~Unit, ~Result<&2, &2, E, Unit>, ~(closeCallback(~T, ~E, ~map)), handle)
        return Owner{Serial.Owner{handle}, Stream.Reader{next, close}}

def create(~T: Data, ~E: Data, ~map: Error<T> -> E, cursor: SSE.Cursor<T>) -> IO(Owner<T, E>):
  do IO<Owner<T, E>>:
    resource : Serial.Owner<SSE.Cursor<T>> <- Serial.create(SSE.Cursor<T>, cursor)
    acquired(~T, ~E, ~map, resource)

def borrow(-T: Data, -E: Data, owner: Owner<T, E>) -> Owner<T, E> & Stream.Reader<E>:
  match owner:
    case Owner{resource, +reader}: (Owner{resource, reader}, reader)

def disposalResult(-T: Data, closed: SSE.CloseResult<T>) -> Result<&2, &2, Error<T>, Unit>:
  match closed:
    case SSE.CloseResult{_, Done{value}}: Done{value}
    case SSE.CloseResult{_, Fail{error}}: Fail{StreamingFailure{error}}

# Retire all Reader aliases/calls first. This releases adapter-owned handles,
# closes any remaining acquired stream and leaves borrowed transport hooks to
# their original owner. Disposal reports cleanup failure in the boundary type.
def dispose(-T: Data, -E: Data, owner: Owner<T, E>) -> IO(Result<&2, &2, Error<T>, Unit>):
  match owner:
    case Owner{resource, Stream.Reader{next, close}}:
      do IO<Result<&2, &2, Error<T>, Unit>>:
        Cb.dispose(Unit, Result<&2, &2, E, Maybe<&2, Stream.ResponseStreamEvent>>, next)
        Cb.dispose(Unit, Result<&2, &2, E, Unit>, close)
        cursor : SSE.Cursor<T> <- Serial.retire(SSE.Cursor<T>, resource)
        closed : SSE.CloseResult<T> <- SSE.close(T, cursor)
        return disposalResult(T, closed)
