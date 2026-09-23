import Base
import ./abort.bend as A
import ./deferred.bend as D
import ./url.bend as IPv4
import ./url.bend as IPv6
import ./serial-resource.bend as Resource
import ./abort.bend as Outcome
import ./ref.bend as R

type Side is Data:
  Local{}
  Peer{}

type Endpoint is Data:
  EndpointV4{address: IPv4.Address, port: U32}
  EndpointV6{address: IPv6.Ipv6Address, port: U32, scope: U32}

type EndpointError is Data:
  EndpointSocketError{code: U32, message: String}
  InvalidFamily{family: U32}

def selector(side: Side) -> U32:
  match side:
    case Local{}: 0
    case Peer{}: 1

def endpoint(family: U32, a: U32, b: U32, c: U32, d: U32, port: U32, scope: U32) -> Result<&2, &2, EndpointError, Endpoint>:
  match family:
    case 4: Done{EndpointV4{IPv4.Address{a}, port}}
    case 6: Done{EndpointV6{IPv6.Ipv6Address{a, b, c, d}, port, scope}}
    case value: Fail{InvalidFamily{value}}

def endpointValue(result: Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32>) -> Result<&2, &2, EndpointError, Endpoint>:
  match result:
    case Fail{(code, message)}: Fail{EndpointSocketError{code, message}}
    case Done{(family, a, b, c, d, port, scope)}: endpoint(family, a, b, c, d, port, scope)

def convertedEndpoint(pair: Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32>) -> Socket & Result<&2, &2, EndpointError, Endpoint>:
  match pair:
    case (socket, result): (socket, endpointValue(result))

# Observe numeric endpoint metadata without consuming, duplicating or changing
# the connection. The same affine socket is returned on success and failure.
def get(socket: Socket, side: Side) -> IO(Socket & Result<&2, &2, EndpointError, Endpoint>):
  do IO<Socket & Result<&2, &2, EndpointError, Endpoint>>:
    result : Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32> <- Socket.endpoint(socket, selector(side))
    return convertedEndpoint(result)

# A separate owned descriptor lets cancellation run while the original socket
# is held by pending IO. It pins the same connection, never a reused fd number.
type InterruptError is Data:
  InterruptError{code: U32, message: String}

type InterruptOwner is Type:
  InterruptOwner{resource: Resource.Owner<Maybe<&1, Socket>>}

type Handle is Data:
  Handle{resource: Resource.Handle<Maybe<&1, Socket>>}

def acquiredInterrupt(pair: Socket & Result<&1, &1, U32 & String, Socket>) -> IO(Socket & Result<&2, &1, InterruptError, InterruptOwner>):
  match pair:
    case (socket, Fail{(code, message)}): IO.pure(Socket & Result<&2, &1, InterruptError, InterruptOwner>, (socket, Fail{InterruptError{code, message}}))
    case (socket, Done{copy}):
      do IO<Socket & Result<&2, &1, InterruptError, InterruptOwner>>:
        resource : Resource.Owner<Maybe<&1, Socket>> <- Resource.create(Maybe<&1, Socket>, Some{copy})
        return (socket, Done{InterruptOwner{resource}})

# The caller retains the original socket even when duplication fails.
def createInterrupt(socket: Socket) -> IO(Socket & Result<&2, &1, InterruptError, InterruptOwner>):
  do IO<Socket & Result<&2, &1, InterruptError, InterruptOwner>>:
    pair : Socket & Result<&1, &1, U32 & String, Socket> <- Socket.duplicate(socket)
    acquiredInterrupt(pair)

def borrowed(pair: Resource.Owner<Maybe<&1, Socket>> & Resource.Handle<Maybe<&1, Socket>>) -> InterruptOwner & Handle:
  match pair:
    case (owner, handle): (InterruptOwner{owner}, Handle{handle})

def borrow(owner: InterruptOwner) -> InterruptOwner & Handle:
  match owner:
    case InterruptOwner{resource}: borrowed(Resource.borrow(Maybe<&1, Socket>, resource))

def interruptResult(value: Result<&1, &1, U32 & String, Unit>) -> Result<&2, &2, InterruptError, Bool>:
  match value:
    case Done{_}: Done{True{}}
    case Fail{(code, message)}: Fail{InterruptError{code, message}}

def shutdown(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Maybe<&1, Socket> & Result<&2, &2, InterruptError, Bool>):
  match pair:
    case (socket, outcome):
      do IO<Maybe<&1, Socket> & Result<&2, &2, InterruptError, Bool>>:
        Socket.close(socket)
        return (None{}, interruptResult(outcome))

def cancelOwned(value: Maybe<&1, Socket>) -> IO(Maybe<&1, Socket> & Result<&2, &2, InterruptError, Bool>):
  match value:
    case None{}: IO.pure(Maybe<&1, Socket> & Result<&2, &2, InterruptError, Bool>, (None{}, Done{False{}}))
    case Some{socket}:
      do IO<Maybe<&1, Socket> & Result<&2, &2, InterruptError, Bool>>:
        pair : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.shutdown(socket)
        shutdown(pair)

# Concurrent cancellation attempts serialize on the separate descriptor, not
# on the socket held by IO. Only the first attempt invokes shutdown; even an
# error retires the interrupt descriptor. Shutdown is destructive, not reusable
# per-operation cancellation. Buffered data may still be returned by pending IO.
def cancelInterrupt(handle: Handle) -> IO(Result<&2, &2, InterruptError, Bool>):
  match handle:
    case Handle{resource}: Resource.run(Maybe<&1, Socket>, Result<&2, &2, InterruptError, Bool>, resource, cancelOwned)

def closeCopy(value: Maybe<&1, Socket>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{socket}: Socket.close(socket)

# Join all users of the handle before disposal. This closes only our descriptor:
# normal completion must not shut down another live owner of the connection.
def dispose(owner: InterruptOwner) -> IO(Unit):
  match owner:
    case InterruptOwner{resource}:
      do IO<Unit>:
        value : Maybe<&1, Socket> <- Resource.retire(Maybe<&1, Socket>, resource)
        closeCopy(value)

type Error<-Reason: Data> is Data:
  Aborted{reason: A.AbortReason<Reason>}
  SocketError{code: U32, message: String}

# A connection-wide observation, not one watcher/duplicate per byte read.
# The caller owns the signal and keeps it alive until this owner is closed.
type Lifetime<-Reason: Data> is Type:
  Lifetime{signal: A.AbortSignal<Reason>, interrupt: InterruptOwner, cancellation: D.Cancellation<A.AbortReason<Reason>>, watcher: Chan(Result<&2, &2, InterruptError, Unit>)}

type Owner<-Reason: Data> is Type:
  Owner{socket: Socket, lifetime: Lifetime<Reason>}

def cancelled(result: Result<&2, &2, InterruptError, Bool>) -> Result<&2, &2, InterruptError, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{error}

def cancelForReasonSocket(-Reason: Data, handle: Handle, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Result<&2, &2, InterruptError, Unit>):
  match reason:
    case None{}: IO.pure(Result<&2, &2, InterruptError, Unit>, Done{Unit{}})
    case Some{_}:
      do IO<Result<&2, &2, InterruptError, Unit>>:
        result : Result<&2, &2, InterruptError, Bool> <- cancelInterrupt(handle)
        return cancelled(result)

def watchSocket(-Reason: Data, handle: Handle, ticket: D.Ticket<Maybe<&2, A.AbortReason<Reason>>>) -> IO(Result<&2, &2, InterruptError, Unit>):
  do IO<Result<&2, &2, InterruptError, Unit>>:
    reason : Maybe<&2, A.AbortReason<Reason>> <- D.wait(Maybe<&2, A.AbortReason<Reason>>, ticket)
    cancelForReasonSocket(Reason, handle, reason)

def observingSocket(-Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, pair: InterruptOwner & Handle, observation: D.Observation<A.AbortReason<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  match pair observation:
    case (owner, handle) D.Observation{ticket, cancellation}:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        watcher : Chan(Result<&2, &2, InterruptError, Unit>) <- IO.fork(Result<&2, &2, InterruptError, Unit>, watchSocket(Reason, handle, ticket))
        return Done{Owner{socket, Lifetime{signal, owner, cancellation, watcher}}}

def acquired(-Reason: Data, +signal: A.AbortSignal<Reason>, pair: Socket & Result<&2, &1, InterruptError, InterruptOwner>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  match pair:
    case (socket, Fail{InterruptError{code, message}}):
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        Socket.close(socket)
        return Fail{SocketError{code, message}}
    case (socket, Done{owner}):
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        observation : D.Observation<A.AbortReason<Reason>> <- A.observe(Reason, signal)
        observingSocket(Reason, socket, signal, borrow(owner), observation)

def checkedSocket(-Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  match reason:
    case Some{why}:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        Socket.close(socket)
        return Fail{Aborted{why}}
    case None{}:
      do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
        pair : Socket & Result<&2, &1, InterruptError, InterruptOwner> <- createInterrupt(socket)
        acquired(Reason, signal, pair)

# Takes ownership of an already connected socket, including on failure.
# Connection establishment itself is outside this scope.
def create(-Reason: Data, socket: Socket, +signal: A.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Owner<Reason>>):
  do IO<Result<&2, &1, Error<Reason>, Owner<Reason>>>:
    reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
    checkedSocket(Reason, socket, signal, reason)

def socketOutcome(-Reason: Data, -Value: Data, value: Result<&1, &1, U32 & String, Value>, reason: Maybe<&2, A.AbortReason<Reason>>) -> Result<&2, &2, Error<Reason>, Value>:
  match value reason:
    case _ Some{why}: Fail{Aborted{why}}
    case Fail{(code, message)} None{}: Fail{SocketError{code, message}}
    case Done{value} None{}: Done{value}

def received(-Reason: Data, -Value: Data, lifetime: Lifetime<Reason>, signal: A.AbortSignal<Reason>, pair: Socket & Result<&1, &1, U32 & String, Value>) -> IO(Owner<Reason> & Result<&2, &2, Error<Reason>, Value>):
  match pair:
    case (socket, value):
      do IO<Owner<Reason> & Result<&2, &2, Error<Reason>, Value>>:
        reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        return (Owner{socket, lifetime}, socketOutcome(Reason, Value, value, reason))

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

def recvSocket(-Reason: Data, owner: Owner<Reason>, maximum: U32) -> IO(Owner<Reason> & Result<&2, &2, Error<Reason>, List<&2, U32>>):
  run(Reason, List<&2, U32>, owner, socket => TCP.recv_bytes(socket, maximum))

def sendSocket(-Reason: Data, owner: Owner<Reason>, bytes: List<&2, U32>) -> IO(Owner<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  run(Reason, Unit, owner, socket => TCP.send_bytes(socket, bytes))

# Cancel the observation, join its watcher, then retire both descriptors. A
# racing abort may already have won; joining prevents use after retirement.
def close(-Reason: Data, owner: Owner<Reason>) -> IO(Result<&2, &2, InterruptError, Unit>):
  match owner:
    case Owner{socket, Lifetime{_, interrupt, cancellation, watcher}}:
      do IO<Result<&2, &2, InterruptError, Unit>>:
        removed : Bool <- D.cancel(A.AbortReason<Reason>, cancellation)
        result : Result<&2, &2, InterruptError, Unit> <- IO.join(Result<&2, &2, InterruptError, Unit>, watcher)
        dispose(interrupt)
        Socket.close(socket)
        return result

type Address is Data:
  V4{value: IPv4.Address}
  V6{value: IPv6.Ipv6Address, scope: U32}

def begin(address: Address, port: U32) -> IO(Result<&1, &1, U32 & String, Connect & ConnectCancel>):
  match address:
    case V4{IPv4.Address{value}}: Connect.ipv4(value, port)
    case V6{IPv6.Ipv6Address{a, b, c, d}, scope}: Connect.ipv6(a, b, c, d, port, scope)

def cancel(-Reason: Data, handle: ConnectCancel, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Unit):
  match reason:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}:
      do IO<Unit>:
        won : Bool <- Connect.cancel(handle)
        return Unit{}

def watch(-Reason: Data, ticket: D.Ticket<Maybe<&2, A.AbortReason<Reason>>>, handle: ConnectCancel) -> IO(Unit):
  do IO<Unit>:
    reason : Maybe<&2, A.AbortReason<Reason>> <- D.wait(Maybe<&2, A.AbortReason<Reason>>, ticket)
    cancel(Reason, handle, reason)

# As with abortable socket reads, inspect the retained reason after settlement.
# If abort was observed by this final check, even a completed socket is closed
# before returning the reason. Abort after this check can follow success.
def outcome(-Reason: Data, result: Result<&1, &1, U32 & String, Socket>, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  match result reason:
    case Done{socket} None{}: IO.pure(Result<&2, &1, Error<Reason>, Socket>, Done{socket})
    case Fail{(code, message)} None{}: IO.pure(Result<&2, &1, Error<Reason>, Socket>, Fail{SocketError{code, message}})
    case Done{socket} Some{why}:
      do IO<Result<&2, &1, Error<Reason>, Socket>>:
        Socket.close(socket)
        return Fail{Aborted{why}}
    case Fail{_} Some{why}: IO.pure(Result<&2, &1, Error<Reason>, Socket>, Fail{Aborted{why}})

def settled(-Reason: Data, result: Result<&1, &1, U32 & String, Socket>, signal: A.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  do IO<Result<&2, &1, Error<Reason>, Socket>>:
    reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
    outcome(Reason, result, reason)

def finish(-Reason: Data, result: Result<&1, &1, U32 & String, Socket>, cancellation: D.Cancellation<A.AbortReason<Reason>>, watcher: Chan(Unit), signal: A.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  do IO<Result<&2, &1, Error<Reason>, Socket>>:
    removed : Bool <- D.cancel(A.AbortReason<Reason>, cancellation)
    IO.join(Unit, watcher)
    settled(Reason, result, signal)

def started(-Reason: Data, result: Result<&1, &1, U32 & String, Connect & ConnectCancel>, observation: D.Observation<A.AbortReason<Reason>>, signal: A.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  match result observation:
    case Fail{error} D.Observation{ticket, cancellation}:
      do IO<Result<&2, &1, Error<Reason>, Socket>>:
        removed : Bool <- D.cancel(A.AbortReason<Reason>, cancellation)
        unused : Maybe<&2, A.AbortReason<Reason>> <- D.wait(Maybe<&2, A.AbortReason<Reason>>, ticket)
        settled(Reason, Fail{error}, signal)
    case Done{(owner, handle)} D.Observation{ticket, cancellation}:
      do IO<Result<&2, &1, Error<Reason>, Socket>>:
        watcher : Chan(Unit) <- IO.fork(Unit, watch(Reason, ticket, handle))
        result : Result<&1, &1, U32 & String, Socket> <- Connect.wait(owner)
        finish(Reason, result, cancellation, watcher, signal)

def checkedConnect(-Reason: Data, address: Address, port: U32, +signal: A.AbortSignal<Reason>, check: Result<&2, &2, A.AbortReason<Reason>, Unit>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  match check:
    case Fail{why}: IO.pure(Result<&2, &1, Error<Reason>, Socket>, Fail{Aborted{why}})
    case Done{_}:
      do IO<Result<&2, &1, Error<Reason>, Socket>>:
        observation : D.Observation<A.AbortReason<Reason>> <- A.observe(Reason, signal)
        result : Result<&1, &1, U32 & String, Connect & ConnectCancel> <- begin(address, port)
        started(Reason, result, observation, signal)

# The signal remains caller-owned. Every return retires the attempt and drains
# its observation/watcher. There is no detached connection or per-poll watcher.
def connect(-Reason: Data, address: Address, port: U32, +signal: A.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Socket>):
  do IO<Result<&2, &1, Error<Reason>, Socket>>:
    check : Result<&2, &2, A.AbortReason<Reason>, Unit> <- A.throwIfAborted(Reason, signal)
    checkedConnect(Reason, address, port, signal, check)

type Packet is Data:
  Packet{peer: Endpoint, truncated: Bool, bytes: List<&2, U32>}

type DatagramError<-Reason: Data> is Data:
  DatagramAborted{reason: A.AbortReason<Reason>}
  DatagramSocketError{code: U32, message: String}
  InvalidEndpoint{error: EndpointError}
  CancelledWithoutReason{}

def packet(-Reason: Data, peer: Result<&2, &2, EndpointError, Endpoint>, truncated: Bool, bytes: List<&2, U32>) -> Result<&2, &2, DatagramError<Reason>, Packet>:
  match peer:
    case Fail{error}: Fail{InvalidEndpoint{error}}
    case Done{datagramValue}: Done{Packet{datagramValue, truncated, bytes}}

def converted(-Reason: Data, datagramValue: Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>) -> Maybe<&2, Result<&2, &2, DatagramError<Reason>, Packet>>:
  match datagramValue:
    case None{}: None{}
    case Some{Fail{(code, message)}}: Some{Fail{DatagramSocketError{code, message}}}
    case Some{Done{((family, a, b, c, d, port, scope), truncated, bytes)}}:
      Some{packet(Reason, endpoint(family, a, b, c, d, port, scope), truncated, bytes)}

def selected(-Reason: Data, -Value: Data, choice: Outcome.Outcome<Reason, DatagramError<Reason>, Value>) -> Result<&2, &2, DatagramError<Reason>, Value>:
  match choice:
    case Outcome.Aborted{why}: Fail{DatagramAborted{why}}
    case Outcome.Completed{result}: result
    case Outcome.Cancelled{}: Fail{CancelledWithoutReason{}}

def datagramOutcome(-Reason: Data, datagramValue: Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>, abortState: Maybe<&2, A.AbortReason<Reason>>) -> Result<&2, &2, DatagramError<Reason>, Packet>:
  selected(Reason, Packet, Outcome.choose(Reason, DatagramError<Reason>, Packet, abortState, converted(Reason, datagramValue)))

def cancelForReason(-Reason: Data, handle: UDPReadCancel, abortState: Maybe<&2, A.AbortReason<Reason>>) -> IO(Unit):
  match abortState:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}:
      do IO<Unit>:
        won : Bool <- UDPRead.cancel(handle)
        return Unit{}

def watchDatagram(-Reason: Data, handle: UDPReadCancel, ticket: D.Ticket<Maybe<&2, A.AbortReason<Reason>>>) -> IO(Unit):
  do IO<Unit>:
    abortState : Maybe<&2, A.AbortReason<Reason>> <- D.wait(Maybe<&2, A.AbortReason<Reason>>, ticket)
    cancelForReason(Reason, handle, abortState)

def settledDatagram(-Reason: Data, signal: A.AbortSignal<Reason>, pair: Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>) -> IO(Socket & Result<&2, &2, DatagramError<Reason>, Packet>):
  match pair:
    case (socket, datagramValue):
      do IO<Socket & Result<&2, &2, DatagramError<Reason>, Packet>>:
        abortState : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        return (socket, datagramOutcome(Reason, datagramValue, abortState))

def observing(-Reason: Data, signal: A.AbortSignal<Reason>, pair: UDPRead & UDPReadCancel, observation: D.Observation<A.AbortReason<Reason>>) -> IO(Socket & Result<&2, &2, DatagramError<Reason>, Packet>):
  match pair observation:
    case (read, handle) D.Observation{ticket, cancellation}:
      do IO<Socket & Result<&2, &2, DatagramError<Reason>, Packet>>:
        watcher : Chan(Unit) <- IO.fork(Unit, watchDatagram(Reason, handle, ticket))
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>> <- UDPRead.wait(read)
        removed : Bool <- D.cancel(A.AbortReason<Reason>, cancellation)
        IO.join(Unit, watcher)
        settledDatagram(Reason, signal, result)

def checkedDatagram(-Reason: Data, socket: Socket, maximum: U32, +signal: A.AbortSignal<Reason>, abortState: Maybe<&2, A.AbortReason<Reason>>) -> IO(Socket & Result<&2, &2, DatagramError<Reason>, Packet>):
  match abortState:
    case Some{why}: IO.pure(Socket & Result<&2, &2, DatagramError<Reason>, Packet>, (socket, Fail{DatagramAborted{why}}))
    case None{}:
      do IO<Socket & Result<&2, &2, DatagramError<Reason>, Packet>>:
        operation : UDPRead & UDPReadCancel <- UDPRead.new(socket, maximum)
        observation : D.Observation<A.AbortReason<Reason>> <- A.observe(Reason, signal)
        observing(Reason, signal, operation, observation)

# Borrow the signal until completion. Always return the socket, retire the
# observation and join its watcher. An abort observed after packet completion
# wins at this API boundary; it may have consumed that packet, as TCP IO does.
def recv(-Reason: Data, socket: Socket, maximum: U32, +signal: A.AbortSignal<Reason>) -> IO(Socket & Result<&2, &2, DatagramError<Reason>, Packet>):
  do IO<Socket & Result<&2, &2, DatagramError<Reason>, Packet>>:
    abortState : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
    checkedDatagram(Reason, socket, maximum, signal, abortState)

def writeOperation(socket: Socket, destination: Endpoint, bytes: List<&2, U32>) -> IO(UDPWrite & UDPWriteCancel):
  match destination:
    case EndpointV4{IPv4.Address{address}, port}: UDPWrite.new(socket, 4, address, 0, 0, 0, port, 0, bytes)
    case EndpointV6{IPv6.Ipv6Address{a, b, c, d}, port, scope}: UDPWrite.new(socket, 6, a, b, c, d, port, scope, bytes)

def writeConverted(-Reason: Data, value: Maybe<&1, Result<&1, &1, U32 & String, Unit>>) -> Maybe<&2, Result<&2, &2, DatagramError<Reason>, Unit>>:
  match value:
    case None{}: None{}
    case Some{Fail{(code, message)}}: Some{Fail{DatagramSocketError{code, message}}}
    case Some{Done{unit}}: Some{Done{unit}}

def cancelWriteForReason(-Reason: Data, handle: UDPWriteCancel, abortState: Maybe<&2, A.AbortReason<Reason>>) -> IO(Unit):
  match abortState:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}:
      do IO<Unit>:
        won : Bool <- UDPWrite.cancel(handle)
        return Unit{}

def watchWrite(-Reason: Data, handle: UDPWriteCancel, ticket: D.Ticket<Maybe<&2, A.AbortReason<Reason>>>) -> IO(Unit):
  do IO<Unit>:
    abortState : Maybe<&2, A.AbortReason<Reason>> <- D.wait(Maybe<&2, A.AbortReason<Reason>>, ticket)
    cancelWriteForReason(Reason, handle, abortState)

def writeSettled(-Reason: Data, signal: A.AbortSignal<Reason>, pair: Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>>) -> IO(Socket & Result<&2, &2, DatagramError<Reason>, Unit>):
  match pair:
    case (socket, value):
      do IO<Socket & Result<&2, &2, DatagramError<Reason>, Unit>>:
        abortState : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        return (socket, selected(Reason, Unit, Outcome.choose(Reason, DatagramError<Reason>, Unit, abortState, writeConverted(Reason, value))))

def writeObserving(-Reason: Data, signal: A.AbortSignal<Reason>, pair: UDPWrite & UDPWriteCancel, observation: D.Observation<A.AbortReason<Reason>>) -> IO(Socket & Result<&2, &2, DatagramError<Reason>, Unit>):
  match pair observation:
    case (write, handle) D.Observation{ticket, cancellation}:
      do IO<Socket & Result<&2, &2, DatagramError<Reason>, Unit>>:
        watcher : Chan(Unit) <- IO.fork(Unit, watchWrite(Reason, handle, ticket))
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, Unit>> <- UDPWrite.wait(write)
        removed : Bool <- D.cancel(A.AbortReason<Reason>, cancellation)
        IO.join(Unit, watcher)
        writeSettled(Reason, signal, result)

def writeChecked(-Reason: Data, socket: Socket, destination: Endpoint, bytes: List<&2, U32>, +signal: A.AbortSignal<Reason>, abortState: Maybe<&2, A.AbortReason<Reason>>) -> IO(Socket & Result<&2, &2, DatagramError<Reason>, Unit>):
  match abortState:
    case Some{why}: IO.pure(Socket & Result<&2, &2, DatagramError<Reason>, Unit>, (socket, Fail{DatagramAborted{why}}))
    case None{}:
      do IO<Socket & Result<&2, &2, DatagramError<Reason>, Unit>>:
        operation : UDPWrite & UDPWriteCancel <- writeOperation(socket, destination, bytes)
        observation : D.Observation<A.AbortReason<Reason>> <- A.observe(Reason, signal)
        writeObserving(Reason, signal, operation, observation)

# Borrow the signal, return the socket on every outcome and join the observer.
# A retained abort wins at this boundary even if transmission already completed;
# callers must not interpret an abort result as proof of non-delivery.
def send(-Reason: Data, socket: Socket, destination: Endpoint, bytes: List<&2, U32>, +signal: A.AbortSignal<Reason>) -> IO(Socket & Result<&2, &2, DatagramError<Reason>, Unit>):
  do IO<Socket & Result<&2, &2, DatagramError<Reason>, Unit>>:
    abortState : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
    writeChecked(Reason, socket, destination, bytes, signal, abortState)

# An affine write descriptor sharing the reader's connection and abort scope.
# Join and close every writer before closing the connection owner. Writers
# borrow its watcher; they do not register another signal observation.
type Writer<-Reason: Data> is Type:
  Writer{socket: Socket, signal: A.AbortSignal<Reason>}

def duplicated(-Reason: Data, lifetime: Lifetime<Reason>, signal: A.AbortSignal<Reason>, pair: Socket & Result<&1, &1, U32 & String, Socket>) -> Owner<Reason> & Result<&2, &1, Error<Reason>, Writer<Reason>>:
  match pair:
    case (socket, Fail{(code, message)}): (Owner{socket, lifetime}, Fail{SocketError{code, message}})
    case (socket, Done{copy}): (Owner{socket, lifetime}, Done{Writer{copy, signal}})

def checkedWriter(-Reason: Data, socket: Socket, lifetime: Lifetime<Reason>, signal: A.AbortSignal<Reason>, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Owner<Reason> & Result<&2, &1, Error<Reason>, Writer<Reason>>):
  match reason:
    case Some{why}: IO.pure(Owner<Reason> & Result<&2, &1, Error<Reason>, Writer<Reason>>, (Owner{socket, lifetime}, Fail{Aborted{why}}))
    case None{}:
      do IO<Owner<Reason> & Result<&2, &1, Error<Reason>, Writer<Reason>>>:
        pair : Socket & Result<&1, &1, U32 & String, Socket> <- Socket.duplicate(socket)
        return duplicated(Reason, lifetime, signal, pair)

# The read owner is returned on success and failure. The new descriptor pins
# the same socket independently, allowing an upload to park while reads run.
def createWriter(-Reason: Data, owner: Owner<Reason>) -> IO(Owner<Reason> & Result<&2, &1, Error<Reason>, Writer<Reason>>):
  match owner:
    case Owner{socket, Lifetime{+signal, interrupt, cancellation, watcher}}:
      do IO<Owner<Reason> & Result<&2, &1, Error<Reason>, Writer<Reason>>>:
        reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        checkedWriter(Reason, socket, Lifetime{signal, interrupt, cancellation, watcher}, signal, reason)

def sent(-Reason: Data, +signal: A.AbortSignal<Reason>, pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match pair:
    case (socket, result):
      do IO<Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>>:
        reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        return (Writer{socket, signal}, socketOutcome(Reason, Unit, result, reason))

def allowed(-Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, bytes: List<&2, U32>, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match reason:
    case Some{why}: IO.pure(Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>, (Writer{socket, signal}, Fail{Aborted{why}}))
    case None{}:
      do IO<Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>>:
        pair : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, bytes)
        sent(Reason, signal, pair)

def sendWriter(-Reason: Data, writer: Writer<Reason>, bytes: List<&2, U32>) -> IO(Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>):
  match writer:
    case Writer{socket, +signal}:
      do IO<Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>>:
        reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        allowed(Reason, socket, signal, bytes, reason)

# Closing a writer never shuts down the shared connection or retires its signal.
def closeWriter(-Reason: Data, writer: Writer<Reason>) -> IO(Unit):
  match writer:
    case Writer{socket, _}: Socket.close(socket)

# One upload task borrows the connection interrupt until stop joins it.
# Stopping competes atomically with write completion: an intentional stop must
# not turn the shutdown-induced write error into a failed response.
type State<-Reason: Data> is Data:
  Active{}
  Settled{result: Result<&2, &2, Error<Reason>, Unit>, reported: Bool}
  Stopped{}

type UploadError<-Reason: Data> is Data:
  WriteFailure{error: Error<Reason>, cleanup: Maybe<&2, InterruptError>}
  InterruptFailure{error: InterruptError}

type UploadOwner<-Reason: Data> is Type:
  UploadOwner{state: R.Ref<State<Reason>>, interrupt: Handle, task: Chan(Result<&2, &2, InterruptError, Unit>)}

def borrowedUpload(-Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, cancellation: D.Cancellation<A.AbortReason<Reason>>, watcher: Chan(Result<&2, &2, InterruptError, Unit>), pair: InterruptOwner & Handle) -> Owner<Reason> & Handle:
  match pair:
    case (owner, handle): (Owner{socket, Lifetime{signal, owner, cancellation, watcher}}, handle)

# Borrowing never duplicates the affine interrupt owner.
def borrowConnection(-Reason: Data, owner: Owner<Reason>) -> Owner<Reason> & Handle:
  match owner:
    case Owner{socket, Lifetime{signal, owner, cancellation, watcher}}:
      borrowedUpload(Reason, socket, signal, cancellation, watcher, borrow(owner))

def settle(-Reason: Data, state: State<Reason>, result: Result<&2, &2, Error<Reason>, Unit>) -> State<Reason> & Bool:
  match state result:
    case Active{} Done{_}: (Settled{Done{Unit{}}, False{}}, False{})
    case Active{} Fail{+error}: (Settled{Fail{error}, False{}}, True{})
    case previous _: (previous, False{})

def wake(handle: Handle, needed: Bool) -> IO(Result<&2, &2, InterruptError, Unit>):
  match needed:
    case False{}: IO.pure(Result<&2, &2, InterruptError, Unit>, Done{Unit{}})
    case True{}:
      do IO<Result<&2, &2, InterruptError, Unit>>:
        result : Result<&2, &2, InterruptError, Bool> <- cancelInterrupt(handle)
        return cancelled(result)

def finished(-Reason: Data, state: R.Ref<State<Reason>>, handle: Handle, pair: Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>) -> IO(Result<&2, &2, InterruptError, Unit>):
  match pair:
    case (writer, result):
      do IO<Result<&2, &2, InterruptError, Unit>>:
        failed : Bool <- R.modify(State<Reason>, Bool, state, previous => settle(Reason, previous, result))
        closeWriter(Reason, writer)
        wake(handle, failed)

def body(-Reason: Data, +state: R.Ref<State<Reason>>, handle: Handle, bytes: List<&2, U32>, pair: Writer<Reason> & Result<&2, &2, Error<Reason>, Unit>) -> IO(Result<&2, &2, InterruptError, Unit>):
  match pair:
    case (writer, Fail{error}): finished(Reason, state, handle, (writer, Fail{error}))
    case (writer, Done{_}):
      do IO<Result<&2, &2, InterruptError, Unit>>:
        result : Writer<Reason> & Result<&2, &2, Error<Reason>, Unit> <- sendWriter(Reason, writer, bytes)
        finished(Reason, state, handle, result)

def runUpload(-Reason: Data, writer: Writer<Reason>, state: R.Ref<State<Reason>>, handle: Handle, head: List<&2, U32>, bytes: List<&2, U32>) -> IO(Result<&2, &2, InterruptError, Unit>):
  do IO<Result<&2, &2, InterruptError, Unit>>:
    result : Writer<Reason> & Result<&2, &2, Error<Reason>, Unit> <- sendWriter(Reason, writer, head)
    body(Reason, state, handle, bytes, result)

def launch(-Reason: Data, writer: Writer<Reason>, head: List<&2, U32>, bytes: List<&2, U32>, pair: Owner<Reason> & Handle) -> IO(Owner<Reason> & Result<&2, &1, Error<Reason>, UploadOwner<Reason>>):
  match pair:
    case (connection, +handle):
      do IO<Owner<Reason> & Result<&2, &1, Error<Reason>, UploadOwner<Reason>>>:
        +state : R.Ref<State<Reason>> <- R.new(State<Reason>, Active{})
        task : Chan(Result<&2, &2, InterruptError, Unit>) <- IO.fork(Result<&2, &2, InterruptError, Unit>, runUpload(Reason, writer, state, handle, head, bytes))
        return (connection, Done{UploadOwner{state, handle, task}})

def created(-Reason: Data, head: List<&2, U32>, bytes: List<&2, U32>, pair: Owner<Reason> & Result<&2, &1, Error<Reason>, Writer<Reason>>) -> IO(Owner<Reason> & Result<&2, &1, Error<Reason>, UploadOwner<Reason>>):
  match pair:
    case (connection, Fail{error}): IO.pure(Owner<Reason> & Result<&2, &1, Error<Reason>, UploadOwner<Reason>>, (connection, Fail{error}))
    case (connection, Done{writer}): launch(Reason, writer, head, bytes, borrowConnection(Reason, connection))

def startUpload(-Reason: Data, connection: Owner<Reason>, head: List<&2, U32>, bytes: List<&2, U32>) -> IO(Owner<Reason> & Result<&2, &1, Error<Reason>, UploadOwner<Reason>>):
  do IO<Owner<Reason> & Result<&2, &1, Error<Reason>, UploadOwner<Reason>>>:
    pair : Owner<Reason> & Result<&2, &1, Error<Reason>, Writer<Reason>> <- createWriter(Reason, connection)
    created(Reason, head, bytes, pair)

def observe(-Reason: Data, state: State<Reason>) -> State<Reason> & Maybe<&2, Error<Reason>>:
  match state:
    case Settled{Fail{+error}, _}: (Settled{Fail{error}, True{}}, Some{error})
    case previous: (previous, None{})

def checkUpload(-Reason: Data, owner: UploadOwner<Reason>) -> IO(UploadOwner<Reason> & Maybe<&2, Error<Reason>>):
  match owner:
    case UploadOwner{+state, interrupt, task}:
      do IO<UploadOwner<Reason> & Maybe<&2, Error<Reason>>>:
        error : Maybe<&2, Error<Reason>> <- R.modify(State<Reason>, Maybe<&2, Error<Reason>>, state, value => observe(Reason, value))
        return (UploadOwner{state, interrupt, task}, error)

def stopping(-Reason: Data, state: State<Reason>) -> State<Reason> & Bool:
  match state:
    case Active{}: (Stopped{}, True{})
    case previous: (previous, False{})

def uploadOutcome(-Reason: Data, state: State<Reason>, cleanup: Result<&2, &2, InterruptError, Unit>) -> Result<&2, &2, UploadError<Reason>, Unit>:
  match state cleanup:
    case Settled{Fail{error}, False{}} Done{_}: Fail{WriteFailure{error, None{}}}
    case Settled{Fail{error}, False{}} Fail{cleanup}: Fail{WriteFailure{error, Some{cleanup}}}
    case _ Fail{error}: Fail{InterruptFailure{error}}
    case _ Done{_}: Done{Unit{}}

def combined(left: Result<&2, &2, InterruptError, Unit>, right: Result<&2, &2, InterruptError, Unit>) -> Result<&2, &2, InterruptError, Unit>:
  match left:
    case Fail{error}: Fail{error}
    case Done{_}: right

# Call before retiring the connection. A successful completed upload needs no
# shutdown; an unfinished one is interrupted. Joining precedes state disposal.
def stop(-Reason: Data, owner: UploadOwner<Reason>) -> IO(Result<&2, &2, UploadError<Reason>, Unit>):
  match owner:
    case UploadOwner{+state, interrupt, task}:
      do IO<Result<&2, &2, UploadError<Reason>, Unit>>:
        needed : Bool <- R.modify(State<Reason>, Bool, state, value => stopping(Reason, value))
        stopped : Result<&2, &2, InterruptError, Unit> <- wake(interrupt, needed)
        joined : Result<&2, &2, InterruptError, Unit> <- IO.join(Result<&2, &2, InterruptError, Unit>, task)
        value : State<Reason> <- R.dispose(State<Reason>, state)
        return uploadOutcome(Reason, value, combined(stopped, joined))

# Keep-alive support: whether a read would not block (data, a peer close or an
# error is pending), and whether an upload finished successfully. An error
# from the check counts as readable so the caller discards the connection.
def readableResult(result: Result<&1, &1, U32 & String, Bool>) -> Bool:
  match result:
    case Done{value}: value
    case Fail{_}: True{}

def readableOwned(-Reason: Data, lifetime: Lifetime<Reason>, pair: Socket & Result<&1, &1, U32 & String, Bool>) -> Owner<Reason> & Bool:
  match pair:
    case (socket, result): (Owner{socket, lifetime}, readableResult(result))

def readable(-Reason: Data, owner: Owner<Reason>) -> IO(Owner<Reason> & Bool):
  match owner:
    case Owner{socket, lifetime}:
      do IO<Owner<Reason> & Bool>:
        pair : Socket & Result<&1, &1, U32 & String, Bool> <- TCP.readable(socket)
        return readableOwned(Reason, lifetime, pair)

def settledDone(-Reason: Data, state: State<Reason>) -> Bool:
  match state:
    case Settled{Done{_}, _}: True{}
    case _: False{}

def uploadSettled(-Reason: Data, owner: UploadOwner<Reason>) -> IO(UploadOwner<Reason> & Bool):
  match owner:
    case UploadOwner{+state, interrupt, task}:
      do IO<UploadOwner<Reason> & Bool>:
        current : State<Reason> <- R.read(State<Reason>, state)
        return (UploadOwner{state, interrupt, task}, settledDone(Reason, current))
