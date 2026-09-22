import Base
import ../packages/runtime/src/socket.bend as Client
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/url.bend as IPv4
import ../packages/runtime/src/url.bend as IPv6
import ./connect-owned.bend as Test
import ../packages/runtime/test/utf8-runner.bend as Scalar

def address(ipv6: Bool) -> Client.Address:
  match ipv6:
    case False{}: Client.V4{IPv4.Address{2130706433}}
    case True{}: Client.V6{IPv6.Ipv6Address{0, 0, 0, 1}, 0}

def expect(+kind: String, expectedCode: U32, result: Result<&2, &1, Client.Error<String>, Socket>) -> IO(Unit):
  match result:
    case Done{socket}:
      do IO<Unit>:
        Socket.close(socket)
        Test.assertion(String.eq(kind, "success"), "unexpected socket")
    case Fail{Client.Aborted{Abort.Supplied{reason}}}: Test.assertion(String.eq(kind, "abort") && String.eq(reason, "stop"), "wrong supplied reason")
    case Fail{Client.Aborted{Abort.DefaultAbort{}}}: Test.assertion(String.eq(kind, "default"), "wrong default reason")
    case Fail{Client.SocketError{code, _}}: Test.assertion(String.eq(kind, "error") && U32.is_eq(code, expectedCode), "wrong socket error")

def repeat(count: Nat, +endpoint: Client.Address, +port: U32, +signal: Abort.AbortSignal<String>, +kind: String, +code: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        result : Result<&2, &1, Client.Error<String>, Socket> <- Client.connect(String, endpoint, port, signal)
        expect(kind, code, result)
        repeat(rest, endpoint, port, signal, kind, code)

def launch(count: Nat, +endpoint: Client.Address, +port: U32, +signal: Abort.AbortSignal<String>, tasks: List<&1, Chan(Result<&2, &1, Client.Error<String>, Socket>)>) -> IO(List<&1, Chan(Result<&2, &1, Client.Error<String>, Socket>)>):
  match count:
    case Zero{}: IO.pure(List<&1, Chan(Result<&2, &1, Client.Error<String>, Socket>)>, tasks)
    case Succ{rest}:
      do IO<List<&1, Chan(Result<&2, &1, Client.Error<String>, Socket>)>>:
        task : Chan(Result<&2, &1, Client.Error<String>, Socket>) <- IO.fork(Result<&2, &1, Client.Error<String>, Socket>, Client.connect(String, endpoint, port, signal))
        launch(rest, endpoint, port, signal, task <> tasks)

def joined(tasks: List<&1, Chan(Result<&2, &1, Client.Error<String>, Socket>)>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case task <> rest:
      do IO<Unit>:
        result : Result<&2, &1, Client.Error<String>, Socket> <- IO.join(Result<&2, &1, Client.Error<String>, Socket>, task)
        expect("abort", 0, result)
        joined(rest)

# Deterministically exercise abort observed after the OS returned a socket.
def late(pair: Connect & ConnectCancel, +controller: Abort.AbortController<String>) -> IO(Unit):
  match pair:
    case (owner, _):
      do IO<Unit>:
        socket : Socket <- IO.try(Socket, Connect.wait(owner))
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        result : Result<&2, &1, Client.Error<String>, Socket> <- Client.settled(String, Done{socket}, Abort.signal(String, controller))
        expect("abort", 0, result)

def run(mode: String, +endpoint: Client.Address, +port: U32, code: U32, +controller: Abort.AbortController<String>) -> IO(Unit):
  match mode:
    case "late":
      do IO<Unit>:
        pair : Connect & ConnectCancel <- IO.try(Connect & ConnectCancel, Client.begin(endpoint, port))
        late(pair, controller)
    case "cancel":
      do IO<Unit>:
        tasks : List<&1, Chan(Result<&2, &1, Client.Error<String>, Socket>)> <- launch(32n, endpoint, port, Abort.signal(String, controller), Nil{})
        IO.sleep(10)
        first : Bool <- Abort.abort(String, controller, Some{"stop"})
        second : Bool <- Abort.abort(String, controller, Some{"replacement"})
        Test.assertion(first && Bool.not(second), "abort settlement changed")
        joined(tasks)
        repeat(16n, endpoint, port, Abort.signal(String, controller), "abort", 0)
    case "pre":
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        repeat(16n, endpoint, port, Abort.signal(String, controller), "abort", 0)
    case "default":
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, None{})
        repeat(16n, endpoint, port, Abort.signal(String, controller), "default", 0)
    case kind: repeat(16n, endpoint, port, Abort.signal(String, controller), kind, code)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> family <> port <> code <> Nil{}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        run(mode, address(String.eq(family, "6")), Scalar.decimal(port, 0), Scalar.decimal(code, 0), controller)
        Abort.dispose(String, controller)
        IO.print("PASS abortable connect")
    case _: IO.die(Unit, 1, "expected mode, family, port, error code")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
