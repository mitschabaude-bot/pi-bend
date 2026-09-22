import Base
import ../packages/runtime/src/dns-transport.bend as Query
import ../packages/runtime/src/dns-transport.bend as Session
import ../packages/runtime/src/dns-transport.bend as Peer
import ../packages/runtime/src/dns-transport.bend as TCP
import ../packages/runtime/src/dns-message.bend as Frame
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/abortable-socket.bend as SocketIO
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-tcp-connection.bend as Test
import ./abortable-socket.bend as Check

def cause(reason: Abort.AbortReason<Deadline.Cause<String>>) -> String:
  match reason:
    case Abort.Supplied{Deadline.Expired{}}: "expiry"
    case Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{"stop"}}}: "parent"
    case Abort.Supplied{Deadline.ParentAbort{Abort.DefaultAbort{}}}: "default"
    case _: "unexpected"

def retained(value: Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>>) -> String:
  match value:
    case None{}: "none"
    case Some{why}: cause(why)

def outcome(value: Result<&2, &2, Query.TcpQueryError<String>, Query.Reply>) -> String:
  match value:
    case Done{Query.TcpQueryAnswer{Message.Message{_, Message.Header{_, flags, _, _, _, _}, _, _, _, _}}}: "answer:" ++ U32.show(flags)
    case Done{Query.TcpQueryTruncated{_}}: "truncated"
    case Fail{Query.TcpQueryInvalidReadSize{}}: "zero"
    case Fail{Query.TcpQueryConnection{Connect.Aborted{why}}}: "connect:" ++ cause(why)
    case Fail{Query.TcpQueryConnection{Connect.SocketError{code, _}}}: "socket:" ++ U32.show(code)
    case Fail{Query.TcpQueryAdoption{Peer.Adoption{SocketIO.Aborted{why}}}}: "adopt:" ++ cause(why)
    case Fail{Query.Terminated{Session.TcpSessionTransport{TCP.Transport{_, SocketIO.Aborted{why}}}}}: "read:" ++ cause(why)
    case Fail{Query.Terminated{Session.EndOfStream{}}}: "eof"
    case Fail{Query.Terminated{Session.TcpSessionTransport{TCP.Framing{Frame.IncompleteFrame{}}}}}: "frame"
    case Fail{Query.Submission{Session.Query{_}}}: "query"
    case _: "unexpected"

def status(value: Query.Report<String>) -> IO(Unit):
  match value:
    case Query.Report{result, cleanup, reason}:
      do IO<Unit>:
        Check.cleanup(cleanup)
        IO.print(outcome(result))
        IO.print(retained(reason))

def later(controller: Abort.AbortController<String>) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(100)
    won : Bool <- Abort.abort(String, controller, Some{"stop"})
    return Unit{}

def exchange(+mode: String, family: String, port: String, signal: Abort.AbortSignal<String>) -> IO(Query.Report<String>):
  Query.query(String, Test.endpoint(family), Scalar.decimal(port, 0), Bool.pick(U32, String.eq(mode, "timeout") || String.eq(mode, "noise"), 500, 5000), signal, Bool.pick(U32, String.eq(mode, "bad-query"), 65536, 42), 256, Message.Question{Name.Name{Nil{}}, 1, 1}, Bool.pick(U32, String.eq(mode, "zero"), 0, 7))

def run(parentAbort: Bool, mode: String, family: String, port: String, +controller: Abort.AbortController<String>) -> IO(Unit):
  match parentAbort:
    case False{}:
      do IO<Unit>:
        result : Query.Report<String> <- exchange(mode, family, port, Abort.signal(String, controller))
        status(result)
    case True{}:
      do IO<Unit>:
        task : Chan(Unit) <- IO.fork(Unit, later(controller))
        result : Query.Report<String> <- exchange(mode, family, port, Abort.signal(String, controller))
        IO.join(Unit, task)
        status(result)

def prepare(pre: Bool, defaultReason: Bool, controller: Abort.AbortController<String>) -> IO(Unit):
  match pre:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, Bool.pick(Maybe<&2, String>, defaultReason, None{}, Some{"stop"}))
        return Unit{}

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> family <> port <> Nil{}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        prepare(String.eq(mode, "pre") || String.eq(mode, "pre-default"), String.eq(mode, "pre-default"), controller)
        run(String.eq(mode, "parent"), mode, family, port, controller)
        Abort.dispose(String, controller)
        IO.print("PASS DNS TCP query")
    case _: IO.die(Unit, 1, "expected mode family port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
