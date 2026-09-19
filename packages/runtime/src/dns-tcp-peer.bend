import Base
import ./abort.bend as Abort
import ./abortable-socket.bend as SocketIO
import ./socket-endpoint.bend as Endpoint
import ./dns-tcp-connection.bend as TCP
import ./dns-response.bend as Response
import ./dns-message.bend as Message

# A snapshot of a connected socket's endpoints. No wildcard/requested address
# is substituted for the address actually selected by the operating system.
type Route is Data:
  Route{local: Response.Endpoint, remote: Response.Endpoint}

type Peer<-Reason: Data> is Type:
  Peer{route: Route, connection: TCP.Connection<Reason>}

type Error<-Reason: Data> is Data:
  Inspection{error: Endpoint.Error}
  Adoption{error: SocketIO.Error<Reason>}

def address(value: Endpoint.Endpoint) -> Response.Endpoint:
  match value:
    case Endpoint.V4{ip, port}: Response.Endpoint{Response.V4{ip}, port}
    case Endpoint.V6{ip, port, scope}: Response.Endpoint{Response.V6{ip, scope}, port}

def adopted(-Reason: Data, route: Route, result: Result<&2, &1, SocketIO.Error<Reason>, SocketIO.Owner<Reason>>) -> Result<&2, &1, Error<Reason>, Peer<Reason>>:
  match result:
    case Fail{error}: Fail{Adoption{error}}
    case Done{socket}: Done{Peer{route, TCP.adopt(Reason, socket)}}

def remote(-Reason: Data, local: Response.Endpoint, signal: Abort.AbortSignal<Reason>, pair: Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint>) -> IO(Result<&2, &1, Error<Reason>, Peer<Reason>>):
  match pair:
    case (socket, Fail{error}):
      do IO<Result<&2, &1, Error<Reason>, Peer<Reason>>>:
        Socket.close(socket)
        return Fail{Inspection{error}}
    case (socket, Done{at}):
      do IO<Result<&2, &1, Error<Reason>, Peer<Reason>>>:
        result : Result<&2, &1, SocketIO.Error<Reason>, SocketIO.Owner<Reason>> <- SocketIO.create(Reason, socket, signal)
        return adopted(Reason, Route{local, address(at)}, result)

def local(-Reason: Data, signal: Abort.AbortSignal<Reason>, pair: Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint>) -> IO(Result<&2, &1, Error<Reason>, Peer<Reason>>):
  match pair:
    case (socket, Fail{error}):
      do IO<Result<&2, &1, Error<Reason>, Peer<Reason>>>:
        Socket.close(socket)
        return Fail{Inspection{error}}
    case (socket, Done{at}):
      do IO<Result<&2, &1, Error<Reason>, Peer<Reason>>>:
        result : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Peer{})
        remote(Reason, address(at), signal, result)

# Consumes the connected socket, including on failure. Adoption checks retained
# abort after endpoint inspection and installs the connection's single watcher.
# Signal ownership stays with the caller until the TCP connection is closed.
def create(-Reason: Data, socket: Socket, signal: Abort.AbortSignal<Reason>) -> IO(Result<&2, &1, Error<Reason>, Peer<Reason>>):
  do IO<Result<&2, &1, Error<Reason>, Peer<Reason>>>:
    result : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
    local(Reason, signal, result)

def transaction(route: Route, id: U32, opcode: U32, question: Message.Question) -> Response.Transaction:
  match route:
    case Route{sentFrom, sentTo}: Response.Transaction{sentFrom, sentTo, id, opcode, question}

# Frame delivery remains explicit: a caller may dispatch out-of-order replies
# to several outstanding transactions without this layer discarding frames.
def inspect(route: Route, expected: Response.Transaction, wire: List<&2, U32>) -> Response.Decision:
  match route:
    case Route{receivedAt, receivedFrom}: Response.inspectStream(expected, receivedFrom, receivedAt, wire)
