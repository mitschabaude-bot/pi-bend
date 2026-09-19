import Base
import ./connect-owned.bend as Test
import ../packages/runtime/test/utf8-runner.bend as Scalar

type Running is Type:
  Running{task: Chan(Result<&1, &1, U32 & String, Socket>), handle: ConnectCancel}

def running(pair: Connect & ConnectCancel) -> IO(Running):
  match pair:
    case (owner, handle):
      do IO<Running>:
        task : Chan(Result<&1, &1, U32 & String, Socket>) <- IO.fork(Result<&1, &1, U32 & String, Socket>, Connect.wait(owner))
        return Running{task, handle}

def create(count: Nat, +ipv6: Bool, +port: U32, values: List<&1, Running>) -> IO(List<&1, Running>):
  match count:
    case Zero{}: IO.pure(List<&1, Running>, values)
    case Succ{rest}:
      do IO<List<&1, Running>>:
        pair : Connect & ConnectCancel <- Test.begin(ipv6, port)
        value : Running <- running(pair)
        create(rest, ipv6, port, value <> values)

def cancelled(value: Running) -> IO(Unit):
  match value:
    case Running{task, +handle}:
      do IO<Unit>:
        won : Bool <- Connect.cancel(handle)
        Test.assertion(won, "cohort cancellation lost")
        result : Result<&1, &1, U32 & String, Socket> <- IO.join(Result<&1, &1, U32 & String, Socket>, task)
        Test.failed(result)
        Test.stale(handle)

def retire(values: List<&1, Running>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        cancelled(value)
        retire(rest)

def cohort(ipv6: Bool, port: U32) -> IO(Unit):
  do IO<Unit>:
    values : List<&1, Running> <- create(64n, ipv6, port, Nil{})
    IO.sleep(5)
    retire(values)

def old(pair: Connect & ConnectCancel) -> IO(ConnectCancel):
  match pair:
    case (owner, handle):
      do IO<ConnectCancel>:
        Connect.close(owner)
        return handle

def replaced(pair: Connect & ConnectCancel, previous: ConnectCancel) -> IO(Unit):
  do IO<Unit>:
    Test.stale(previous)
    Test.cancelBefore(pair)

def reuse(+ipv6: Bool, +port: U32) -> IO(Unit):
  do IO<Unit>:
    first : Connect & ConnectCancel <- Test.begin(ipv6, port)
    previous : ConnectCancel <- old(first)
    second : Connect & ConnectCancel <- Test.begin(ipv6, port)
    replaced(second, previous)

def raceResult(result: Result<&1, &1, U32 & String, Socket>, +first: Bool, +second: Bool) -> IO(Unit):
  match result:
    case Done{socket}:
      do IO<Unit>:
        Socket.close(socket)
        Test.assertion(Bool.not(first || second), "success despite winning cancellation")
        IO.print("connected")
    case Fail{(code, _)}:
      do IO<Unit>:
        Test.assertion((first || second) && Bool.not(first && second), "wrong cancellation winner count")
        IO.print("cancelled:" ++ U32.show(code))

def race(pair: Connect & ConnectCancel) -> IO(Unit):
  match pair:
    case (owner, +handle):
      do IO<Unit>:
        task : Chan(Result<&1, &1, U32 & String, Socket>) <- IO.fork(Result<&1, &1, U32 & String, Socket>, Connect.wait(owner))
        first : Chan(Bool) <- IO.fork(Bool, Connect.cancel(handle))
        second : Chan(Bool) <- IO.fork(Bool, Connect.cancel(handle))
        result : Result<&1, &1, U32 & String, Socket> <- IO.join(Result<&1, &1, U32 & String, Socket>, task)
        a : Bool <- IO.join(Bool, first)
        b : Bool <- IO.join(Bool, second)
        raceResult(result, a, b)
        Test.stale(handle)

def one(mode: String, +ipv6: Bool, +port: U32) -> IO(Unit):
  match mode:
    case "reuse": reuse(ipv6, port)
    case "cohort": cohort(ipv6, port)
    case _:
      do IO<Unit>:
        pair : Connect & ConnectCancel <- Test.begin(ipv6, port)
        race(pair)

def repeat(count: Nat, +mode: String, +ipv6: Bool, +port: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        one(mode, ipv6, port)
        repeat(rest, mode, ipv6, port)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> family <> port <> Nil{}: repeat(4n, mode, String.eq(family, "6"), Scalar.decimal(port, 0))
    case _: IO.die(Unit, 1, "expected mode, family and port")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
