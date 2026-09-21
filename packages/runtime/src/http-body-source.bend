import Base
import ./http-response.bend as Response
import ./http-response-progress.bend as Progress
import ./http-response-stream.bend as Stream
import ./sse-reader.bend as SSE
import ./serial-resource.bend as Serial
import ./callback.bend as Cb

# One acquired byte source. Borrowed callbacks serialize access to the affine
# body; the caller retires all aliases/calls before disposing this owner.
type Owner<-State: Type, -E: Data> is Type:
  Owner{resource: Serial.Owner<Response.Body<State>>, source: SSE.Source<E>, release: Response.Body<State> -> IO(Result<&2, &2, E, Unit>)}

def chunk(-T: Data, -E: Data, map: Progress.Error<T> -> E, result: Result<&2, &2, Progress.Error<T>, Maybe<&2, List<&2, U32>>>) -> Result<&2, &2, E, Maybe<&2, SSE.Chunk>>:
  match result:
    case Fail{error}: Fail{map(error)}
    case Done{None{}}: Done{None{}}
    case Done{Some{bytes}}: Done{Some{SSE.Bytes{bytes}}}

def pulled(-T: Data, -State: Type, -E: Data, map: Progress.Error<T> -> E, value: Response.Next<T, State>) -> Response.Body<State> & Result<&2, &2, E, Maybe<&2, SSE.Chunk>>:
  match value:
    case Response.Next{body, result}: (body, chunk(T, E, map, result))

def closeResult(-T: Data, -E: Data, map: Progress.Error<T> -> E, result: Result<&2, &2, Progress.Error<T>, Maybe<&2, List<&2, U32>>>) -> Result<&2, &2, E, Unit>:
  match result:
    case Fail{error}: Fail{map(error)}
    case Done{_}: Done{Unit{}}

def closed(-T: Data, -State: Type, -E: Data, map: Progress.Error<T> -> E, value: Response.Next<T, State>) -> Response.Body<State> & Result<&2, &2, E, Unit>:
  match value:
    case Response.Next{body, result}: (body, closeResult(T, E, map, result))

def pull(~T: Data, ~State: Type, ~read: State -> IO(State & Result<&2, &2, T, Maybe<&2, Stream.Event>>), ~close: State -> IO(Result<&2, &2, T, Unit>), -E: Data, map: Progress.Error<T> -> E, body: Response.Body<State>) -> IO(Response.Body<State> & Result<&2, &2, E, Maybe<&2, SSE.Chunk>>):
  do IO<Response.Body<State> & Result<&2, &2, E, Maybe<&2, SSE.Chunk>>>:
    value : Response.Next<T, State> <- Response.nextWith(~T, ~State, ~read, ~close, body)
    return pulled(T, State, E, map, value)

def closeBody(-T: Data, -State: Type, -E: Data, map: Progress.Error<T> -> E, close: State -> IO(Result<&2, &2, T, Unit>), body: Response.Body<State>) -> IO(Response.Body<State> & Result<&2, &2, E, Unit>):
  do IO<Response.Body<State> & Result<&2, &2, E, Unit>>:
    value : Response.Next<T, State> <- Response.closeWith(T, State, close, body)
    return closed(T, State, E, map, value)

def nextCallback(~T: Data, ~State: Type, ~E: Data, ~map: Progress.Error<T> -> E, ~read: State -> IO(State & Result<&2, &2, T, Maybe<&2, Stream.Event>>), ~close: State -> IO(Result<&2, &2, T, Unit>), handle: Serial.Handle<Response.Body<State>>, unused: Unit) -> IO(Result<&2, &2, E, Maybe<&2, SSE.Chunk>>):
  Serial.run(Response.Body<State>, Result<&2, &2, E, Maybe<&2, SSE.Chunk>>, handle, body => pull(~T, ~State, ~read, ~close, E, map, body))

def closeCallback(~T: Data, ~State: Type, ~E: Data, ~map: Progress.Error<T> -> E, ~close: State -> IO(Result<&2, &2, T, Unit>), handle: Serial.Handle<Response.Body<State>>, unused: Unit) -> IO(Result<&2, &2, E, Unit>):
  Serial.run(Response.Body<State>, Result<&2, &2, E, Unit>, handle, body => closeBody(T, State, E, map, close, body))

def released(-T: Data, -State: Type, -E: Data, map: Progress.Error<T> -> E, value: Response.Next<T, State>) -> Result<&2, &2, E, Unit>:
  match value:
    case Response.Next{_, result}: closeResult(T, E, map, result)

def releaseBody(-T: Data, -State: Type, -E: Data, map: Progress.Error<T> -> E, close: State -> IO(Result<&2, &2, T, Unit>), body: Response.Body<State>) -> IO(Result<&2, &2, E, Unit>):
  do IO<Result<&2, &2, E, Unit>>:
    value : Response.Next<T, State> <- Response.closeWith(T, State, close, body)
    return released(T, State, E, map, value)

def acquired(~T: Data, ~State: Type, ~E: Data, ~map: Progress.Error<T> -> E, ~read: State -> IO(State & Result<&2, &2, T, Maybe<&2, Stream.Event>>), ~close: State -> IO(Result<&2, &2, T, Unit>), resource: Serial.Owner<Response.Body<State>>) -> IO(Owner<State, E>):
  match resource:
    case Serial.Owner{+handle}:
      do IO<Owner<State, E>>:
        next : Cb.Callback<Unit, Result<&2, &2, E, Maybe<&2, SSE.Chunk>>> <- Cb.create(~Serial.Handle<Response.Body<State>>, ~Unit, ~Result<&2, &2, E, Maybe<&2, SSE.Chunk>>, ~(nextCallback(~T, ~State, ~E, ~map, ~read, ~close)), handle)
        closeSource : Cb.Callback<Unit, Result<&2, &2, E, Unit>> <- Cb.create(~Serial.Handle<Response.Body<State>>, ~Unit, ~Result<&2, &2, E, Unit>, ~(closeCallback(~T, ~State, ~E, ~map, ~close)), handle)
        return Owner{Serial.Owner{handle}, SSE.Source{next, closeSource}, body => releaseBody(T, State, E, map, close, body)}

def create(~T: Data, ~State: Type, ~E: Data, ~map: Progress.Error<T> -> E, ~read: State -> IO(State & Result<&2, &2, T, Maybe<&2, Stream.Event>>), ~close: State -> IO(Result<&2, &2, T, Unit>), body: Response.Body<State>) -> IO(Owner<State, E>):
  do IO<Owner<State, E>>:
    resource : Serial.Owner<Response.Body<State>> <- Serial.create(Response.Body<State>, body)
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
        Cb.dispose(Unit, Result<&2, &2, E, Maybe<&2, SSE.Chunk>>, next)
        Cb.dispose(Unit, Result<&2, &2, E, Unit>, close)
        body : Response.Body<State> <- Serial.retire(Response.Body<State>, resource)
        release(body)
