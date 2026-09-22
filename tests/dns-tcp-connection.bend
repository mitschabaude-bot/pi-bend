import Base
import ../packages/runtime/src/socket-interrupt.bend as Interrupt
import ../packages/runtime/src/dns-transport.bend as TCP
import ../packages/runtime/src/dns-message.bend as Frame
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/abortable-socket.bend as SocketIO
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./abortable-socket.bend as Test

def endpoint(family: String) -> Connect.Address:
  match family:
    case "6": Connect.V6{IPv6.Address{0, 0, 0, 1}, 0}
    case _: Connect.V4{IPv4.Address{2130706433}}

def connected(result: Result<&2, &1, Connect.Error<String>, Socket>) -> IO(Socket):
  match result:
    case Done{socket}: IO.pure(Socket, socket)
    case Fail{_}: IO.die(Socket, 1, "connect failed")

def close(connection: TCP.Connection<String>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, Interrupt.Error, Unit> <- TCP.closeTcpConnection(String, connection)
    Test.cleanup(result)

def queryResult(result: Result<&2, &2, Message.Error, List<&2, U32>>) -> IO(List<&2, U32>):
  match result:
    case Done{bytes}: IO.pure(List<&2, U32>, bytes)
    case Fail{_}: IO.die(List<&2, U32>, 1, "query encoding failed")

def sent(pair: TCP.Connection<String> & Result<&2, &2, TCP.TcpConnectionError<String>, Unit>) -> IO(TCP.Connection<String>):
  match pair:
    case (connection, Done{_}): IO.pure(TCP.Connection<String>, connection)
    case (connection, Fail{_}):
      do IO<TCP.Connection<String>>:
        close(connection)
        IO.die(TCP.Connection<String>, 1, "send failed")

def send(connection: TCP.Connection<String>, id: U32) -> IO(TCP.Connection<String>):
  do IO<TCP.Connection<String>>:
    bytes : List<&2, U32> <- queryResult(Message.query(id, 256, Message.Question{Name.Name{Nil{}}, 1, 1}))
    result : TCP.Connection<String> & Result<&2, &2, TCP.TcpConnectionError<String>, Unit> <- TCP.send(String, connection, bytes)
    sent(result)

def valid(id: U32, parsed: Result<&2, &2, Message.Error, Message.Message>) -> Bool:
  match parsed:
    case Done{Message.Message{_, Message.Header{actual, flags, _, _, _, _}, _, _, _, _}}: U32.is_eq(id, actual) && U32.is_eq(flags, 33152)
    case _: False{}

def packet(id: U32, next: TCP.Next<String>) -> IO(TCP.Connection<String>):
  match next:
    case TCP.Next{connection, Done{Some{bytes}}}:
      do IO<TCP.Connection<String>>:
        Test.assertTrue(valid(id, Message.parse(bytes)), "wrong response frame")
        return connection
    case TCP.Next{connection, _}:
      do IO<TCP.Connection<String>>:
        close(connection)
        IO.die(TCP.Connection<String>, 1, "expected response frame")

def abortReason(reason: Abort.AbortReason<String>) -> Bool:
  match reason:
    case Abort.Supplied{why}: String.eq(why, "stop")
    case _: False{}

def transportError(kind: String, error: SocketIO.Error<String>) -> Bool:
  match error:
    case SocketIO.Aborted{why}: String.eq(kind, "abort") && abortReason(why)
    case _: False{}

def framingError(kind: String, error: Frame.TcpFrameError) -> Bool:
  match error:
    case Frame.IncompleteFrame{}: String.eq(kind, "cut")
    case _: False{}

def terminalError(kind: String, error: TCP.TcpConnectionError<String>) -> Bool:
  match error:
    case TCP.Framing{why}: framingError(kind, why)
    case TCP.Transport{_, why}: transportError(kind, why)
    case TCP.InvalidReadSize{}: String.eq(kind, "zero")

def terminalValue(kind: String, value: Maybe<&2, List<&2, U32>>) -> Bool:
  match value:
    case None{}: String.eq(kind, "eof")
    case Some{_}: False{}

def terminalResult(kind: String, value: Result<&2, &2, TCP.TcpConnectionError<String>, Maybe<&2, List<&2, U32>>>) -> Bool:
  match value:
    case Fail{why}: terminalError(kind, why)
    case Done{value}: terminalValue(kind, value)

def terminalChecked(valid: Bool, connection: TCP.Connection<String>) -> IO(TCP.Connection<String>):
  match valid:
    case True{}: IO.pure(TCP.Connection<String>, connection)
    case False{}:
      do IO<TCP.Connection<String>>:
        close(connection)
        IO.die(TCP.Connection<String>, 1, "unexpected terminal result")

def terminal(kind: String, next: TCP.Next<String>) -> IO(TCP.Connection<String>):
  match next:
    case TCP.Next{connection, result}: terminalChecked(terminalResult(kind, result), connection)

def finished(+kind: String, connection: TCP.Connection<String>) -> IO(Unit):
  do IO<Unit>:
    next : TCP.Next<String> <- TCP.receiveTcpConnection(String, connection, 7)
    connection : TCP.Connection<String> <- terminal(kind, next)
    next : TCP.Next<String> <- TCP.receiveTcpConnection(String, connection, 7)
    connection : TCP.Connection<String> <- terminal(kind, next)
    close(connection)

def packets(count: Nat, +id: U32, +maximum: U32, connection: TCP.Connection<String>) -> IO(Unit):
  match count:
    case Zero{}: finished("eof", connection)
    case Succ{rest}:
      do IO<Unit>:
        next : TCP.Next<String> <- TCP.receiveTcpConnection(String, connection, maximum)
        connection : TCP.Connection<String> <- packet(id, next)
        packets(rest, (id - 1 : U32), maximum, connection)

# Exercise buffered cancellation deterministically, independent of how the OS
# splits a coalesced write. Only this test constructs a pending input suffix.
def buffered(connection: TCP.Connection<String>) -> TCP.Connection<String>:
  match connection:
    case TCP.Connection{socket, _}: TCP.Connection{socket, TCP.Reading{Frame.newTcpFrame(), 0 <> 1 <> 99 <> Nil{}}}

def badWrite(pair: TCP.Connection<String> & Result<&2, &2, TCP.TcpConnectionError<String>, Unit>) -> IO(TCP.Connection<String>):
  match pair:
    case (connection, Fail{TCP.Framing{Frame.TcpFrameInvalidByte{256}}}): IO.pure(TCP.Connection<String>, connection)
    case (connection, _):
      do IO<TCP.Connection<String>>:
        close(connection)
        IO.die(TCP.Connection<String>, 1, "expected invalid write guard")

type Mode is Data:
  AbortRead{}
  BufferedAbort{}
  CutPrefix{}
  CutBody{}
  Pipeline{oneByte: Bool}

def parseMode(value: String) -> Mode:
  match value:
    case "abort": AbortRead{}
    case "buffered": BufferedAbort{}
    case "cut-prefix": CutPrefix{}
    case "cut-body": CutBody{}
    case "one-byte": Pipeline{True{}}
    case _: Pipeline{False{}}

def run(mode: Mode, +controller: Abort.AbortController<String>, connection: TCP.Connection<String>) -> IO(Unit):
  match mode:
    case AbortRead{}:
      do IO<Unit>:
        connection : TCP.Connection<String> <- send(connection, 1)
        task : Chan(TCP.Next<String>) <- IO.fork(TCP.Next<String>, TCP.receiveTcpConnection(String, connection, 7))
        IO.sleep(10)
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        next : TCP.Next<String> <- IO.join(TCP.Next<String>, task)
        connection : TCP.Connection<String> <- terminal("abort", next)
        finished("abort", connection)
    case BufferedAbort{}:
      do IO<Unit>:
        connection : TCP.Connection<String> <- send(connection, 1)
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        finished("abort", buffered(connection))
    case CutPrefix{}:
      do IO<Unit>:
        connection : TCP.Connection<String> <- send(connection, 1)
        finished("cut", connection)
    case CutBody{}:
      do IO<Unit>:
        connection : TCP.Connection<String> <- send(connection, 1)
        finished("cut", connection)
    case Pipeline{oneByte}:
      do IO<Unit>:
        rejected : TCP.Connection<String> & Result<&2, &2, TCP.TcpConnectionError<String>, Unit> <- TCP.send(String, connection, 256 <> Nil{})
        connection : TCP.Connection<String> <- badWrite(rejected)
        next : TCP.Next<String> <- TCP.receiveTcpConnection(String, connection, 0)
        connection : TCP.Connection<String> <- terminal("zero", next)
        connection : TCP.Connection<String> <- send(connection, 1)
        connection : TCP.Connection<String> <- send(connection, 2)
        connection : TCP.Connection<String> <- send(connection, 3)
        packets(3n, 3, Bool.pick(U32, oneByte, 1, 65535), connection)

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> family <> port <> Nil{}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        result : Result<&2, &1, Connect.Error<String>, Socket> <- Connect.connect(String, endpoint(family), Scalar.decimal(port, 0), Abort.signal(String, controller))
        socket : Socket <- connected(result)
        adopted : Result<&2, &1, SocketIO.Error<String>, SocketIO.Owner<String>> <- SocketIO.create(String, socket, Abort.signal(String, controller))
        socket : SocketIO.Owner<String> <- Test.opened(adopted)
        run(parseMode(mode), controller, TCP.adopt(String, socket))
        Abort.dispose(String, controller)
        IO.print("PASS DNS TCP connection")
    case _: IO.die(Unit, 1, "expected mode family port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
