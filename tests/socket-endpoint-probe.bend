import Base
import ../packages/runtime/test/utf8-runner.bend as Scalar

def show(result: Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32>) -> String:
  match result:
    case Fail{(code, _)}: "error:" ++ U32.show(code)
    case Done{(family,a,b,c,d,port,scope)}: String.join(Scalar.showNumbers(family <> a <> b <> c <> d <> port <> scope <> Nil{}), ",")

def closed(pair: Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32>) -> IO(Unit):
  match pair:
    case (socket, result):
      do IO<Unit>:
        Socket.close(socket)
        IO.print(show(result))

def run(args: List<String>) -> IO(Unit):
  match args:
    case side <> Nil{}:
      do IO<Unit>:
        socket : Socket <- IO.try(Socket, UDP.bind(0))
        result : Socket & Result<&1, &1, U32 & String, U32 & U32 & U32 & U32 & U32 & U32 & U32> <- Socket.endpoint(socket, Scalar.decimal(side,0))
        closed(result)
    case _: IO.die(Unit,1,"expected side")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
