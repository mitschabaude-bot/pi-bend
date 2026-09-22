import Base
import ../packages/runtime/src/dns-transport.bend as Query
import ../packages/runtime/src/dns-message.bend as Request
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/dns-message.bend as Edns
import ../packages/runtime/src/dns-transport.bend as Attempt
import ../packages/runtime/src/resolver-config.bend as Timeout
import ../packages/runtime/src/abortable-datagram.bend as Datagram
import ../packages/runtime/src/datagram-peer.bend as Peer
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-udp-attempt-scope.bend as ScopeTest

def destination(family: U32, port: U32) -> Endpoint.Endpoint:
  match family:
    case 4: Endpoint.V4{IPv4.Address{2130706433}, port}
    case _: Endpoint.V6{IPv6.Address{0,0,0,1}, port, 0}

def request(+mode: String) -> Request.Request:
  Request.Request{Bool.pick(U32, String.eq(mode, "invalid"), 65536, 42), 256, Message.Question{Name.Name{Nil{}}, 1, 1}, Bool.pick(Maybe<&2, Edns.Query>, String.eq(mode, "edns"), Some{Edns.Query{1232, False{}, Nil{}}}, None{})}

def outcome(result: Result<&2, &2, Query.UdpQueryError<Deadline.Cause<Deadline.Cause<String>>>, Query.UdpQueryReply>) -> String:
  match result:
    case Done{Query.UdpQueryAnswer{Message.Message{+packet, Message.Header{_, flags, _, _, _, _}, _, _, _, _}}}: "answer:" ++ U32.show(flags) ++ ":" ++ U32.show(Message.size(packet)) ++ ":" ++ U32.show(Name.byte(packet, (Message.size(packet) - 1 : U32)))
    case Done{Query.UdpQueryTruncated{_}}: "truncated"
    case Fail{Query.UdpQueryEncoding{_}}: "invalid"
    case Fail{Query.Opening{Peer.Association{code, _}}}: "association:" ++ U32.show(code)
    case Fail{Query.Aborted{why}}: "abort:" ++ ScopeTest.show(Attempt.classify(String, Some{why}))
    case Fail{Query.UdpQueryTransport{Datagram.Aborted{why}}}: "abort:" ++ ScopeTest.show(Attempt.classify(String, Some{why}))
    case Fail{Query.UdpQueryTransport{Datagram.SocketError{code, _}}}: "socket:" ++ U32.show(code)
    case _: "unexpected"

def child(destination: Endpoint.Endpoint, request: Request.Request, pair: Deadline.Scope<Deadline.Cause<String>> & Abort.AbortSignal<Deadline.Cause<Deadline.Cause<String>>>) -> IO(Unit):
  match pair:
    case (scope, signal):
      do IO<Unit>:
        result : Result<&2, &2, Query.UdpQueryError<Deadline.Cause<Deadline.Cause<String>>>, Query.UdpQueryReply> <- Query.exchangeRequestUdpQuery(Deadline.Cause<Deadline.Cause<String>>, destination, signal, request)
        IO.print(outcome(result))
        ended : Attempt.End<String> <- Attempt.closeUdpAttemptScope(String, scope)
        IO.print(ScopeTest.show(ended))

def created(destination: Endpoint.Endpoint, request: Request.Request, result: Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<String>>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "unexpected budget rejection")
    case Done{scope}: child(destination, request, Deadline.borrow(Deadline.Cause<String>, scope))

def total(destination: Endpoint.Endpoint, request: Request.Request, pair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match pair:
    case (scope, signal):
      do IO<Unit>:
        attempt : Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<String>>> <- Attempt.createUdpAttemptScope(String, Timeout.Duration{0n}, signal)
        created(destination, request, attempt)
        ended : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        return Unit{}

def run(family: U32, port: U32, +mode: String) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<String> <- Abort.new(String)
    ScopeTest.before(mode, controller)
    task : Chan(Unit) <- IO.fork(Unit, ScopeTest.later(mode, controller))
    scope : Deadline.Scope<String> <- Deadline.create(String, Bool.pick(U32, String.eq(mode, "total"), 20, 5000), Abort.signal(String, controller))
    total(destination(family, Bool.pick(U32, String.eq(mode, "port"), 0, port)), request(mode), Deadline.borrow(String, scope))
    IO.join(Unit, task)
    Abort.dispose(String, controller)

def args(values: List<String>) -> IO(Unit):
  match values:
    case family <> port <> mode <> Nil{}: run(Scalar.decimal(family, 0), Scalar.decimal(port, 0), mode)
    case _: IO.die(Unit, 1, "expected family port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
