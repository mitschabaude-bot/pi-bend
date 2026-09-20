import Base
import ../packages/runtime/src/dns-tcp-session.bend as Session
import ../packages/runtime/src/dns-tcp-peer.bend as Peer
import ../packages/runtime/src/dns-pending.bend as Pending
import ../packages/runtime/src/dns-tcp-connection.bend as TCP
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-tcp-frame.bend as Frame
import ../packages/runtime/src/dns-name.bend as Name
import ../packages/runtime/src/abortable-socket.bend as SocketIO
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-tcp-connection.bend as Test
import ./abortable-socket.bend as Check

def entries(values: List<&2, Pending.Entry<U32>>, acc: String) -> String:
  match values:
    case Nil{}: acc
    case Pending.Entry{_, token, _} <> rest: entries(rest, acc ++ U32.show(token) ++ ",")

def failure(value: Session.Failure<String>) -> String:
  match value:
    case Session.EndOfStream{}: "eof"
    case Session.Transport{TCP.Framing{Frame.IncompleteFrame{}}}: "framing"
    case Session.Transport{TCP.Transport{_, SocketIO.Aborted{Abort.Supplied{"stop"}}}}: "abort"
    case _: "unexpected"

def describe(value: Session.Outcome<String, U32>) -> String:
  match value:
    case Session.Submitted{_}: "submitted"
    case Session.Cancelled{None{}}: "cancel:none"
    case Session.Cancelled{Some{Pending.Entry{_, token, _}}}: "cancel:" ++ U32.show(token)
    case Session.Rejected{Session.Registration{Pending.DuplicateId{}}}: "duplicate"
    case Session.Rejected{Session.Query{_}}: "query"
    case Session.Rejected{Session.InvalidReadSize{}}: "zero"
    case Session.Rejected{Session.Stopped{_}}: "stopped"
    case Session.Rejected{_}: "unexpected"
    case Session.Ended{why, outstanding}: "ended:" ++ failure(why) ++ ":" ++ entries(outstanding, "")
    case Session.Response{Pending.Answer{token, _}}: "answer:" ++ U32.show(token)
    case Session.Response{Pending.Truncated{token, _}}: "truncated:" ++ U32.show(token)
    case Session.Response{Pending.Ignored{_}}: "ignored"

def observed(step: Session.Step<String, U32>) -> IO(Session.Session<String, U32>):
  match step:
    case Session.Step{session, event}:
      do IO<Session.Session<String, U32>>:
        IO.print(describe(event))
        return session

def closed(value: Session.Closed<U32>) -> IO(Unit):
  match value:
    case Session.Closed{outstanding, result}:
      do IO<Unit>:
        Check.cleanup(result)
        IO.print("closed:" ++ entries(outstanding, ""))

def close(session: Session.Session<String, U32>) -> IO(Unit):
  do IO<Unit>:
    result : Session.Closed<U32> <- Session.close(String, U32, session)
    closed(result)

def send(session: Session.Session<String, U32>, +id: U32) -> IO(Session.Session<String, U32>):
  do IO<Session.Session<String, U32>>:
    step : Session.Step<String, U32> <- Session.submit(String, U32, session, id, 256, Message.Question{Name.Name{Nil{}}, 1, 1}, id)
    observed(step)

def read(session: Session.Session<String, U32>, size: U32) -> IO(Session.Session<String, U32>):
  do IO<Session.Session<String, U32>>:
    step : Session.Step<String, U32> <- Session.receive(String, U32, session, size)
    observed(step)

def finish(session: Session.Session<String, U32>) -> IO(Unit):
  do IO<Unit>:
    session : Session.Session<String, U32> <- read(session, 7)
    session : Session.Session<String, U32> <- read(session, 7)
    session : Session.Session<String, U32> <- send(session, 3)
    close(session)

def replies(count: Nat, session: Session.Session<String, U32>) -> IO(Unit):
  match count:
    case Zero{}: finish(session)
    case Succ{rest}:
      do IO<Unit>:
        session : Session.Session<String, U32> <- read(session, 3)
        replies(rest, session)

type Mode is Data:
  Replies{}
  Eof{}
  AbortRead{}
  AbortWrite{}
  CloseEarly{}
  CancelQueries{}

def mode(value: String) -> Mode:
  match value:
    case "eof": Eof{}
    case "cut": Eof{}
    case "abort": AbortRead{}
    case "write-abort": AbortWrite{}
    case "close": CloseEarly{}
    case "cancel": CancelQueries{}
    case _: Replies{}

def run(selected: Mode, controller: Abort.AbortController<String>, session: Session.Session<String, U32>, +ticket: Pending.Ticket) -> IO(Unit):
  match selected:
    case CancelQueries{}:
      do IO<Unit>:
        session : Session.Session<String, U32> <- send(session, 2)
        session : Session.Session<String, U32> <- observed(Session.cancel(String, U32, session, ticket))
        session : Session.Session<String, U32> <- read(session, 3)
        session : Session.Session<String, U32> <- send(session, 1)
        session : Session.Session<String, U32> <- observed(Session.cancel(String, U32, session, ticket))
        replies(2n, session)
    case Replies{}:
      do IO<Unit>:
        session : Session.Session<String, U32> <- send(session, 2)
        session : Session.Session<String, U32> <- send(session, 1)
        session : Session.Session<String, U32> <- send(session, 65536)
        session : Session.Session<String, U32> <- read(session, 0)
        replies(4n, session)
    case Eof{}:
      do IO<Unit>:
        session : Session.Session<String, U32> <- send(session, 2)
        finish(session)
    case CloseEarly{}:
      do IO<Unit>:
        session : Session.Session<String, U32> <- send(session, 2)
        close(session)
    case AbortRead{}:
      do IO<Unit>:
        session : Session.Session<String, U32> <- send(session, 2)
        task : Chan(Session.Step<String, U32>) <- IO.fork(Session.Step<String, U32>, Session.receive(String, U32, session, 7))
        IO.sleep(10)
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        step : Session.Step<String, U32> <- IO.join(Session.Step<String, U32>, task)
        session : Session.Session<String, U32> <- observed(step)
        finish(session)
    case AbortWrite{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        session : Session.Session<String, U32> <- send(session, 2)
        finish(session)

def initial(selected: Mode, controller: Abort.AbortController<String>, step: Session.Step<String, U32>) -> IO(Unit):
  match step:
    case Session.Step{session, Session.Submitted{ticket}}:
      do IO<Unit>:
        IO.print("submitted")
        run(selected, controller, session, ticket)
    case Session.Step{session, _}:
      do IO<Unit>:
        close(session)
        IO.die(Unit, 1, "initial submission failed")

def opened(selected: Mode, controller: Abort.AbortController<String>, result: Result<&2, &1, Peer.Error<String>, Peer.Peer<String>>) -> IO(Unit):
  match result:
    case Done{peer}:
      do IO<Unit>:
        step : Session.Step<String, U32> <- Session.submit(String, U32, Session.adopt(String, U32, peer), 1, 256, Message.Question{Name.Name{Nil{}}, 1, 1}, 1)
        initial(selected, controller, step)
    case Fail{_}: IO.die(Unit, 1, "peer creation failed")

def args(values: List<String>) -> IO(Unit):
  match values:
    case selected <> family <> port <> Nil{}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        result : Result<&2, &1, Connect.Error<String>, Socket> <- Connect.connect(String, Test.endpoint(family), Scalar.decimal(port, 0), Abort.signal(String, controller))
        socket : Socket <- Test.connected(result)
        result : Result<&2, &1, Peer.Error<String>, Peer.Peer<String>> <- Peer.create(String, socket, Abort.signal(String, controller))
        opened(mode(selected), controller, result)
        Abort.dispose(String, controller)
        IO.print("PASS DNS TCP session")
    case _: IO.die(Unit, 1, "expected mode family port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
