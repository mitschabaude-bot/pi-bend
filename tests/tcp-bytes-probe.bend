import Base
import ../packages/runtime/test/utf8-runner.bend as H

def port(arguments: List<String>) -> U32:
  match arguments:
    case SCon{Chr{112}, digits} <> _: H.decimal(digits, 0)
    case _ <> rest: port(rest)
    case Nil{}: 0

def payload(remaining: Nat, +n: U32) -> List<&2, U32>:
  match remaining:
    case 0n: Nil{}
    case 1n+rest: n <> payload(rest, (n + 1 : U32))

def received(result: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match result:
    case (socket, Done{bytes}):
      do IO<Unit>:
        IO.print(String.join(H.showNumbers(bytes), ","))
        Socket.close(socket)
    case (socket, Fail{(code, message)}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, code, message)

def sent(result: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case (socket, Done{_}):
      do IO<Unit>:
        result : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- TCP.recv_bytes(socket, 256)
        received(result)
    case (socket, Fail{(code, message)}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, code, message)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port(arguments)))
    result : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send_bytes(socket, payload(256n, 0))
    sent(result)
