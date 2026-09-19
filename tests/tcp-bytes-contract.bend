import Base
import ./tcp-bytes-probe.bend as Probe
import ../packages/runtime/test/utf8-runner.bend as H

def sent(result: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Socket):
  match result:
    case (socket, Done{_}): IO.pure(Socket, socket)
    case (socket, Fail{(code, message)}):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, code, message)

def rejected(result: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Socket):
  match result:
    case (socket, Fail{(22, _)}): IO.pure(Socket, socket)
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "invalid byte was not rejected with EINVAL")

def emptyRead(result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Socket):
  match result:
    case (socket, Done{Nil{}}): IO.pure(Socket, socket)
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "expected empty read")

def finish(result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- emptyRead(result)
    Socket.close(socket)
    IO.print("EOF")

# External I/O loop: EOF, not a synthetic fuel limit, terminates reading.
@unsafe
def receive(result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match result:
    case (socket, Done{Nil{}}):
      do IO<Unit>:
        again : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 7)
        finish(again)
    case (socket, Done{bytes}):
      do IO<Unit>:
        IO.print(String.join(H.showNumbers(bytes), ","))
        next : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 7)
        receive(next)
    case (socket, Fail{(code, message)}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, code, message)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", Probe.port(arguments)))
    bad : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, 65 <> 256 <> 66 <> Nil{})
    socket : Socket <- rejected(bad)
    bad : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, 4294967295 <> Nil{})
    socket : Socket <- rejected(bad)
    empty : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, Nil{})
    socket : Socket <- sent(empty)
    sentPayload : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, Probe.payload(256n, 0))
    socket : Socket <- sent(sentPayload)
    empty : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 0)
    socket : Socket <- emptyRead(empty)
    first : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 7)
    receive(first)
