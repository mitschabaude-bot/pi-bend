import Base
import ../packages/runtime/src/dns-transport.bend as Peer
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/abort.bend as Abort
import ./dns-tcp-connection.bend as Test

def socket(result: Result<&1, &1, U32 & String, Socket>) -> IO(Socket):
  match result:
    case Done{owner}: IO.pure(Socket, owner)
    case Fail{_}: IO.die(Socket, 1, "UDP bind failed; inspection may have retained its socket")

def rejected(result: Result<&2, &1, Peer.TcpPeerError<String>, Peer.Peer<String>>) -> IO(Unit):
  match result:
    case Fail{Peer.Inspection{Endpoint.SocketError{107, _}}}: IO.pure(Unit, Unit{})
    case Done{Peer.Peer{_, connection}}:
      do IO<Unit>:
        Test.close(connection)
        IO.die(Unit, 1, "unconnected UDP accepted as TCP peer")
    case _: IO.die(Unit, 1, "expected Linux ENOTCONN")

def observed(+signal: Abort.AbortSignal<String>, pair: Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint>) -> IO(Unit):
  match pair:
    case (owner, Done{Endpoint.V4{_, +port}}):
      do IO<Unit>:
        result : Result<&2, &1, Peer.TcpPeerError<String>, Peer.Peer<String>> <- Peer.createTcpPeer(String, owner, signal)
        rejected(result)
        bound : Result<&1, &1, U32 & String, Socket> <- UDP.bind(port)
        rebound : Socket <- socket(bound)
        Socket.close(rebound)
        return Unit{}
    case (owner, _):
      do IO<Unit>:
        Socket.close(owner)
        IO.die(Unit, 1, "local UDP endpoint missing")

def repeat(count: Nat, +signal: Abort.AbortSignal<String>) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, Socket> <- UDP.bind(0)
        owner : Socket <- socket(result)
        pair : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(owner, Endpoint.Local{})
        observed(signal, pair)
        repeat(rest, signal)

def main() -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<String> <- Abort.new(String)
    repeat(32n, Abort.signal(String, controller))
    Abort.dispose(String, controller)
    IO.print("PASS DNS TCP peer inspection cleanup")
