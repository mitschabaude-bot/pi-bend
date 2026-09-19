import Base
import ./tcp-bytes-probe.bend as Probe
import ./tcp-bytes-contract.bend as Contract

def ready(result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Socket):
  match result:
    case (socket, Done{82 <> Nil{}}): IO.pure(Socket, socket)
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "missing server handshake")

def resetReceived(result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Socket):
  match result:
    case (socket, Fail{(0, _)}):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "reset returned error code zero")
    case (socket, Fail{_}): IO.pure(Socket, socket)
    case (socket, _):
      do IO<Socket>:
        Socket.close(socket)
        IO.die(Socket, 1, "reset was not returned as a typed read error")

def sendFailed(result: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case (socket, Fail{(0, _)}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "failed send returned error code zero")
    case (socket, Fail{_}):
      do IO<Unit>:
        Socket.close(socket)
        IO.print("ERRORS")
    case (socket, _):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, 1, "send after reset was not a typed error")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", Probe.port(arguments)))
    gate : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 1)
    socket : Socket <- ready(gate)
    ack : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, 65 <> Nil{})
    socket : Socket <- Contract.sent(ack)
    reset : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 1)
    socket : Socket <- resetReceived(reset)
    failed : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, 66 <> Nil{})
    sendFailed(failed)
