import Base
import ../packages/runtime/src/dns-transport.bend as Peer
import ../packages/runtime/src/dns-transport.bend as TCP
import ../packages/runtime/src/dns-message.bend as Response
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/socket.bend as SocketIO
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-tcp-connection.bend as Test
import ./socket-endpoint.bend as Show
import ./abortable-socket.bend as Check

def show(value: Response.Endpoint) -> String:
  match value:
    case Response.Endpoint{Response.V4{ip}, port}: Show.show(Endpoint.EndpointV4{ip, port})
    case Response.Endpoint{Response.V6{ip, scope}, port}: Show.show(Endpoint.EndpointV6{ip, port, scope})

def report(route: Peer.Route) -> IO(Unit):
  match route:
    case Peer.Route{local, remote}:
      do IO<Unit>:
        IO.print(show(local))
        IO.print(show(remote))

def decision(value: Response.Decision) -> String:
  match value:
    case Response.Matched{Message.Message{_, Message.Header{id, _, _, _, _, _}, _, _, _, _}}: "matched:" ++ U32.show(id)
    case Response.ResponseTruncated{_}: "truncated"
    case Response.Ignore{Response.IdMismatch{}}: "id"
    case Response.Ignore{Response.QuestionMismatch{}}: "question"
    case Response.Ignore{Response.EndpointMismatch{}}: "endpoint"
    case Response.Ignore{Response.Malformed{_}}: "malformed"
    case _: "unexpected"

def frame(+route: Peer.Route, +expected: Response.Transaction, next: TCP.Next<String>) -> IO(TCP.Connection<String>):
  match next:
    case TCP.Next{connection, Done{Some{bytes}}}:
      do IO<TCP.Connection<String>>:
        IO.print(decision(Peer.inspect(route, expected, bytes)))
        return connection
    case TCP.Next{connection, _}:
      do IO<TCP.Connection<String>>:
        Test.close(connection)
        IO.die(TCP.Connection<String>, 1, "missing response frame")

def exchange(+route: Peer.Route, connection: TCP.Connection<String>) -> IO(Unit):
  do IO<Unit>:
    report(route)
    connection : TCP.Connection<String> <- Test.send(connection, 1)
    connection : TCP.Connection<String> <- Test.send(connection, 2)
    next : TCP.Next<String> <- TCP.receiveTcpConnection(String, connection, 3)
    connection : TCP.Connection<String> <- frame(route, Peer.buildTransaction(route, 2, 0, Message.Question{Name.Name{Nil{}}, 1, 1}), next)
    next : TCP.Next<String> <- TCP.receiveTcpConnection(String, connection, 3)
    connection : TCP.Connection<String> <- frame(route, Peer.buildTransaction(route, 1, 0, Message.Question{Name.Name{Nil{}}, 1, 1}), next)
    Test.finished("eof", connection)

def opened(result: Result<&2, &1, Peer.TcpPeerError<String>, Peer.Peer<String>>) -> IO(Unit):
  match result:
    case Done{Peer.Peer{route, connection}}: exchange(route, connection)
    case Fail{_}: IO.die(Unit, 1, "peer creation failed")

def rejected(result: Result<&2, &1, Peer.TcpPeerError<String>, Peer.Peer<String>>) -> IO(Unit):
  match result:
    case Fail{Peer.Adoption{SocketIO.Aborted{Abort.Supplied{"stop"}}}}: IO.pure(Unit, Unit{})
    case Done{Peer.Peer{_, connection}}:
      do IO<Unit>:
        Test.close(connection)
        IO.die(Unit, 1, "pre-aborted peer adopted")
    case _: IO.die(Unit, 1, "wrong adoption error")

def run(abort: Bool, +controller: Abort.AbortController<String>, socket: Socket) -> IO(Unit):
  match abort:
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        result : Result<&2, &1, Peer.TcpPeerError<String>, Peer.Peer<String>> <- Peer.createTcpPeer(String, socket, Abort.signal(String, controller))
        rejected(result)
    case False{}:
      do IO<Unit>:
        result : Result<&2, &1, Peer.TcpPeerError<String>, Peer.Peer<String>> <- Peer.createTcpPeer(String, socket, Abort.signal(String, controller))
        opened(result)

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> family <> port <> Nil{}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        result : Result<&2, &1, Connect.Error<String>, Socket> <- Connect.connect(String, Test.endpoint(family), Scalar.decimal(port, 0), Abort.signal(String, controller))
        socket : Socket <- Test.connected(result)
        run(String.eq(mode, "abort"), controller, socket)
        Abort.dispose(String, controller)
        IO.print("PASS DNS TCP peer")
    case _: IO.die(Unit, 1, "expected mode family port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
