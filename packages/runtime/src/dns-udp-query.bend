import Base
import ./abort.bend as Abort
import ./abortable-datagram.bend as Datagram
import ./datagram-peer.bend as Peer
import ./socket-endpoint.bend as Endpoint
import ./dns-query.bend as Request
import ./dns-message.bend as Message
import ./dns-edns.bend as Edns
import ./dns-response.bend as Response

type Reply is Data:
  Answer{message: Message.Message}
  Truncated{header: Message.Header}

type Error<-Reason: Data> is Data:
  Encoding{error: Edns.Error}
  Aborted{reason: Abort.AbortReason<Reason>}
  Opening{error: Peer.Error}
  Transport{error: Datagram.Error<Reason>}

def encode(request: Request.Request) -> Result<&2, &2, Edns.Error, List<&2, U32>>:
  Request.encode(request)

def endpoint(value: Endpoint.Endpoint) -> Response.Endpoint:
  match value:
    case Endpoint.V4{ip, port}: Response.Endpoint{Response.V4{ip}, port}
    case Endpoint.V6{ip, port, scope}: Response.Endpoint{Response.V6{ip, scope}, port}

def transaction(route: Peer.Route, request: Request.Request) -> Response.Transaction:
  match route request:
    case Peer.Route{local, remote} Request.Request{id, flags, question, _}: Response.Transaction{endpoint(local), endpoint(remote), id, (flags / 2048 % 16 : U32), question}

type Reading<-Reason: Data> is Type:
  Continue{socket: Socket}
  Finish{socket: Socket, result: Result<&2, &2, Error<Reason>, Reply>}

def inspected(-Reason: Data, socket: Socket, decision: Response.Decision) -> Reading<Reason>:
  match decision:
    case Response.Ignore{_}: Continue{socket}
    case Response.Truncated{header}: Finish{socket, Done{Truncated{header}}}
    case Response.Matched{message}: Finish{socket, Done{Answer{message}}}

def received(-Reason: Data, expected: Response.Transaction, local: Endpoint.Endpoint, pair: Socket & Result<&2, &2, Datagram.Error<Reason>, Datagram.Packet>) -> Reading<Reason>:
  match pair:
    case (socket, Fail{error}): Finish{socket, Fail{Transport{error}}}
    # DNS messages are bounded at 65535 bytes. A larger truncated datagram is
    # ignored, never parsed as a complete message or trusted for TCP fallback.
    case (socket, Done{Datagram.Packet{_, True{}, _}}): Continue{socket}
    case (socket, Done{Datagram.Packet{peer, False{}, bytes}}): inspected(Reason, socket, Response.inspect(expected, endpoint(peer), endpoint(local), bytes))

# Each iteration awaits abort-aware IO under the same borrowed signal. Noise
# cannot reset the deadline, and rejected packets are not retained in a list.
@unsafe def read(-Reason: Data, +signal: Abort.AbortSignal<Reason>, +expected: Response.Transaction, +local: Endpoint.Endpoint, state: Reading<Reason>) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match state:
    case Finish{socket, result}:
      do IO<Result<&2, &2, Error<Reason>, Reply>>:
        Socket.close(socket)
        return result
    case Continue{socket}:
      do IO<Result<&2, &2, Error<Reason>, Reply>>:
        packet : Socket & Result<&2, &2, Datagram.Error<Reason>, Datagram.Packet> <- Datagram.recv(Reason, socket, 65535, signal)
        read(Reason, signal, expected, local, received(Reason, expected, local, packet))

def sent(-Reason: Data, signal: Abort.AbortSignal<Reason>, expected: Response.Transaction, local: Endpoint.Endpoint, pair: Socket & Result<&2, &2, Datagram.Error<Reason>, Unit>) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match pair:
    case (socket, Fail{error}):
      do IO<Result<&2, &2, Error<Reason>, Reply>>:
        Socket.close(socket)
        return Fail{Transport{error}}
    case (socket, Done{_}): read(Reason, signal, expected, local, Continue{socket})

def owned(-Reason: Data, +signal: Abort.AbortSignal<Reason>, request: Request.Request, bytes: List<&2, U32>, owner: Peer.Owner) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match owner:
    case Peer.Owner{socket, Peer.Route{+local, +remote}}:
      do IO<Result<&2, &2, Error<Reason>, Reply>>:
        result : Socket & Result<&2, &2, Datagram.Error<Reason>, Unit> <- Datagram.send(Reason, socket, remote, bytes, signal)
        sent(Reason, signal, transaction(Peer.Route{local, remote}, request), local, result)

def opened(-Reason: Data, signal: Abort.AbortSignal<Reason>, request: Request.Request, bytes: List<&2, U32>, result: Result<&2, &1, Peer.Error, Peer.Owner>) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, Fail{Opening{error}})
    case Done{owner}: owned(Reason, signal, request, bytes, owner)

def checked(-Reason: Data, destination: Endpoint.Endpoint, signal: Abort.AbortSignal<Reason>, request: Request.Request, bytes: List<&2, U32>, reason: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match reason:
    case Some{why}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, Fail{Aborted{why}})
    case None{}:
      do IO<Result<&2, &2, Error<Reason>, Reply>>:
        peer : Result<&2, &1, Peer.Error, Peer.Owner> <- Peer.create(destination)
        opened(Reason, signal, request, bytes, peer)

def prepared(-Reason: Data, destination: Endpoint.Endpoint, +signal: Abort.AbortSignal<Reason>, request: Request.Request, result: Result<&2, &2, Edns.Error, List<&2, U32>>) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, Fail{Encoding{error}})
    case Done{bytes}:
      do IO<Result<&2, &2, Error<Reason>, Reply>>:
        reason : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, signal)
        checked(Reason, destination, signal, request, bytes, reason)

# One query on a dedicated numeric peer. The caller owns the attempt scope;
# return only after the socket and all per-operation abort watchers are closed.
def exchangeRequest(-Reason: Data, destination: Endpoint.Endpoint, signal: Abort.AbortSignal<Reason>, +request: Request.Request) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  prepared(Reason, destination, signal, request, encode(request))
