import Base
import ../packages/runtime/src/http-exchange.bend as Exchange
import ../packages/runtime/src/http-response.bend as Stream
import ../packages/runtime/src/abort.bend as A
import ./http-socket-exchange.bend as Fixture
import ./tcp-bytes-probe.bend as Probe

def acknowledge(value: Stream.StreamEvent) -> IO(Unit):
  match value:
    case Stream.BodyData{_}: IO.print("ready")
    case _: IO.pure(Unit, Unit{})

def loop(fuel: Nat, next: Exchange.Next<String>, capture: Fixture.Capture) -> IO(String):
  match fuel next:
    case _ Exchange.Next{exchange, Fail{why}}: Fixture.ended(exchange, capture, Fixture.exchangeError(why))
    case _ Exchange.Next{exchange, Done{None{}}}: Fixture.ended(exchange, capture, "eof")
    case Zero{} Exchange.Next{exchange, _}: Fixture.stop(exchange, capture, "out-of-fuel")
    case Succ{rest} Exchange.Next{exchange, Done{Some{+value}}}:
      do IO<String>:
        acknowledge(value)
        next : Exchange.Next<String> <- Exchange.nextSocketExchange(String, exchange)
        loop(rest, next, Fixture.event(capture, value))

def started(result: Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>>) -> IO(String):
  match result:
    case Fail{_}: IO.die(String, 1, "unexpected start failure")
    case Done{exchange}:
      do IO<String>:
        next : Exchange.Next<String> <- Exchange.nextSocketExchange(String, exchange)
        loop(256n, next, Fixture.Capture{0, Nil{}, False{}})

def cases(count: Nat, +port: U32) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        +controller : A.AbortController<String> <- A.new(String)
        socket : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        result : Result<&2, &1, Exchange.StartError<String>, Exchange.Exchange<String>> <- Fixture.start(socket, A.signal(String, controller), 7)
        text : String <- started(result)
        A.dispose(String, controller)
        IO.print(text)
        cases(rest, port)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(7n, Probe.port(args))
