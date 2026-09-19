import Base
import ../packages/runtime/test/utf8-runner.bend as H

def port(arguments: List<String>) -> U32:
  match arguments:
    case SCon{Chr{112}, digits} <> _: H.decimal(digits, 0)
    case _ <> rest: port(rest)
    case Nil{}: 0

@unsafe
def receive(result: Socket & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match result:
    case (socket, Done{SNil{}}): Socket.close(socket)
    case (socket, Done{text}):
      do IO<Unit>:
        IO.write(text)
        next : Socket & Result<&1, &1, U32 & String, String> <- TCP.recv(socket, 7)
        receive(next)
    case (socket, Fail{(code, message)}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, code, message)

def sent(result: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case (socket, Done{_}):
      do IO<Unit>:
        first : Socket & Result<&1, &1, U32 & String, String> <- TCP.recv(socket, 7)
        receive(first)
    case (socket, Fail{(code, message)}):
      do IO<Unit>:
        Socket.close(socket)
        IO.die(Unit, code, message)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port(arguments)))
    result : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, "ping")
    sent(result)
