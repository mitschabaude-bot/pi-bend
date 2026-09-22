import Base
import ../packages/runtime/src/socket.bend as Datagram
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./abortable-datagram.bend as Receive
import ./udp-write.bend as Write

def destination(family: U32, port: U32) -> Endpoint.Endpoint:
  match family:
    case 4: Endpoint.EndpointV4{IPv4.Address{2130706433}, port}
    case _: Endpoint.EndpointV6{IPv6.Address{0, 0, 0, 1}, port, 0}

def result(pair: Socket & Result<&2, &2, Datagram.DatagramError<Deadline.Cause<String>>, Unit>) -> IO(Socket):
  match pair:
    case (socket, Fail{Datagram.DatagramAborted{why}}):
      do IO<Socket>:
        IO.print("abort:" ++ Receive.cause(why))
        return socket
    case (socket, Fail{Datagram.DatagramSocketError{code, _}}):
      do IO<Socket>:
        IO.print("error:" ++ U32.show(code))
        return socket
    case (socket, Done{_}):
      do IO<Socket>:
        IO.print("ok")
        return socket
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "unexpected send result")

def scoped(socket: Socket, target: Endpoint.Endpoint, bytes: List<&2, U32>, pair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Socket):
  match pair:
    case (scope, signal):
      do IO<Socket>:
        value : Socket & Result<&2, &2, Datagram.DatagramError<Deadline.Cause<String>>, Unit> <- Datagram.send(Deadline.Cause<String>, socket, target, bytes, signal)
        socket : Socket <- result(value)
        saved : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        IO.print("scope:" ++ Receive.retained(saved))
        return socket

def loop(count: Nat, +mode: String, +target: Endpoint.Endpoint, +bytes: List<&2, U32>, socket: Socket) -> IO(Socket):
  match count:
    case Zero{}: IO.pure(Socket, socket)
    case Succ{rest}:
      do IO<Socket>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        Receive.before(mode, parent)
        task : Chan(Unit) <- IO.fork(Unit, Receive.later(mode, parent))
        scope : Deadline.Scope<String> <- Deadline.create(String, Bool.pick(U32, String.eq(mode, "deadline"), 20, 5000), Abort.signal(String, parent))
        socket : Socket <- scoped(socket, target, bytes, Deadline.borrow(String, scope))
        IO.join(Unit, task)
        Abort.dispose(String, parent)
        loop(rest, mode, target, bytes, socket)

def run(+family: U32, +port: U32, +mode: String, size: Nat, count: Nat) -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- IO.try(Socket, UDP.bind_family(family, 0))
    socket : Socket <- loop(count, mode, destination(family, Bool.pick(U32, String.eq(mode, "port"), 0, port)), Write.payload(size, 0, String.eq(mode, "byte"), Nil{}), socket)
    value : Socket & Result<&1, &1, U32 & String, Unit> <- UDP.send_bytes(socket, family, Bool.pick(U32, U32.is_eq(family, 4), 2130706433, 0), 0, 0, Bool.pick(U32, U32.is_eq(family, 6), 1, 0), port, 0, 17 <> 0 <> 255 <> Nil{})
    socket : Socket <- Write.sent(value)
    Socket.close(socket)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> port <> mode <> size <> count <> Nil{}: run(Scalar.decimal(family, 0), Scalar.decimal(port, 0), mode, U32.to_nat(Scalar.decimal(size, 0)), U32.to_nat(Scalar.decimal(count, 0)))
    case _: IO.die(Unit, 1, "expected family port mode size count")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
