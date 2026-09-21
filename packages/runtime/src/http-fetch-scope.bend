import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./http-response.bend as Response
import ./http-response-stream.bend as Stream

# A transport may retain the borrowed child signal until its owner is closed.
# The fetch timer ends at headers; parent cancellation lasts through the body.
type State<-Reason: Data, -Transport: Type> is Type:
  State{transport: Transport, scope: Deadline.Scope<Reason>}

type Error<-Reason: Data, -E: Data> is Data:
  Aborted{reason: Abort.AbortReason<Deadline.Cause<Reason>>}
  DispatchFailure{cause: E, abort: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

def attach(-Reason: Data, -Transport: Type, scope: Deadline.Scope<Reason>, response: Response.Response<Transport>) -> IO(Response.Response<State<Reason, Transport>>):
  match response:
    case Response.Response{metadata, Response.Open{transport, expose}}:
      IO.pure(Response.Response<State<Reason, Transport>>, Response.Response{metadata, Response.Open{State{transport, scope}, expose}})
    case Response.Response{metadata, Response.Closed{trailers}}:
      do IO<Response.Response<State<Reason, Transport>>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Response.Response{metadata, Response.Closed{trailers}}

def settled(-Reason: Data, -E: Data, -Transport: Type, scope: Deadline.Scope<Reason>, result: Result<&2, &1, E, Response.Response<Transport>>) -> IO(Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>):
  match result:
    case Fail{cause}:
      do IO<Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Fail{DispatchFailure{cause, reason}}
    case Done{response}:
      do IO<Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>>:
        scope : Deadline.Scope<Reason> <- Deadline.disarm(Reason, scope)
        response : Response.Response<State<Reason, Transport>> <- attach(Reason, Transport, scope, response)
        return Done{response}

def checked(-Reason: Data, -E: Data, -Transport: Type, dispatch: Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, E, Response.Response<Transport>>), scope: Deadline.Scope<Reason>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> IO(Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>):
  match reason:
    case Some{why}:
      do IO<Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>>:
        retired : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Fail{Aborted{why}}
    case None{}:
      do IO<Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>>:
        result : Result<&2, &1, E, Response.Response<Transport>> <- dispatch(signal)
        settled(Reason, E, Transport, scope, result)

def borrowed(-Reason: Data, -E: Data, -Transport: Type, dispatch: Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, E, Response.Response<Transport>>), pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>):
  match pair:
    case (scope, +signal):
      do IO<Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        checked(Reason, E, Transport, dispatch, scope, signal, reason)

# A failed dispatch must retire its internal resources and signal observations
# before returning. A successful dispatch transfers their ownership in response.
# Milliseconds are literal U32; provider-level numeric validation is separate.
def start(-Reason: Data, -E: Data, -Transport: Type, milliseconds: U32, parent: Abort.AbortSignal<Reason>, dispatch: Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, E, Response.Response<Transport>>)) -> IO(Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>):
  do IO<Result<&2, &1, Error<Reason, E>, Response.Response<State<Reason, Transport>>>>:
    scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
    borrowed(Reason, E, Transport, dispatch, Deadline.borrow(Reason, scope))

def readResult(-Reason: Data, -E: Data, -Transport: Type, scope: Deadline.Scope<Reason>, pair: Transport & Result<&2, &2, E, Maybe<&2, Stream.Event>>) -> State<Reason, Transport> & Result<&2, &2, E, Maybe<&2, Stream.Event>>:
  match pair:
    case (transport, result): (State{transport, scope}, result)

def read(-Reason: Data, -E: Data, -Transport: Type, next: Transport -> IO(Transport & Result<&2, &2, E, Maybe<&2, Stream.Event>>), state: State<Reason, Transport>) -> IO(State<Reason, Transport> & Result<&2, &2, E, Maybe<&2, Stream.Event>>):
  match state:
    case State{transport, scope}:
      do IO<State<Reason, Transport> & Result<&2, &2, E, Maybe<&2, Stream.Event>>>:
        pair : Transport & Result<&2, &2, E, Maybe<&2, Stream.Event>> <- next(transport)
        return readResult(Reason, E, Transport, scope, pair)

# Close the transport first so no signal borrower outlives the child controller.
# Its typed cleanup result is preserved even when disposal reports failure.
def close(-Reason: Data, -E: Data, -Transport: Type, release: Transport -> IO(Result<&2, &2, E, Unit>), state: State<Reason, Transport>) -> IO(Result<&2, &2, E, Unit>):
  match state:
    case State{transport, scope}:
      do IO<Result<&2, &2, E, Unit>>:
        result : Result<&2, &2, E, Unit> <- release(transport)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return result
