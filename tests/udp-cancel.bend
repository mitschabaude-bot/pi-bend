import Base
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./socket-endpoint.bend as EndpointTest
import ./udp-bytes.bend as Datagram

def require(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "UDP cancellation contract failed")

def delayed(handle: UDPReadCancel) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(20)
    UDPRead.cancel(handle)

def cancelled(pair: Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>) -> IO(Socket):
  match pair:
    case (socket, None{}): IO.pure(Socket, socket)
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "expected cancellation")

def completed(mode: String, pair: Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>>) -> IO(Socket):
  match pair:
    case (socket, Some{Done{(_, False{}, 0 <> 255 <> Nil{})}}):
      do IO<Socket>:
        require(String.eq(mode, "complete"))
        return socket
    case (socket, Some{Fail{(22, _)}}):
      do IO<Socket>:
        require(String.eq(mode, "invalid"))
        return socket
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "expected packet or capacity error")

def awaited(mode: String, read: UDPRead) -> IO(Socket):
  do IO<Socket>:
    result : Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>> <- UDPRead.wait(read)
    completed(mode, result)

def first(mode: String, read: UDPRead, +handle: UDPReadCancel) -> IO(Socket):
  match mode:
    case "complete": awaited("complete", read)
    case "invalid": awaited("invalid", read)
    case "pre":
      do IO<Socket>:
        won : Bool <- UDPRead.cancel(handle)
        require(won)
        again : Bool <- UDPRead.cancel(handle)
        require(Bool.not(again))
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>> <- UDPRead.wait(read)
        cancelled(result)
    case _:
      do IO<Socket>:
        a : Chan(Bool) <- IO.fork(Bool, delayed(handle))
        b : Chan(Bool) <- IO.fork(Bool, delayed(handle))
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>> <- UDPRead.wait(read)
        socket : Socket <- cancelled(result)
        +left : Bool <- IO.join(Bool, a)
        +right : Bool <- IO.join(Bool, b)
        require((left || right) && Bool.not(left && right))
        return socket

def released(pair: UDPRead & UDPReadCancel) -> IO(Socket):
  match pair:
    case (read, handle):
      do IO<Socket>:
        socket : Socket <- UDPRead.release(read)
        stale : Bool <- UDPRead.cancel(handle)
        require(Bool.not(stale))
        return socket

def reused(old: UDPReadCancel, pair: UDPRead & UDPReadCancel) -> IO(Socket):
  match pair:
    case (read, handle):
      do IO<Socket>:
        stale : Bool <- UDPRead.cancel(old)
        require(Bool.not(stale))
        won : Bool <- UDPRead.cancel(handle)
        require(won)
        result : Socket & Maybe<&1, Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>>> <- UDPRead.wait(read)
        cancelled(result)

def operation(mode: String, pair: UDPRead & UDPReadCancel) -> IO(Socket):
  match pair:
    case (read, +handle):
      do IO<Socket>:
        socket : Socket <- first(mode, read, handle)
        next : UDPRead & UDPReadCancel <- UDPRead.new(socket, 1)
        socket : Socket <- reused(handle, next)
        unused : UDPRead & UDPReadCancel <- UDPRead.new(socket, 1)
        released(unused)

def loop(count: Nat, +mode: String, socket: Socket) -> IO(Socket):
  match count:
    case Zero{}: IO.pure(Socket, socket)
    case Succ{rest}:
      do IO<Socket>:
        pair : UDPRead & UDPReadCancel <- UDPRead.new(socket, Bool.pick(U32, String.eq(mode, "invalid"), 65536, 1024))
        socket : Socket <- operation(mode, pair)
        loop(rest, mode, socket)

def run(family: U32, mode: String, count: Nat) -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- IO.try(Socket, UDP.bind_family(family, 0))
    endpoint : Socket & Result<&2, &2, Endpoint.Error, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
    socket : Socket <- EndpointTest.observed(endpoint)
    socket : Socket <- loop(count, mode, socket)
    IO.print("ready")
    packet : Socket & Result<&1, &1, U32 & String, (U32 & U32 & U32 & U32 & U32 & U32 & U32) & Bool & List<&2, U32>> <- UDP.recv_bytes(socket, 10)
    socket : Socket <- Datagram.received(packet)
    Socket.close(socket)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> mode <> count <> Nil{}: run(Scalar.decimal(family, 0), mode, U32.to_nat(Scalar.decimal(count, 0)))
    case _: IO.die(Unit, 1, "expected family mode count")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
