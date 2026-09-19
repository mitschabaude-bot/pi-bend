import Base
import ./abort.bend as A
import ./deferred.bend as D
import ./socket-interrupt.bend as I

# A connection-wide observation, not one watcher/duplicate per byte read.
# The caller owns the signal and keeps it alive until this owner is closed.
type Error<-Reason: Data> is Data:
  Aborted{reason: A.AbortReason<Reason>}
  SocketError{code: U32, message: String}

type Lifetime<-Reason: Data> is Type:
  Lifetime{signal: A.AbortSignal<Reason>, interrupt: I.Owner, cancellation: D.Cancellation<A.AbortReason<Reason>>, watcher: Chan(Result<&2, &2, I.Error, Unit>)}

type Owner<-Reason: Data> is Type:
  Owner{socket: Socket, lifetime: Lifetime<Reason>}

def cancelled(result: Result<&2, &2, I.Error, Bool>) -> Result<&2, &2, I.Error, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{error}

def cancelForReason(-Reason: Data, handle: I.Handle, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Result<&2, &2, I.Error, Unit>):
  match reason:
    case None{}: IO.pure(Result<&2, &2, I.Error, Unit>, Done{Unit{}})
    case Some{_}:
      do IO<Result<&2, &2, I.Error, Unit>>:
        result : Result<&2, &2, I.Error, Bool> <- I.cancel(handle)
        return cancelled(result)

def watch(-Reason: Data, handle: I.Handle, ticket: D.Ticket<Maybe<&2, A.AbortReason<Reason>>>) -> IO(Result<&2, &2, I.Error, Unit>):
  do IO<Result<&2, &2, I.Error, Unit>>:
    reason : Maybe<&2, A.AbortReason<Reason>> <- D.wait(Maybe<&2, A.AbortReason<Reason>>, ticket)
    cancelForReason(Reason, handle, reason)

def observing(-Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, pair: I.Owner & I.Handle, observation: D.Observation<A.AbortReason<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  match pair observation:
    case (owner, handle) D.Observation{ticket, cancellation}:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        watcher : Chan(Result<&2, &2, I.Error, Unit>) <- IO.fork(Result<&2, &2, I.Error, Unit>, watch(Reason, handle, ticket))
        return Done{Owner{socket, Lifetime{signal, owner, cancellation, watcher}}}

def acquired(-Reason: Data, +signal: A.AbortSignal<Reason>, pair: Socket & Result<&2, &1, I.Error, I.Owner>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  match pair:
    case (socket, Fail{I.Error{code, message}}):
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        Socket.close(socket)
        return Fail{SocketError{code, message}}
    case (socket, Done{owner}):
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        observation : D.Observation<A.AbortReason<Reason>> <- A.observe(Reason, signal)
        observing(Reason, socket, signal, I.borrow(owner), observation)

def checked(-Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  match reason:
    case Some{why}:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        Socket.close(socket)
        return Fail{Aborted{why}}
    case None{}:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        pair : Socket & Result<&2, &1, I.Error, I.Owner> <- I.create(socket)
        acquired(Reason, signal, pair)

# Takes ownership of an already connected socket, including on failure.
# Connection establishment itself is outside this scope.
def create(-Reason: Data, socket: Socket, +signal: A.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
    reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
    checked(Reason, socket, signal, reason)

def outcome(-Reason: Data, -Value: Data, value: Result<&1, &1, U32 & String, Value>, reason: Maybe<&2, A.AbortReason<Reason>>) -> Result<&2, &2, Error<Reason>, Value>:
  match value reason:
    case _ Some{why}: Fail{Aborted{why}}
    case Fail{(code, message)} None{}: Fail{SocketError{code, message}}
    case Done{value} None{}: Done{value}

def received(-Reason: Data, -Value: Data, lifetime: Lifetime<Reason>, signal: A.AbortSignal<Reason>, pair: Socket & Result<&1, &1, U32 & String, Value>) -> IO(Owner<Reason> & Result<&2, &2, Error<Reason>, Value>):
  match pair:
    case (socket, value):
      do IO<Owner<Reason> & Result<&2, &2, Error<Reason>, Value>>:
        reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        return (Owner{socket, lifetime}, outcome(Reason, Value, value, reason))

def perform(-Reason: Data, -Value: Data, socket: Socket, lifetime: Lifetime<Reason>, signal: A.AbortSignal<Reason>, operation: Socket -> IO(Socket & Result<&1, &1, U32 & String, Value>), reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Owner<Reason> & Result<&2, &2, Error<Reason>, Value>):
  match reason:
    case Some{why}: IO.pure(Owner<Reason> & Result<&2, &2, Error<Reason>, Value>, (Owner{socket, lifetime}, Fail{Aborted{why}}))
    case None{}:
      do IO<Owner<Reason> & Result<&2, &2, Error<Reason>, Value>>:
        pair : Socket & Result<&1, &1, U32 & String, Value> <- operation(socket)
        received(Reason, Value, lifetime, signal, pair)

# Observe abort both before IO and after it settles. Local shutdown's EOF or
# socket error must never hide a retained abort reason. Concurrent abort after
# the final observation may legitimately follow an already completed operation.
def run(-Reason: Data, -Value: Data, owner: Owner<Reason>, operation: Socket -> IO(Socket & Result<&1, &1, U32 & String, Value>)) -> IO(Owner<Reason> & Result<&2, &2, Error<Reason>, Value>):
  match owner:
    case Owner{socket, Lifetime{+signal, interrupt, cancellation, watcher}}:
      do IO<Owner<Reason> & Result<&2, &2, Error<Reason>, Value>>:
        reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        perform(Reason, Value, socket, Lifetime{signal, interrupt, cancellation, watcher}, signal, operation, reason)

def recv(-Reason: Data, owner: Owner<Reason>, maximum: U32) -> IO(Owner<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>):
  run(Reason, List<&2, U32>, owner, socket => TCP.recv_bytes(socket, maximum))

def send(-Reason: Data, owner: Owner<Reason>, bytes: List<&2, U32>) -> IO(Owner<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  run(Reason, Unit, owner, socket => TCP.send_bytes(socket, bytes))

# Cancel the observation, join its watcher, then retire both descriptors. A
# racing abort may already have won; joining prevents use after retirement.
def close(-Reason: Data, owner: Owner<Reason>) -> IO(Result<&2, &2, I.Error, Unit>):
  match owner:
    case Owner{socket, Lifetime{_, interrupt, cancellation, watcher}}:
      do IO<Result<&2, &2, I.Error, Unit>>:
        removed : Bool <- D.cancel(A.AbortReason<Reason>, cancellation)
        result : Result<&2, &2, I.Error, Unit> <- IO.join(Result<&2, &2, I.Error, Unit>, watcher)
        I.dispose(interrupt)
        Socket.close(socket)
        return result
