import Base
import ../packages/runtime/src/socket.bend as S
import ../packages/runtime/src/abort.bend as A
import ../packages/runtime/src/socket.bend as I
import ./tcp-bytes-probe.bend as Probe

def assertTrue(value: Bool, message: String) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def cleanup(result: Result<&2, &2, I.InterruptError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "socket cleanup failed")

def closed(owner: S.Owner<String>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, I.InterruptError, Unit> <- S.close(String, owner)
    cleanup(result)

def opened(result: Result<&2, &1, S.Error<String>, S.Owner<String>>) -> IO(S.Owner<String>):
  match result:
    case Done{owner}: IO.pure(S.Owner<String>, owner)
    case Fail{_}: IO.die(S.Owner<String>, 1, "socket adoption failed")

def why(reason: A.AbortReason<String>, mode: U32) -> Bool:
  match reason mode:
    case A.DefaultAbort{} 3: True{}
    case A.Supplied{value} _: String.eq(value, "stop")
    case _ _: False{}

def aborted(-Value: Data, pair: S.Owner<String> & Result<&2, &2, S.Error<String>, Value>, mode: U32) -> IO(S.Owner<String>):
  match pair:
    case (owner, Fail{S.Aborted{reason}}):
      do IO<S.Owner<String>>:
        assertTrue(why(reason, mode), "wrong abort reason")
        return owner
    case (owner, _):
      do IO<S.Owner<String>>:
        closed(owner)
        IO.die(S.Owner<String>, 1, "abort appeared as data/EOF/socket error")

def data(pair: S.Owner<String> & Result<&2, &2, S.Error<String>, List<&2, U32>>) -> IO(S.Owner<String>):
  match pair:
    case (owner, Done{78 <> Nil{}}): IO.pure(S.Owner<String>, owner)
    case (owner, _):
      do IO<S.Owner<String>>:
        closed(owner)
        IO.die(S.Owner<String>, 1, "missing initial bytes")

def eof(pair: S.Owner<String> & Result<&2, &2, S.Error<String>, List<&2, U32>>) -> IO(Unit):
  match pair:
    case (owner, Done{Nil{}}): closed(owner)
    case (owner, _):
      do IO<Unit>:
        closed(owner)
        IO.die(Unit, 1, "clean peer EOF failed")

def abortReason(mode: U32) -> Maybe<&2, String>:
  match mode:
    case 3: None{}
    case _: Some{"stop"}

def later(controller: A.AbortController<String>, mode: U32) -> IO(Bool):
  do IO<Bool>:
    IO.sleep(50)
    A.abort(String, controller, abortReason(mode))

def pending(owner: S.Owner<String>, +controller: A.AbortController<String>, +mode: U32) -> IO(Unit):
  do IO<Unit>:
    task : Chan(Bool) <- IO.fork(Bool, later(controller, mode))
    pair : S.Owner<String> & Result<&2, &2, S.Error<String>, List<&2, U32>> <- S.recvSocket(String, owner, 16)
    owner : S.Owner<String> <- aborted(List<&2, U32>, pair, mode)
    again : S.Owner<String> & Result<&2, &2, S.Error<String>, List<&2, U32>> <- S.recvSocket(String, owner, 16)
    owner : S.Owner<String> <- aborted(List<&2, U32>, again, mode)
    sent : S.Owner<String> & Result<&2, &2, S.Error<String>, Unit> <- S.sendSocket(String, owner, 88 <> Nil{})
    owner : S.Owner<String> <- aborted(Unit, sent, mode)
    closed(owner)
    won : Bool <- IO.join(Bool, task)
    assertTrue(won, "abort did not win signal settlement")
    again : Bool <- A.abort(String, controller, Some{"different"})
    assertTrue(Bool.not(again), "abort reason changed")

def active(owner: S.Owner<String>, controller: A.AbortController<String>, mode: U32) -> IO(Unit):
  match mode:
    case 1:
      do IO<Unit>:
        pair : S.Owner<String> & Result<&2, &2, S.Error<String>, List<&2, U32>> <- S.recvSocket(String, owner, 1)
        owner : S.Owner<String> <- data(pair)
        closed(owner)
        won : Bool <- A.abort(String, controller, Some{"after close"})
        assertTrue(won, "normal completion aborted borrowed signal")
    case 4:
      do IO<Unit>:
        pair : S.Owner<String> & Result<&2, &2, S.Error<String>, List<&2, U32>> <- S.recvSocket(String, owner, 1)
        owner : S.Owner<String> <- data(pair)
        pending(owner, controller, 4)
    case 5:
      do IO<Unit>:
        pair : S.Owner<String> & Result<&2, &2, S.Error<String>, List<&2, U32>> <- S.recvSocket(String, owner, 1)
        eof(pair)
    case other: pending(owner, controller, other)

def preAborted(result: Result<&2, &1, S.Error<String>, S.Owner<String>>) -> IO(Unit):
  match result:
    case Fail{S.Aborted{A.Supplied{reason}}}: assertTrue(String.eq(reason, "stop"), "pre-abort reason lost")
    case Fail{_}: IO.die(Unit, 1, "wrong pre-abort error")
    case Done{owner}:
      do IO<Unit>:
        closed(owner)
        IO.die(Unit, 1, "pre-aborted socket adopted")

def scenario(socket: Socket, +controller: A.AbortController<String>, +mode: U32) -> IO(Unit):
  match mode:
    case 0:
      do IO<Unit>:
        won : Bool <- A.abort(String, controller, Some{"stop"})
        result : Result<&2, &1, S.Error<String>, S.Owner<String>> <- S.create(String, socket, A.signal(String, controller))
        preAborted(result)
    case other:
      do IO<Unit>:
        result : Result<&2, &1, S.Error<String>, S.Owner<String>> <- S.create(String, socket, A.signal(String, controller))
        owner : S.Owner<String> <- opened(result)
        active(owner, controller, other)

def loop(count: Nat, +port: U32, +index: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        scenario(socket, controller, (index % 6 : U32))
        A.dispose(String, controller)
        loop(rest, port, (index + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    loop(24n, Probe.port(args), 0)
    IO.print("PASS abortable socket")
