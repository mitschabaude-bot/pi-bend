import Base
import ../packages/runtime/src/socket.bend as Datagram
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./socket-endpoint.bend as EndpointTest
import ./udp-bytes.bend as Bytes

def cause(why: Abort.AbortReason<Deadline.Cause<String>>) -> String:
  match why:
    case Abort.Supplied{Deadline.Expired{}}: "expiry"
    case Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{text}}}: "parent:" ++ text
    case Abort.Supplied{Deadline.ParentAbort{Abort.DefaultAbort{}}}: "default"
    case _: "unexpected"

def retained(saved: Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>>) -> String:
  match saved:
    case None{}: "none"
    case Some{why}: cause(why)

def result(pair: Socket & Result<&2, &2, Datagram.DatagramError<Deadline.Cause<String>>, Datagram.Packet>) -> IO(Socket):
  match pair:
    case (socket, Fail{Datagram.DatagramAborted{why}}):
      do IO<Socket>:
        IO.print("abort:" ++ cause(why))
        return socket
    case (socket, Fail{Datagram.DatagramSocketError{code, _}}):
      do IO<Socket>:
        IO.print("error:" ++ U32.show(code))
        return socket
    case (socket, Done{Datagram.Packet{_, truncated, bytes}}):
      do IO<Socket>:
        IO.print("packet:" ++ Bytes.bit(truncated) ++ ":" ++ Bytes.csv(bytes))
        return socket
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "unexpected datagram result")

def stop(parent: Abort.AbortController<String>, default: Bool) -> IO(Unit):
  do IO<Unit>:
    won : Bool <- Abort.abort(String, parent, Bool.pick(Maybe<&2, String>, default, None{}, Some{"stop"}))
    return Unit{}

def before(mode: String, parent: Abort.AbortController<String>) -> IO(Unit):
  match mode:
    case "pre": stop(parent, False{})
    case _: IO.pure(Unit, Unit{})

def later(mode: String, parent: Abort.AbortController<String>) -> IO(Unit):
  match mode:
    case "custom":
      do IO<Unit>:
        IO.sleep(20)
        stop(parent, False{})
    case "default":
      do IO<Unit>:
        IO.sleep(20)
        stop(parent, True{})
    case _: IO.pure(Unit, Unit{})

def scoped(socket: Socket, maximum: U32, pair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Socket):
  match pair:
    case (scope, signal):
      do IO<Socket>:
        packet : Socket & Result<&2, &2, Datagram.DatagramError<Deadline.Cause<String>>, Datagram.Packet> <- Datagram.recv(Deadline.Cause<String>, socket, maximum, signal)
        socket : Socket <- result(packet)
        saved : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        IO.print("scope:" ++ retained(saved))
        return socket

def loop(count: Nat, +mode: String, socket: Socket) -> IO(Socket):
  match count:
    case Zero{}: IO.pure(Socket, socket)
    case Succ{rest}:
      do IO<Socket>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        before(mode, parent)
        task : Chan(Unit) <- IO.fork(Unit, later(mode, parent))
        scope : Deadline.Scope<String> <- Deadline.create(String, Bool.pick(U32, String.eq(mode, "deadline"), 20, 5000), Abort.signal(String, parent))
        socket : Socket <- scoped(socket, Bool.pick(U32, String.eq(mode, "invalid"), 65536, Bool.pick(U32, String.eq(mode, "short"), 1, 10)), Deadline.borrow(String, scope))
        IO.join(Unit, task)
        Abort.dispose(String, parent)
        loop(rest, mode, socket)

def run(family: U32, mode: String, count: Nat) -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- IO.try(Socket, UDP.bind_family(family, 0))
    endpoint : Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
    socket : Socket <- EndpointTest.observed(endpoint)
    socket : Socket <- loop(count, mode, socket)
    IO.print("ready")
    packet : Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>> <- UDP.recv_bytes(socket, 10)
    socket : Socket <- Bytes.received(packet)
    Socket.close(socket)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> mode <> count <> Nil{}: run(Scalar.decimal(family, 0), mode, U32.to_nat(Scalar.decimal(count, 0)))
    case _: IO.die(Unit, 1, "expected family mode count")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
