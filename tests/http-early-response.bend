import Base
import ../packages/runtime/src/http-exchange.bend as Exchange
import ../packages/runtime/src/http-message.bend as Request
import ../packages/runtime/src/http-message.bend as Body
import ../packages/runtime/src/http-message.bend as Headers
import ../packages/runtime/src/http-message.bend as H
import ../packages/runtime/src/abort.bend as A
import ./http-socket-exchange.bend as Fixture
import ./tcp-bytes-probe.bend as Probe
import ./tcp-bytes-backpressure.bend as Payload

def checkSignal(reason: Maybe<&2, A.AbortReason<String>>) -> IO(Unit):
  match reason:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}: IO.die(Unit, 1, "internal upload stop aborted caller signal")

def cases(count: Nat, +port: U32, +index: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        result : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Fixture.requested(socket, A.signal(String, controller), 7, Request.prepareBufferedRequest("POST", "/", Headers.appendField(Headers.new(), H.Header{"host", "example.test"}), Body.Bytes{Payload.payload(256n, Nil{})}))
        text : String <- Fixture.adopted((index % 5 : U32), result)
        reason : Maybe<&2, A.AbortReason<String>> <- A.reason(String, A.signal(String, controller))
        checkSignal(reason)
        A.dispose(String, controller)
        IO.print(text)
        cases(rest, port, (index + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(15n, Probe.port(args), 0)
