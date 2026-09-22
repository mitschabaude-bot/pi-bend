import Base
import ../packages/runtime/src/tls-socket.bend as TLS
import ../packages/runtime/src/tls13-client.bend as Client
import ../packages/runtime/src/socket.bend as Socket
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as Request
import ../packages/runtime/src/http-response.bend as Response
import ../packages/runtime/test/utf8-runner.bend as Decimal
import ./tls13-client.bend as Session
import ./tls-socket.bend as TLSCheck
import ./aes128-gcm.bend as Bytes
import ./socket-writer.bend as Check
import ./tcp-bytes-backpressure.bend as Payload
import ./http-socket-exchange.bend as HTTPCheck

def started(connection: TLS.Connection<String>, request: Result<&2, &2, Request.RequestError, Request.BufferedRequestPrepared>) -> IO(Result<&2, &1, HTTP.StartError<String>, HTTP.Exchange<String>>):
  match request:
    case Fail{_}: IO.die(Result<&2, &1, HTTP.StartError<String>, HTTP.Exchange<String>>, 1, "invalid HTTPS fixture")
    case Done{request}:
      HTTP.startTLSExchange(~String, connection, request, 7, Response.Limits{4096n, 65536n, 100n, 8n, Request.Limits{1024n, 1024n, 16384n, 100n}})

def parentAlive(reason: Maybe<&2, Abort.AbortReason<String>>) -> IO(Unit):
  match reason:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}: IO.die(Unit, 1, "HTTP close aborted the caller signal")

def run(port: U32, certificate: List<&2, U32>, mode: U32) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<String> <- Abort.new(String)
    socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
    adoption : Result<&2, &1, Socket.SocketErrorOfSocket<String>, Socket.Owner<String>> <- Socket.create(String, socket, Abort.signal(String, controller))
    owner : Socket.Owner<String> <- Check.opened(adoption)
    initial : Result<&2, &1, TLS.Error<String>, TLS.Connection<String>> <- TLS.start(String, owner, Some{"localhost"}, Client.Authorization{chain => Session.pin(certificate, chain)}, TLS.defaults())
    connection : TLS.Connection<String> <- TLSCheck.connected(initial)
    result : Result<&2, &1, HTTP.StartError<String>, HTTP.Exchange<String>> <- started(connection, Request.prepareBufferedRequest("POST", "/", Request.appendField(Request.new(), Request.Header{"host", "localhost"}), Request.Bytes{Payload.payload(256n, Nil{})}))
    summary : String <- HTTPCheck.adopted(mode, result)
    reason : Maybe<&2, Abort.AbortReason<String>> <- Abort.reason(String, Abort.signal(String, controller))
    parentAlive(reason)
    Abort.dispose(String, controller)
    IO.print(summary)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case port <> cert <> mode <> Nil{}: run(Decimal.decimal(port, 0), Bytes.bytes(cert), Decimal.decimal(mode, 0))
    case _: IO.die(Unit, 1, "expected port certificate mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
