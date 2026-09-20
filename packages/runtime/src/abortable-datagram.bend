import Base
import ./abort-outcome.bend as Outcome
import ./abort.bend as Abort
import ./deferred.bend as Deferred
import ./socket-endpoint.bend as Endpoint

type Packet is Data:
  Packet{peer: Endpoint.Endpoint, truncated: Bool, bytes: List<&2, U32>}

type Error<-Reason: Data> is Data:
  Aborted{reason: Abort.AbortReason<Reason>}
  SocketError{code: U32, message: String}
  InvalidEndpoint{error: Endpoint.Error}
  CancelledWithoutReason{}

def packet(-Reason: Data, peer: Result<&2, &2, Endpoint.Error, Endpoint.Endpoint>, truncated: Bool, bytes: List<&2, U32>) -> Result<&2, &2, Error<Reason>, Packet>:
  match peer:
    case Fail{error}: Fail{InvalidEndpoint{error}}
    case Done{datagramValue}: Done{Packet{datagramValue, truncated, bytes}}

def converted(-Reason: Data, datagramValue: Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>) -> Maybe<&2, Result<&2, &2, Error<Reason>, Packet>>:
  match datagramValue:
    case None{}: None{}
    case Some{Fail{(code, message)}}: Some{Fail{SocketError{code, message}}}
    case Some{Done{((family, a, b, c, d, port, scope), truncated, bytes)}}:
      Some{packet(Reason, Endpoint.endpoint(family, a, b, c, d, port, scope), truncated, bytes)}

def selected(-Reason: Data, choice: Outcome.Outcome<Reason, Error<Reason>, Packet>) -> Result<&2, &2, Error<Reason>, Packet>:
  match choice:
    case Outcome.Aborted{why}: Fail{Aborted{why}}
    case Outcome.Completed{result}: result
    case Outcome.Cancelled{}: Fail{CancelledWithoutReason{}}

def outcome(-Reason: Data, datagramValue: Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>, abortState: Maybe<&2, Abort.AbortReason<Reason>>) -> Result<&2, &2, Error<Reason>, Packet>:
  selected(Reason, Outcome.choose(Reason, Error<Reason>, Packet, abortState, converted(Reason, datagramValue)))

def cancelForReason(-Reason: Data, handle: UDPReadCancel, abortState: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(Unit):
  match abortState:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}:
      do IO<Unit>:
        won : Bool <- UDPRead.cancel(handle)
        return Unit{}

def watch(-Reason: Data, handle: UDPReadCancel, ticket: Deferred.Ticket<Maybe<&2, Abort.AbortReason<Reason>>>) -> IO(Unit):
  do IO<Unit>:
    abortState : Maybe<&2, Abort.AbortReason<Reason>> <- Deferred.wait(Maybe<&2, Abort.AbortReason<Reason>>, ticket)
    cancelForReason(Reason, handle, abortState)

def settled(-Reason: Data, signal: Abort.AbortSignal<Reason>, pair: Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>) -> IO(Socket & Result<&2, &2, Error<Reason>, Packet>):
  match pair:
    case (socket, datagramValue):
      do IO<Socket & Result<&2, &2, Error<Reason>, Packet>>:
        abortState : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, signal)
        return (socket, outcome(Reason, datagramValue, abortState))

def observing(-Reason: Data, signal: Abort.AbortSignal<Reason>, pair: UDPRead & UDPReadCancel, observation: Deferred.Observation<Abort.AbortReason<Reason>>) -> IO(Socket & Result<&2, &2, Error<Reason>, Packet>):
  match pair observation:
    case (read, handle) Deferred.Observation{ticket, cancellation}:
      do IO<Socket & Result<&2, &2, Error<Reason>, Packet>>:
        watcher : Chan(Unit) <- IO.fork(Unit, watch(Reason, handle, ticket))
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>> <- UDPRead.wait(read)
        removed : Bool <- Deferred.cancel(Abort.AbortReason<Reason>, cancellation)
        IO.join(Unit, watcher)
        settled(Reason, signal, result)

def checked(-Reason: Data, socket: Socket, maximum: U32, +signal: Abort.AbortSignal<Reason>, abortState: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(Socket & Result<&2, &2, Error<Reason>, Packet>):
  match abortState:
    case Some{why}: IO.pure(Socket & Result<&2, &2, Error<Reason>, Packet>, (socket, Fail{Aborted{why}}))
    case None{}:
      do IO<Socket & Result<&2, &2, Error<Reason>, Packet>>:
        operation : UDPRead & UDPReadCancel <- UDPRead.new(socket, maximum)
        observation : Deferred.Observation<Abort.AbortReason<Reason>> <- Abort.observe(Reason, signal)
        observing(Reason, signal, operation, observation)

# Borrow the signal until completion. Always return the socket, retire the
# observation and join its watcher. An abort observed after packet completion
# wins at this API boundary; it may have consumed that packet, as TCP IO does.
def recv(-Reason: Data, socket: Socket, maximum: U32, +signal: Abort.AbortSignal<Reason>) -> IO(Socket & Result<&2, &2, Error<Reason>, Packet>):
  do IO<Socket & Result<&2, &2, Error<Reason>, Packet>>:
    abortState : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, signal)
    checked(Reason, socket, maximum, signal, abortState)
