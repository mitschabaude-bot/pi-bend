import Base
import ../packages/runtime/src/dns-transport.bend as Recover
import ../packages/runtime/src/dns-transport.bend as Query
import ../packages/runtime/src/dns-transport.bend as Session
import ../packages/runtime/src/dns-transport.bend as TCP
import ../packages/runtime/src/abortable-socket.bend as SocketIO
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/socket-interrupt.bend as Interrupt
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./abortable-socket.bend as Test

def check(name: String, expected: Bool, report: Query.Completed<String>) -> IO(Unit):
  do IO<Unit>:
    actual : Bool <- Recover.reset(String, report)
    Test.assertTrue(Bool.not(Bool.xor(expected, actual)), name)

def transport(operation: TCP.Operation, error: SocketIO.Error<Deadline.Cause<String>>) -> Query.TcpQueryError<String>:
  Query.Terminated{Session.TcpSessionTransport{TCP.Transport{operation, error}}}

def cases(+code: U32) -> IO(Unit):
  do IO<Unit>:
    check("length reset", True{}, Query.Completed{Fail{transport(TCP.ReadingLength{}, SocketIO.SocketError{code, "reset"})}, Done{Unit{}}})
    check("write reset", False{}, Query.Completed{Fail{transport(TCP.Sending{}, SocketIO.SocketError{code, "reset"})}, Done{Unit{}}})
    check("payload reset", False{}, Query.Completed{Fail{transport(TCP.ReadingPayload{}, SocketIO.SocketError{code, "reset"})}, Done{Unit{}}})
    check("cleanup failure", False{}, Query.Completed{Fail{transport(TCP.ReadingLength{}, SocketIO.SocketError{code, "reset"})}, Fail{Interrupt.Error{code, "cleanup must win"}}})
    check("connect reset", False{}, Query.Completed{Fail{Query.TcpQueryConnection{Connect.SocketError{code, "connect"}}}, Done{Unit{}}})
    check("other socket code", False{}, Query.Completed{Fail{transport(TCP.ReadingLength{}, SocketIO.SocketError{0, "other"})}, Done{Unit{}}})
    check("parent abort", False{}, Query.Completed{Fail{transport(TCP.ReadingLength{}, SocketIO.Aborted{Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{"stop"}}}})}, Done{Unit{}}})
    check("default abort", False{}, Query.Completed{Fail{transport(TCP.ReadingLength{}, SocketIO.Aborted{Abort.DefaultAbort{}})}, Done{Unit{}}})
    check("deadline", False{}, Query.Completed{Fail{transport(TCP.ReadingLength{}, SocketIO.Aborted{Abort.Supplied{Deadline.Expired{}}})}, Done{Unit{}}})
    check("EOF", False{}, Query.Completed{Fail{Query.Terminated{Session.EndOfStream{}}}, Done{Unit{}}})
    IO.print("PASS reset policy")

def args(values: List<String>) -> IO(Unit):
  match values:
    case code <> Nil{}: cases(Scalar.decimal(code, 0))
    case _: IO.die(Unit, 1, "expected host ECONNRESET")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
