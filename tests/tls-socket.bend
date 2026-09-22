import Base
import ../packages/runtime/src/tls-socket.bend as TLS
import ../packages/runtime/src/tls13-client.bend as Client
import ../packages/runtime/src/tls13-record.bend as Record
import ../packages/runtime/src/socket.bend as Socket
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Decimal
import ./tls13-client.bend as Session
import ./aes128-gcm.bend as Bytes
import ./socket-writer.bend as Check
import ./tcp-bytes-backpressure.bend as Payload

def checked(result: Result<&2, &2, TLS.Error<String>, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "TLS operation failed")

def connected(result: Result<&2, &1, TLS.Error<String>, TLS.Connection<String>>) -> IO(TLS.Connection<String>):
  match result:
    case Done{value}: IO.pure(TLS.Connection<String>, value)
    case Fail{_}: IO.die(TLS.Connection<String>, 1, "TLS connection failed")

def received(pair: TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>>, expected: U32) -> IO(TLS.Connection<String>):
  match pair:
    case (connection, Done{byte <> Nil{}}):
      do IO<TLS.Connection<String>>:
        Check.require(U32.is_eq(byte, expected), "incorrect TLS application byte")
        return connection
    case _: IO.die(TLS.Connection<String>, 1, "TLS read failed")

def terminal(pair: TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>>, abrupt: Bool) -> IO(TLS.Connection<String>):
  match pair:
    case (connection, Done{Nil{}}):
      do IO<TLS.Connection<String>>:
        Check.require(Bool.not(abrupt), "unauthenticated EOF accepted")
        return connection
    case (connection, Fail{TLS.Protocol{Client.RecordFailure{Record.Truncated{}}}}):
      do IO<TLS.Connection<String>>:
        Check.require(abrupt, "clean TLS closure rejected")
        return connection
    case _: IO.die(TLS.Connection<String>, 1, "incorrect TLS EOF result")

def transfer(pair: TLS.Connection<String> & TLS.Writer<String>, abrupt: Bool) -> IO(Unit):
  match pair:
    case (connection, +writer):
      do IO<Unit>:
        result : Result<&2, &2, TLS.Error<String>, Unit> <- TLS.send(String, writer, Payload.payload(80n, Nil{}))
        checked(result)
        result : Result<&2, &2, TLS.Error<String>, Unit> <- TLS.shutdownWrite(String, writer)
        checked(result)
        part : TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>> <- TLS.recv(String, connection, 1)
        connection : TLS.Connection<String> <- received(part, 97)
        part : TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>> <- TLS.recv(String, connection, 1)
        connection : TLS.Connection<String> <- received(part, 99)
        part : TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>> <- TLS.recv(String, connection, 1)
        connection : TLS.Connection<String> <- received(part, 107)
        part : TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>> <- TLS.recv(String, connection, 1)
        connection : TLS.Connection<String> <- terminal(part, abrupt)
        result : Result<&2, &2, TLS.Error<String>, Unit> <- TLS.dispose(String, connection)
        checked(result)
        IO.print("PASS")

def cancelled(pair: TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>>) -> IO(Unit):
  match pair:
    case (connection, Fail{TLS.Network{Socket.SocketAborted{Abort.Supplied{why}}}}):
      do IO<Unit>:
        Check.require(String.eq(why, "stop"), "TLS lost cancellation reason")
        result : Result<&2, &2, TLS.Error<String>, Unit> <- TLS.dispose(String, connection)
        checked(result)
    case _: IO.die(Unit, 1, "TLS cancellation not observed")

def cancelRead(connection: TLS.Connection<String>, controller: Abort.AbortController<String>) -> IO(Unit):
  do IO<Unit>:
    part : TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>> <- TLS.recv(String, connection, 1)
    connection : TLS.Connection<String> <- received(part, 82)
    task : Chan(TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>>) <- IO.fork(TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>>, TLS.recv(String, connection, 1))
    won : Bool <- Abort.abort(String, controller, Some{"stop"})
    Check.require(won, "abort already settled")
    part : TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>> <- IO.join(TLS.Connection<String> & Result<&2, &2, TLS.Error<String>, List<&2, U32>>, task)
    cancelled(part)
    IO.print("PASS")

def established(connection: TLS.Connection<String>, controller: Abort.AbortController<String>, mode: String, cancel: Bool) -> IO(Unit):
  match cancel:
    case True{}: cancelRead(connection, controller)
    case False{}: transfer(TLS.borrowWriter(String, connection), String.eq(mode, "abrupt"))

def opened(initial: Result<&2, &1, TLS.Error<String>, TLS.Connection<String>>, controller: Abort.AbortController<String>, +mode: String) -> IO(Unit):
  match initial:
    case Fail{TLS.WriteQueueFull{1}}:
      do IO<Unit>:
        Check.require(String.eq(mode, "limit"), "unexpected write queue overflow")
        IO.print("PASS")
    case initial:
      do IO<Unit>:
        Check.require(Bool.not(String.eq(mode, "limit")), "write queue limit ignored")
        connection : TLS.Connection<String> <- connected(initial)
        negotiated : Result<&2, &1, TLS.Error<String>, TLS.Connection<String>> <- TLS.awaitHandshake(String, connection)
        connection : TLS.Connection<String> <- connected(negotiated)
        established(connection, controller, mode, String.eq(mode, "cancel"))

def options(limited: Bool) -> TLS.Options:
  match limited:
    case True{}: TLS.Options{1048576, 1, 16384}
    case False{}: TLS.defaults()

def run(port: U32, certificate: List<&2, U32>, +mode: String) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<String> <- Abort.new(String)
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
    adoption : Result<&2, &1, Socket.SocketErrorOfSocket<String>, Socket.Owner<String>> <- Socket.create(String, socket, Abort.signal(String, controller))
    owner : Socket.Owner<String> <- Check.opened(adoption)
    initial : Result<&2, &1, TLS.Error<String>, TLS.Connection<String>> <- TLS.start(String, owner, Some{"localhost"}, Client.Authorization{chain => Session.pin(certificate, chain)}, options(String.eq(mode, "limit")))
    opened(initial, controller, mode)
    Abort.dispose(String, controller)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case port <> cert <> mode <> Nil{}: run(Decimal.decimal(port, 0), Bytes.bytes(cert), mode)
    case _: IO.die(Unit, 1, "expected port certificate mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
