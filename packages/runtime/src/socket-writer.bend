import Base
import ./abort.bend as A
import ./abortable-socket.bend as Connection

# An affine write descriptor sharing the reader's connection and abort scope.
# Join and close every writer before closing the connection owner. Writers
# borrow its watcher; they do not register another signal observation.
type Writer<-Reason: Data> is Type:
  Writer{socket: Socket, signal: A.AbortSignal<Reason>}

def duplicated(-Reason: Data, lifetime: Connection.Lifetime<Reason>, signal: A.AbortSignal<Reason>, pair: Socket & Result<&1, &1, U32 & String, Socket>) -> Connection.Owner<Reason> & Result<&2, &1, Connection.Error<Reason>, Writer<Reason>>:
  match pair:
    case (socket, Fail{(code, message)}): (Connection.Owner{socket, lifetime}, Fail{Connection.SocketError{code, message}})
    case (socket, Done{copy}): (Connection.Owner{socket, lifetime}, Done{Writer{copy, signal}})

def checked(-Reason: Data, socket: Socket, lifetime: Connection.Lifetime<Reason>, signal: A.AbortSignal<Reason>, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Connection.Owner<Reason> & Result<&2, &1, Connection.Error<Reason>, Writer<Reason>>):
  match reason:
    case Some{why}: IO.pure(Connection.Owner<Reason> & Result<&2, &1, Connection.Error<Reason>, Writer<Reason>>, (Connection.Owner{socket, lifetime}, Fail{Connection.Aborted{why}}))
    case None{}:
      do IO<Connection.Owner<Reason> & Result<&2, &1, Connection.Error<Reason>, Writer<Reason>>>:
        pair : Socket & Result<&1, &1, U32 & String, Socket> <- Socket.duplicate(socket)
        return duplicated(Reason, lifetime, signal, pair)

# The read owner is returned on success and failure. The new descriptor pins
# the same socket independently, allowing an upload to park while reads run.
def create(-Reason: Data, owner: Connection.Owner<Reason>) -> IO(Connection.Owner<Reason> & Result<&2, &1, Connection.Error<Reason>, Writer<Reason>>):
  match owner:
    case Connection.Owner{socket, Connection.Lifetime{+signal, interrupt, cancellation, watcher}}:
      do IO<Connection.Owner<Reason> & Result<&2, &1, Connection.Error<Reason>, Writer<Reason>>>:
        reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        checked(Reason, socket, Connection.Lifetime{signal, interrupt, cancellation, watcher}, signal, reason)

def sent(-Reason: Data, +signal: A.AbortSignal<Reason>, pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Writer<Reason> & Result<&2, &2, Connection.Error<Reason>, Unit>):
  match pair:
    case (socket, result):
      do IO<Writer<Reason> & Result<&2, &2, Connection.Error<Reason>, Unit>>:
        reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        return (Writer{socket, signal}, Connection.outcome(Reason, Unit, result, reason))

def allowed(-Reason: Data, socket: Socket, signal: A.AbortSignal<Reason>, bytes: List<&2, U32>, reason: Maybe<&2, A.AbortReason<Reason>>) -> IO(Writer<Reason> & Result<&2, &2, Connection.Error<Reason>, Unit>):
  match reason:
    case Some{why}: IO.pure(Writer<Reason> & Result<&2, &2, Connection.Error<Reason>, Unit>, (Writer{socket, signal}, Fail{Connection.Aborted{why}}))
    case None{}:
      do IO<Writer<Reason> & Result<&2, &2, Connection.Error<Reason>, Unit>>:
        pair : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, bytes)
        sent(Reason, signal, pair)

def send(-Reason: Data, writer: Writer<Reason>, bytes: List<&2, U32>) -> IO(Writer<Reason> & Result<&2, &2, Connection.Error<Reason>, Unit>):
  match writer:
    case Writer{socket, +signal}:
      do IO<Writer<Reason> & Result<&2, &2, Connection.Error<Reason>, Unit>>:
        reason : Maybe<&2, A.AbortReason<Reason>> <- A.reason(Reason, signal)
        allowed(Reason, socket, signal, bytes, reason)

# Closing a writer never shuts down the shared connection or retires its signal.
def close(-Reason: Data, writer: Writer<Reason>) -> IO(Unit):
  match writer:
    case Writer{socket, _}: Socket.close(socket)
