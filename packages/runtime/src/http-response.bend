import Base
import ./http-transport-callbacks.bend as Ops
import ./http-response-stream.bend as Stream
import ./http-response-metadata.bend as Metadata
import ./http-response-progress.bend as Progress
import ./http-header.bend as Header

# State is the affine transport owner. Read returns its successor on every
# path; close relinquishes it even when reporting a cleanup error. Borrowed
# callback handles permit repeated invocation without copying affine closures.
type Body<-State: Type> is Type:
  Open{state: State, expose: Bool}
  Closed{trailers: Maybe<&2, List<&2, Header.Header>>}

type Response<-State: Type> is Type:
  Response{metadata: Metadata.Metadata, body: Body<State>}

type Next<-E: Data, -State: Type> is Type:
  Next{body: Body<State>, result: Result<&2, &2, Progress.Error<E>, Maybe<&2, List<&2, U32>>>}

def failedStart(-E: Data, -State: Type, primary: Progress.PrimaryError<E>, cleanup: Result<&2, &2, E, Unit>) -> Result<&2, &1, Progress.Error<E>, Response<State>>:
  match cleanup:
    case Done{_}: Fail{Progress.PrimaryFailure{primary}}
    case Fail{error}: Fail{Progress.FailureWithCleanup{primary, error}}

def headRead(-E: Data, -State: Type, pair: State & Result<&2, &2, E, Maybe<&2, Stream.Event>>) -> State & Progress.HeadDecision<E>:
  match pair:
    case (state, result): (state, Progress.head(E, result))

def bodyRead(-E: Data, -State: Type, expose: Bool, pair: State & Result<&2, &2, E, Maybe<&2, Stream.Event>>) -> State & Progress.BodyDecision<E>:
  match pair:
    case (state, result): (state, Progress.body(E, expose, result))

# An effectful source controls progress. The HTTP parser bounds informational
# heads; this generic adapter does not impose a second, unrelated budget.
@unsafe def seek(-E: Data, -State: Type, +read: Ops.Read(E, State), +close: Ops.Close(E, State), pair: State & Progress.HeadDecision<E>) -> IO(Result<&2, &1, Progress.Error<E>, Response<State>>):
  match pair:
    case (state, Progress.Ready{+metadata}): IO.pure(Result<&2, &1, Progress.Error<E>, Response<State>>, Done{Response{metadata, Open{state, Metadata.bodyPresent(metadata)}}})
    case (state, Progress.HeadFailure{error}):
      do IO<Result<&2, &1, Progress.Error<E>, Response<State>>>:
        cleanup : Result<&2, &2, E, Unit> <- Ops.close(E, State, close, state)
        return failedStart(E, State, error, cleanup)
    case (state, Progress.SeekHead{}):
      do IO<Result<&2, &1, Progress.Error<E>, Response<State>>>:
        pair : State & Result<&2, &2, E, Maybe<&2, Stream.Event>> <- Ops.read(E, State, read, state)
        seek(E, State, read, close, headRead(E, State, pair))

def start(-E: Data, -State: Type, read: Ops.Read(E, State), close: Ops.Close(E, State), state: State) -> IO(Result<&2, &1, Progress.Error<E>, Response<State>>):
  seek(E, State, read, close, (state, Progress.SeekHead{}))

def finished(-E: Data, -State: Type, trailers: Maybe<&2, List<&2, Header.Header>>, result: Result<&2, &2, Progress.Error<E>, Unit>) -> Next<E, State>:
  match result:
    case Done{_}: Next{Closed{trailers}, Done{None{}}}
    case Fail{error}: Next{Closed{trailers}, Fail{error}}

# Completion still closes the transport owner: a parser may have released the
# socket while buffered events and callback factories remain to be retired.
@unsafe def drive(-E: Data, -State: Type, +read: Ops.Read(E, State), +close: Ops.Close(E, State), +expose: Bool, pair: State & Progress.BodyDecision<E>) -> IO(Next<E, State>):
  match pair:
    case (state, Progress.Chunk{bytes}): IO.pure(Next<E, State>, Next{Open{state, expose}, Done{Some{bytes}}})
    case (state, Progress.Complete{fields}):
      do IO<Next<E, State>>:
        cleanup : Result<&2, &2, E, Unit> <- Ops.close(E, State, close, state)
        return finished(E, State, Some{fields}, Progress.outcome(E, None{}, cleanup))
    case (state, Progress.BodyFailure{error}):
      do IO<Next<E, State>>:
        cleanup : Result<&2, &2, E, Unit> <- Ops.close(E, State, close, state)
        return finished(E, State, None{}, Progress.outcome(E, Some{error}, cleanup))
    case (state, Progress.ReadMore{}):
      do IO<Next<E, State>>:
        pair : State & Result<&2, &2, E, Maybe<&2, Stream.Event>> <- Ops.read(E, State, read, state)
        drive(E, State, read, close, expose, bodyRead(E, State, expose, pair))

def next(-E: Data, -State: Type, read: Ops.Read(E, State), close: Ops.Close(E, State), body: Body<State>) -> IO(Next<E, State>):
  match body:
    case Closed{fields}: IO.pure(Next<E, State>, Next{Closed{fields}, Done{None{}}})
    case Open{state, expose}: drive(E, State, read, close, expose, (state, Progress.ReadMore{}))

# Early close returns a closed successor and reports cleanup failure once.
def closeWith(-E: Data, -State: Type, close: State -> IO(Result<&2, &2, E, Unit>), body: Body<State>) -> IO(Next<E, State>):
  match body:
    case Closed{fields}: IO.pure(Next<E, State>, Next{Closed{fields}, Done{None{}}})
    case Open{state, _}:
      do IO<Next<E, State>>:
        cleanup : Result<&2, &2, E, Unit> <- close(state)
        return finished(E, State, None{}, Progress.outcome(E, None{}, cleanup))

# Compile-time operations are lifted into owned factories for this call.
def startWith(~E: Data, ~State: Type, ~read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), ~close: State -> IO(Result<&2, &2, E, Unit>), state: State) -> IO(Result<&2, &1, Progress.Error<E>, Response<State>>):
  Ops.with(~E, ~State, ~Result<&2, &1, Progress.Error<E>, Response<State>>, ~read, ~close, reader => closer => start(E, State, reader, closer, state))

def nextWith(~E: Data, ~State: Type, ~read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), ~close: State -> IO(Result<&2, &2, E, Unit>), body: Body<State>) -> IO(Next<E, State>):
  Ops.with(~E, ~State, ~Next<E, State>, ~read, ~close, reader => closer => next(E, State, reader, closer, body))
