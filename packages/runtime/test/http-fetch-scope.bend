import Base
import ../src/http-response.bend as Fetch
import ../src/deadline.bend as Deadline
import ../src/abort.bend as Abort
import ../src/deferred.bend as Deferred
import ../src/http-response.bend as Response
import ../src/http-response.bend as Progress
import ../src/http-response.bend as Stream
import ../src/http-response.bend as Metadata
import ../src/http-message.bend as Head
import ../src/http-message.bend as Status

type Transport is Type:
  Transport{signal: Abort.AbortSignal<Deadline.Cause<String>>, fails: Bool, wait: Bool}

def reason(value: Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>>) -> String:
  match value:
    case None{}: "none"
    case Some{Abort.Supplied{Deadline.Expired{}}}: "expired"
    case Some{Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{why}}}}: why
    case _: "default"

def waitSignal(signal: Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match signal:
    case Abort.AbortSignal{settlement}:
      do IO<Unit>:
        why : Abort.AbortReason<Deadline.Cause<String>> <- Deferred.result(Abort.AbortReason<Deadline.Cause<String>>, settlement)
        return Unit{}

def awaitParent(wait: Bool, signal: Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match wait:
    case True{}: waitSignal(signal)
    case False{}: IO.pure(Unit, Unit{})

def metadata() -> Metadata.Metadata:
  Metadata.fromHead(Head.ResponseHead{Status.StatusLine{1, 1, 200, Nil{}}, Nil{}}, True{})

def dispatched(+mode: String, signal: Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Result<&2, &1, String, Response.Response<Transport>>):
  match mode:
    case "failure": IO.pure(Result<&2, &1, String, Response.Response<Transport>>, Fail{"dispatch"})
    case "timeout":
      do IO<Result<&2, &1, String, Response.Response<Transport>>>:
        waitSignal(signal)
        return Fail{"dispatch"}
    case "closed": IO.pure(Result<&2, &1, String, Response.Response<Transport>>, Done{Response.Response{metadata(), Response.Closed{Some{Nil{}}}}})
    case _:
      IO.pure(Result<&2, &1, String, Response.Response<Transport>>, Done{Response.Response{metadata(), Response.Open{Transport{signal, String.eq(mode, "cleanup"), String.eq(mode, "parent")}, True{}}}})

def dispatch(mode: String, signal: Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Result<&2, &1, String, Response.Response<Transport>>):
  do IO<Result<&2, &1, String, Response.Response<Transport>>>:
    IO.print("dispatch")
    dispatched(mode, signal)

def read(transport: Transport) -> IO(Transport & Result<&2, &2, String, Maybe<&2, Stream.StreamEvent>>):
  match transport:
    case Transport{+signal, +fails, +wait}:
      do IO<Transport & Result<&2, &2, String, Maybe<&2, Stream.StreamEvent>>>:
        awaitParent(wait, signal)
        why : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Abort.reason(Deadline.Cause<String>, signal)
        IO.print("read:" ++ reason(why))
        return (Transport{signal, fails, wait}, Bool.pick(Result<&2, &2, String, Maybe<&2, Stream.StreamEvent>>, fails, Fail{"read"}, Done{Some{Stream.Completed{Nil{}}}}))

def close(transport: Transport) -> IO(Result<&2, &2, String, Unit>):
  match transport:
    case Transport{signal, fails, _}:
      do IO<Result<&2, &2, String, Unit>>:
        why : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Abort.reason(Deadline.Cause<String>, signal)
        IO.print("close:" ++ reason(why))
        return Bool.pick(Result<&2, &2, String, Unit>, fails, Fail{"cleanup"}, Done{Unit{}})

def show(value: Result<&2, &2, Progress.ResponseProgressError<String>, Maybe<&2, List<&2, U32>>>) -> String:
  match value:
    case Done{None{}}: "end"
    case Fail{Progress.ResponseProgressFailureWithCleanup{Progress.TransportFailure{primary}, cleanup}}: primary ++ "+" ++ cleanup
    case _: "unexpected"

def again(next: Response.Next<String, Fetch.State<String, Transport>>) -> IO(Unit):
  match next:
    case Response.Next{_, result}: IO.print("again:" ++ show(result))

def finished(next: Response.Next<String, Fetch.State<String, Transport>>) -> IO(Unit):
  match next:
    case Response.Next{body, result}:
      do IO<Unit>:
        IO.print(show(result))
        next : Response.Next<String, Fetch.State<String, Transport>> <- Response.closeWith(String, Fetch.State<String, Transport>, value => Fetch.closeFetchScope(String, String, Transport, close, value), body)
        again(next)

def abortParent(mode: String, parent: Abort.AbortController<String>) -> IO(Unit):
  match mode:
    case "parent":
      do IO<Unit>:
        won : Bool <- Abort.abort(String, parent, Some{"stop"})
        return Unit{}
    case _: IO.pure(Unit, Unit{})

def consume(+mode: String, parent: Abort.AbortController<String>, result: Result<&2, &1, Fetch.FetchScopeError<String, String>, Response.Response<Fetch.State<String, Transport>>>) -> IO(Unit):
  match result:
    case Fail{Fetch.Aborted{why}}: IO.print("aborted:" ++ reason(Some{why}))
    case Fail{Fetch.DispatchFailure{cause, why}}: IO.print(cause ++ ":" ++ reason(why))
    case Done{Response.Response{head, body}}:
      do IO<Unit>:
        IO.print("headers")
        IO.sleep(Bool.pick(U32, String.eq(mode, "normal"), 1100, 0))
        abortParent(mode, parent)
        next : Response.Next<String, Fetch.State<String, Transport>> <- Response.nextWith(~String, ~(Fetch.State<String, Transport>), ~(value => Fetch.read(String, String, Transport, read, value)), ~(value => Fetch.closeFetchScope(String, String, Transport, close, value)), body)
        finished(next)

def pre(mode: String, parent: Abort.AbortController<String>) -> IO(Unit):
  match mode:
    case "pre":
      do IO<Unit>:
        won : Bool <- Abort.abort(String, parent, Some{"before"})
        return Unit{}
    case _: IO.pure(Unit, Unit{})

def run(+mode: String) -> IO(Unit):
  do IO<Unit>:
    +parent : Abort.AbortController<String> <- Abort.new(String)
    pre(mode, parent)
    result : Result<&2, &1, Fetch.FetchScopeError<String, String>, Response.Response<Fetch.State<String, Transport>>> <- Fetch.startFetchScope(String, String, Transport, Bool.pick(U32, String.eq(mode, "timeout"), 10, 1000), Abort.signal(String, parent), signal => dispatch(mode, signal))
    consume(mode, parent, result)
    Abort.dispose(String, parent)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> Nil{}: run(mode)
    case _: IO.die(Unit, 1, "mode required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
