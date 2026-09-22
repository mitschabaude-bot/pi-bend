import Base
import ../packages/runtime/src/dns-message.bend as Edns
import ../packages/runtime/src/dns-transport.bend as Session
import ../packages/runtime/src/dns-transport.bend as Peer
import ../packages/runtime/src/dns-transport.bend as Pending
import ../packages/runtime/src/dns-transport.bend as TCP
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Frame
import ../packages/runtime/src/dns-message.bend as Name
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
    case Session.TcpSessionTransport{TCP.Framing{Frame.IncompleteFrame{}}}: "framing"
    case Session.TcpSessionTransport{TCP.Transport{_, SocketIO.Aborted{Abort.Supplied{"stop"}}}}: "abort"
    case _: "unexpected"

def describe(value: Session.Outcome<String, U32>) -> String:
  match value:
    case Session.Submitted{_}: "submitted"
    case Session.Cancelled{None{}}: "cancel:none"
    case Session.Cancelled{Some{Pending.Entry{_, token, _}}}: "cancel:" ++ U32.show(token)
    case Session.Rejected{Session.Registration{Pending.DuplicateId{}}}: "duplicate"
    case Session.Rejected{Session.Extension{Edns.EdnsInvalidField{}}}: "extension:field"
    case Session.Rejected{Session.Extension{Edns.InvalidByte{value}}}: "extension:byte:" ++ U32.show(value)
    case Session.Rejected{Session.Extension{Edns.TooLong{}}}: "extension:long"
    case Session.Rejected{Session.Query{_}}: "query"
    case Session.Rejected{Session.TcpSessionInvalidReadSize{}}: "zero"
    case Session.Rejected{Session.Stopped{_}}: "stopped"
    case Session.Rejected{_}: "unexpected"
    case Session.TcpSessionEnded{why, outstanding}: "ended:" ++ failure(why) ++ ":" ++ entries(outstanding, "")
    case Session.Response{Pending.Answer{token, _}}: "answer:" ++ U32.show(token)
    case Session.Response{Pending.Truncated{token, _}}: "truncated:" ++ U32.show(token)
    case Session.Response{Pending.Ignored{_}}: "ignored"

def observed(step: Session.TcpSessionStep<String, U32>) -> IO(Session.Session<String, U32>):
  match step:
    case Session.TcpSessionStep{session, event}:
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
    result : Session.Closed<U32> <- Session.closeTcpSession(String, U32, session)
    closed(result)

def send(session: Session.Session<String, U32>, +id: U32) -> IO(Session.Session<String, U32>):
  do IO<Session.Session<String, U32>>:
    step : Session.TcpSessionStep<String, U32> <- Session.submit(String, U32, session, id, 256, Message.Question{Name.Name{Nil{}}, 1, 1}, id)
    observed(step)

def extension(payload: U32, byte: U32) -> Edns.Query:
  Edns.Query{payload, True{}, Edns.Option{65001, byte <> 255 <> Nil{}} <> Edns.Option{65001, Nil{}} <> Nil{}}

def ednsObserved(step: Session.TcpSessionStep<String, U32>) -> IO(Session.Session<String, U32>):
  match step:
    case Session.TcpSessionStep{session, Session.Submitted{Pending.Ticket{id, serial}}}:
      do IO<Session.Session<String, U32>>:
        IO.print("ticket:" ++ U32.show(id) ++ ":" ++ U32.show(serial))
        return session
    case other: observed(other)

def sendEdns(session: Session.Session<String, U32>, +id: U32, payload: U32, byte: U32) -> IO(Session.Session<String, U32>):
  do IO<Session.Session<String, U32>>:
    step : Session.TcpSessionStep<String, U32> <- Session.submitEdns(String, U32, session, id, 256, Message.Question{Name.Name{Nil{}}, 1, 1}, id, extension(payload, byte))
    ednsObserved(step)

def read(session: Session.Session<String, U32>, size: U32) -> IO(Session.Session<String, U32>):
  do IO<Session.Session<String, U32>>:
    step : Session.TcpSessionStep<String, U32> <- Session.receiveTcpSession(String, U32, session, size)
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
  Extended{}
  Eof{}
  AbortRead{}
  AbortWrite{}
  CloseEarly{}
  CancelQueries{}

def mode(value: String) -> Mode:
  match value:
    case "edns": Extended{}
    case "eof": Eof{}
    case "cut": Eof{}
    case "abort": AbortRead{}
    case "write-abort": AbortWrite{}
    case "close": CloseEarly{}
    case "cancel": CancelQueries{}
    case _: Replies{}

def run(selected: Mode, controller: Abort.AbortController<String>, session: Session.Session<String, U32>, +ticket: Pending.Ticket) -> IO(Unit):
  match selected:
    case Extended{}:
      do IO<Unit>:
        session : Session.Session<String, U32> <- sendEdns(session, 1, 1232, 0)
        session : Session.Session<String, U32> <- sendEdns(session, 2, 65536, 0)
        session : Session.Session<String, U32> <- sendEdns(session, 2, 1232, 256)
        session : Session.Session<String, U32> <- sendEdns(session, 65536, 1232, 0)
        session : Session.Session<String, U32> <- sendEdns(session, 2, 1232, 0)
        session : Session.Session<String, U32> <- observed(Session.cancelTcpSession(String, U32, session, ticket))
        session : Session.Session<String, U32> <- read(session, 3)
        session : Session.Session<String, U32> <- send(session, 1)
        session : Session.Session<String, U32> <- observed(Session.cancelTcpSession(String, U32, session, ticket))
        session : Session.Session<String, U32> <- read(session, 3)
        session : Session.Session<String, U32> <- read(session, 3)
        session : Session.Session<String, U32> <- read(session, 3)
        session : Session.Session<String, U32> <- sendEdns(session, 3, 65536, 0)
        close(session)
    case CancelQueries{}:
      do IO<Unit>:
        session : Session.Session<String, U32> <- send(session, 2)
        session : Session.Session<String, U32> <- observed(Session.cancelTcpSession(String, U32, session, ticket))
        session : Session.Session<String, U32> <- read(session, 3)
        session : Session.Session<String, U32> <- send(session, 1)
        session : Session.Session<String, U32> <- observed(Session.cancelTcpSession(String, U32, session, ticket))
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
        task : Chan(Session.TcpSessionStep<String, U32>) <- IO.fork(Session.TcpSessionStep<String, U32>, Session.receiveTcpSession(String, U32, session, 7))
        IO.sleep(10)
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        step : Session.TcpSessionStep<String, U32> <- IO.join(Session.TcpSessionStep<String, U32>, task)
        session : Session.Session<String, U32> <- observed(step)
        finish(session)
    case AbortWrite{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        session : Session.Session<String, U32> <- send(session, 2)
        finish(session)

def initial(selected: Mode, controller: Abort.AbortController<String>, step: Session.TcpSessionStep<String, U32>) -> IO(Unit):
  match step:
    case Session.TcpSessionStep{session, Session.Submitted{ticket}}:
      do IO<Unit>:
        IO.print("submitted")
        run(selected, controller, session, ticket)
    case Session.TcpSessionStep{session, _}:
      do IO<Unit>:
        close(session)
        IO.die(Unit, 1, "initial submission failed")

def first(extended: Bool, session: Session.Session<String, U32>) -> IO(Session.TcpSessionStep<String, U32>):
  match extended:
    case True{}: Session.submitEdns(String, U32, session, 1, 256, Message.Question{Name.Name{Nil{}}, 1, 1}, 1, extension(1232, 0))
    case False{}: Session.submit(String, U32, session, 1, 256, Message.Question{Name.Name{Nil{}}, 1, 1}, 1)

def isExtended(value: Mode) -> Bool:
  match value:
    case Extended{}: True{}
    case _: False{}

def opened(+selected: Mode, controller: Abort.AbortController<String>, result: Result<&2, &1, Peer.TcpPeerError<String>, Peer.Peer<String>>) -> IO(Unit):
  match result:
    case Done{peer}:
      do IO<Unit>:
        step : Session.TcpSessionStep<String, U32> <- first(isExtended(selected), Session.adoptTcpSession(String, U32, peer))
        initial(selected, controller, step)
    case Fail{_}: IO.die(Unit, 1, "peer creation failed")

def args(values: List<String>) -> IO(Unit):
  match values:
    case selected <> family <> port <> Nil{}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        result : Result<&2, &1, Connect.Error<String>, Socket> <- Connect.connect(String, Test.endpoint(family), Scalar.decimal(port, 0), Abort.signal(String, controller))
        socket : Socket <- Test.connected(result)
        result : Result<&2, &1, Peer.TcpPeerError<String>, Peer.Peer<String>> <- Peer.createTcpPeer(String, socket, Abort.signal(String, controller))
        opened(mode(selected), controller, result)
        Abort.dispose(String, controller)
        IO.print("PASS DNS TCP session")
    case _: IO.die(Unit, 1, "expected mode family port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
