import Base
import ./abort.bend as Abort
import ./deferred.bend as Deferred
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6

type Address is Data:
  V4{value: IPv4.Address}
  V6{value: IPv6.Address, scope: U32}

type Error<-Reason: Data> is Data:
  Aborted{reason: Abort.AbortReason<Reason>}
  SocketError{code: U32, message: String}

def begin(address: Address, port: U32) -> IO(Result<&1, &1, U32 & String, Connect & ConnectCancel>):
  match address:
    case V4{IPv4.Address{value}}: Connect.ipv4(value, port)
    case V6{IPv6.Address{a, b, c, d}, scope}: Connect.ipv6(a, b, c, d, port, scope)

def cancel(-Reason: Data, handle: ConnectCancel, reason: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(Unit):
  match reason:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}:
      do IO<Unit>:
        won : Bool <- Connect.cancel(handle)
        return Unit{}

def watch(-Reason: Data, ticket: Deferred.Ticket<Maybe<&2, Abort.AbortReason<Reason>>>, handle: ConnectCancel) -> IO(Unit):
  do IO<Unit>:
    reason : Maybe<&2, Abort.AbortReason<Reason>> <- Deferred.wait(Maybe<&2, Abort.AbortReason<Reason>>, ticket)
    cancel(Reason, handle, reason)

# As with abortable socket reads, inspect the retained reason after settlement.
# If abort was observed by this final check, even a completed socket is closed
# before returning the reason. Abort after this check can follow success.
def outcome(-Reason: Data, result: Result<&1, &1, U32 & String, Socket>, reason: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  match result reason:
    case Done{socket} None{}: IO.pure(Result<&2, &1, Error<Reason>, Socket>, Done{socket})
    case Fail{(code, message)} None{}: IO.pure(Result<&2, &1, Error<Reason>, Socket>, Fail{SocketError{code, message}})
    case Done{socket} Some{why}:
      do IO<Result<&2, &1, Error<Reason>, Socket>>:
        Socket.close(socket)
        return Fail{Aborted{why}}
    case Fail{_} Some{why}: IO.pure(Result<&2, &1, Error<Reason>, Socket>, Fail{Aborted{why}})

def settled(-Reason: Data, result: Result<&1, &1, U32 & String, Socket>, signal: Abort.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  do IO<Result<&2, &1, Error<Reason>, Socket>>:
    reason : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, signal)
    outcome(Reason, result, reason)

def finish(-Reason: Data, result: Result<&1, &1, U32 & String, Socket>, cancellation: Deferred.Cancellation<Abort.AbortReason<Reason>>, watcher: Chan(Unit), signal: Abort.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  do IO<Result<&2, &1, Error<Reason>, Socket>>:
    removed : Bool <- Deferred.cancel(Abort.AbortReason<Reason>, cancellation)
    IO.join(Unit, watcher)
    settled(Reason, result, signal)

def started(-Reason: Data, result: Result<&1, &1, U32 & String, Connect & ConnectCancel>, observation: Deferred.Observation<Abort.AbortReason<Reason>>, signal: Abort.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  match result observation:
    case Fail{error} Deferred.Observation{ticket, cancellation}:
      do IO<Result<&2, &1, Error<Reason>, Socket>>:
        removed : Bool <- Deferred.cancel(Abort.AbortReason<Reason>, cancellation)
        unused : Maybe<&2, Abort.AbortReason<Reason>> <- Deferred.wait(Maybe<&2, Abort.AbortReason<Reason>>, ticket)
        settled(Reason, Fail{error}, signal)
    case Done{(owner, handle)} Deferred.Observation{ticket, cancellation}:
      do IO<Result<&2, &1, Error<Reason>, Socket>>:
        watcher : Chan(Unit) <- IO.fork(Unit, watch(Reason, ticket, handle))
        result : Result<&1, &1, U32 & String, Socket> <- Connect.wait(owner)
        finish(Reason, result, cancellation, watcher, signal)

def checked(-Reason: Data, address: Address, port: U32, +signal: Abort.AbortSignal<Reason>, check: Result<&2, &2, Abort.AbortReason<Reason>, Unit>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  match check:
    case Fail{why}: IO.pure(Result<&2, &1, Error<Reason>, Socket>, Fail{Aborted{why}})
    case Done{_}:
      do IO<Result<&2, &1, Error<Reason>, Socket>>:
        observation : Deferred.Observation<Abort.AbortReason<Reason>> <- Abort.observe(Reason, signal)
        result : Result<&1, &1, U32 & String, Connect & ConnectCancel> <- begin(address, port)
        started(Reason, result, observation, signal)

# The signal remains caller-owned. Every return retires the attempt and drains
# its observation/watcher. There is no detached connection or per-poll watcher.
def connect(-Reason: Data, address: Address, port: U32, +signal: Abort.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  do IO<Result<&2, &1, Error<Reason>, Socket>>:
    check : Result<&2, &2, Abort.AbortReason<Reason>, Unit> <- Abort.throwIfAborted(Reason, signal)
    checked(Reason, address, port, signal, check)
