import Base
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/test/utf8-runner.bend as Scalar

def assertTrue(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "endpoint contract failed")

def show(value: Endpoint.Endpoint) -> String:
  match value:
    case Endpoint.EndpointV4{IPv4.Address{a}, port}: "4," ++ U32.show(a) ++ ",0,0,0," ++ U32.show(port) ++ ",0"
    case Endpoint.EndpointV6{IPv6.Address{a,b,c,d},port,scope}: "6," ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ "," ++ U32.show(port) ++ "," ++ U32.show(scope)

def observed(pair: Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint>) -> IO(Socket):
  match pair:
    case (socket, Done{value}):
      do IO<Socket>:
        IO.print(show(value))
        return socket
    case (socket, Fail{_}):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "endpoint query failed")

def invalid(pair: Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32>) -> IO(Socket):
  match pair:
    case (socket, Fail{(code, _)}):
      do IO<Socket>:
        assertTrue(U32.is_eq(code, 22))
        return socket
    case (socket, Done{_}):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "invalid selector accepted")

def sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Socket):
  match pair:
    case (socket, Done{_}): IO.pure(Socket, socket)
    case (socket, Fail{_}):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "send failed")

def received(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Socket):
  match pair:
    case (socket, Done{43 <> Nil{}}): IO.pure(Socket, socket)
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "receive failed")

def repeat(count: Nat, socket: Socket) -> IO(Unit):
  match count:
    case Zero{}:
      do IO<Unit>:
        Socket.close(socket)
        IO.print("PASS socket endpoint")
    case Succ{rest}:
      do IO<Unit>:
        local : Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
        socket : Socket <- observed(local)
        peer : Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Peer{})
        socket : Socket <- observed(peer)
        rejected : Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32> <- Socket.endpoint(socket, 2)
        socket : Socket <- invalid(rejected)
        write : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, 42 <> Nil{})
        socket : Socket <- sent(write)
        read : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 1)
        socket : Socket <- received(read)
        repeat(rest, socket)

def unconnectedResult(code: U32, pair: Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint>) -> IO(Socket):
  match pair:
    case (socket, Fail{Endpoint.EndpointSocketError{actual, _}}):
      do IO<Socket>:
        assertTrue(U32.is_eq(code, actual))
        return socket
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "expected unconnected peer error")

def udp(code: U32) -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- IO.try(Socket, UDP.bind(0))
    local : Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
    socket : Socket <- observed(local)
    peer : Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Peer{})
    socket : Socket <- unconnectedResult(code, peer)
    local : Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
    socket : Socket <- observed(local)
    Socket.close(socket)
    IO.print("PASS socket endpoint")

def address(mode: String) -> Connect.Address:
  match mode:
    case "4": Connect.V4{IPv4.Address{2130706433}}
    case "mapped": Connect.V6{IPv6.Address{0,0,65535,2130706433},0}
    case _: Connect.V6{IPv6.Address{0,0,0,1},0}

def connected(pair: Connect & ConnectCancel) -> IO(Unit):
  match pair:
    case (owner, _):
      do IO<Unit>:
        socket : Socket <- IO.try(Socket, Connect.wait(owner))
        repeat(16n, socket)

def start(mode: String, port: U32) -> IO(Unit):
  match mode:
    case "udp": udp(port)
    case other:
      do IO<Unit>:
        pair : Connect & ConnectCancel <- IO.try(Connect & ConnectCancel, Connect.begin(address(other), port))
        connected(pair)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case mode <> port <> Nil{}: start(mode, Scalar.decimal(port,0))
    case _: IO.die(Unit,1,"expected mode port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
