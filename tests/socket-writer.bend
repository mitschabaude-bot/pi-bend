import Base
import ../packages/runtime/src/socket.bend as S
import ../packages/runtime/src/socket.bend as W
import ../packages/runtime/src/socket.bend as I
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/ref.bend as Ref
import ./tcp-bytes-probe.bend as Probe
import ./tcp-bytes-backpressure.bend as Payload

def require(value: Bool, message: String) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def opened(result: Result<&2, &1, S.SocketErrorOfSocket<String>, S.Owner<String>>) -> IO(S.Owner<String>):
  match result:
    case Done{owner}: IO.pure(S.Owner<String>, owner)
    case Fail{_}: IO.die(S.Owner<String>, 1, "socket adoption failed")

def cleanup(value: Result<&2, &2, I.InterruptError, Unit>) -> IO(Unit):
  match value:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "socket cleanup failed")

def close(owner: S.Owner<String>) -> IO(Unit):
  do IO<Unit>:
    value : Result<&2, &2, I.InterruptError, Unit> <- S.close(String, owner)
    cleanup(value)

def copied(pair: S.Owner<String> & Result<&2, &1, S.SocketErrorOfSocket<String>, W.Writer<String>>) -> IO(S.Owner<String> & W.Writer<String>):
  match pair:
    case (owner, Done{writer}): IO.pure(S.Owner<String> & W.Writer<String>, (owner, writer))
    case (owner, Fail{_}):
      do IO<S.Owner<String> & W.Writer<String>>:
        close(owner)
        IO.die(S.Owner<String> & W.Writer<String>, 1, "writer creation failed")

def readByte(pair: S.Owner<String> & Result<&2, &2, S.SocketErrorOfSocket<String>, List<&2, U32>>, expected: U32) -> IO(S.Owner<String>):
  match pair:
    case (owner, Done{value <> Nil{}}):
      do IO<S.Owner<String>>:
        require(U32.is_eq(value, expected), "wrong peer byte")
        return owner
    case (owner, _):
      do IO<S.Owner<String>>:
        close(owner)
        IO.die(S.Owner<String>, 1, "read did not complete during upload")

def sent(pair: S.Owner<String> & Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>) -> IO(S.Owner<String>):
  match pair:
    case (owner, Done{_}): IO.pure(S.Owner<String>, owner)
    case (owner, Fail{_}):
      do IO<S.Owner<String>>:
        close(owner)
        IO.die(S.Owner<String>, 1, "writer close shut down the connection")

def uploaded(flag: Ref.Ref<Bool>, pair: W.Writer<String> & Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>) -> IO(Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>):
  match pair:
    case (writer, result):
      do IO<Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>>:
        Ref.write(Bool, flag, True{})
        W.closeWriter(String, writer)
        return result

def upload(writer: W.Writer<String>, flag: Ref.Ref<Bool>) -> IO(Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>):
  do IO<Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>>:
    result : W.Writer<String> & Result<&2, &2, S.SocketErrorOfSocket<String>, Unit> <- W.sendWriter(String, writer, Payload.payload(256n, Nil{}))
    uploaded(flag, result)

def cancelled(result: Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>) -> IO(Unit):
  match result:
    case Fail{S.SocketAborted{A.Supplied{why}}}: require(String.eq(why, "stop"), "writer lost abort reason")
    case _: IO.die(Unit, 1, "upload did not retain cancellation")

def concurrent(controller: A.AbortController<String>, pair: S.Owner<String> & W.Writer<String>) -> IO(Unit):
  match pair:
    case (owner, writer):
      do IO<Unit>:
        +flag : Ref.Ref<Bool> <- Ref.new(Bool, False{})
        task : Chan(Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>) <- IO.fork(Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>, upload(writer, flag))
        read : S.Owner<String> & Result<&2, &2, S.SocketErrorOfSocket<String>, List<&2, U32>> <- S.recvSocket(String, owner, 1)
        owner : S.Owner<String> <- readByte(read, 82)
        done : Bool <- Ref.read(Bool, flag)
        require(Bool.not(done), "upload finished before early response")
        won : Bool <- A.abort(String, controller, Some{"stop"})
        require(won, "abort already settled")
        result : Result<&2, &2, S.SocketErrorOfSocket<String>, Unit> <- IO.join(Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>, task)
        cancelled(result)
        done : Bool <- Ref.dispose(Bool, flag)
        require(done, "uploader not joined")
        close(owner)

def written(pair: W.Writer<String> & Result<&2, &2, S.SocketErrorOfSocket<String>, Unit>) -> IO(Unit):
  match pair:
    case (writer, Done{_}): W.closeWriter(String, writer)
    case (writer, Fail{_}):
      do IO<Unit>:
        W.closeWriter(String, writer)
        IO.die(Unit, 1, "ordinary writer send failed")

def normal(pair: S.Owner<String> & W.Writer<String>) -> IO(Unit):
  match pair:
    case (owner, writer):
      do IO<Unit>:
        write : W.Writer<String> & Result<&2, &2, S.SocketErrorOfSocket<String>, Unit> <- W.sendWriter(String, writer, 80 <> Nil{})
        written(write)
        result : S.Owner<String> & Result<&2, &2, S.SocketErrorOfSocket<String>, Unit> <- S.sendSocket(String, owner, 78 <> Nil{})
        owner : S.Owner<String> <- sent(result)
        read : S.Owner<String> & Result<&2, &2, S.SocketErrorOfSocket<String>, List<&2, U32>> <- S.recvSocket(String, owner, 1)
        owner : S.Owner<String> <- readByte(read, 78)
        close(owner)

def rejected(pair: S.Owner<String> & Result<&2, &1, S.SocketErrorOfSocket<String>, W.Writer<String>>) -> IO(Unit):
  match pair:
    case (owner, Fail{S.SocketAborted{_}}): close(owner)
    case (owner, Fail{_}):
      do IO<Unit>:
        close(owner)
        IO.die(Unit, 1, "wrong writer creation error")
    case (owner, Done{writer}):
      do IO<Unit>:
        W.closeWriter(String, writer)
        close(owner)
        IO.die(Unit, 1, "pre-aborted writer was created")

def scenario(owner: S.Owner<String>, +controller: A.AbortController<String>, mode: U32) -> IO(Unit):
  match mode:
    case 0:
      do IO<Unit>:
        result : S.Owner<String> & Result<&2, &1, S.SocketErrorOfSocket<String>, W.Writer<String>> <- W.createWriter(String, owner)
        pair : S.Owner<String> & W.Writer<String> <- copied(result)
        normal(pair)
    case 9:
      do IO<Unit>:
        won : Bool <- A.abort(String, controller, Some{"stop"})
        result : S.Owner<String> & Result<&2, &1, S.SocketErrorOfSocket<String>, W.Writer<String>> <- W.createWriter(String, owner)
        rejected(result)
    case _:
      do IO<Unit>:
        result : S.Owner<String> & Result<&2, &1, S.SocketErrorOfSocket<String>, W.Writer<String>> <- W.createWriter(String, owner)
        pair : S.Owner<String> & W.Writer<String> <- copied(result)
        concurrent(controller, pair)

def cases(count: Nat, +port: U32, +index: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.print("PASS socket writer")
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        result : Result<&2, &1, S.SocketErrorOfSocket<String>, S.Owner<String>> <- S.create(String, socket, A.signal(String, controller))
        owner : S.Owner<String> <- opened(result)
        scenario(owner, controller, index)
        A.dispose(String, controller)
        cases(rest, port, (index + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(10n, Probe.port(args), 0)
