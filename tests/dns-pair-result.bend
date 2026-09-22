import Base
import ../packages/runtime/src/dns-resolver.bend as Pair
import ../packages/runtime/src/dns-resolver.bend as Classify
import ../packages/runtime/src/dns-resolver.bend as Lookup
import ../packages/runtime/src/dns-resolver.bend as Answer
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Response
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/url.bend as IPv4
import ../packages/runtime/src/url.bend as IPv6
import ../packages/runtime/src/dns-transport.bend as Transport
import ../packages/runtime/src/dns-transport.bend as UDP
import ../packages/runtime/src/dns-transport.bend as Policy
import ../packages/runtime/src/dns-transport.bend as Datagram
import ../packages/runtime/src/dns-transport.bend as Scope
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/dns-transport.bend as TCP
import ../packages/runtime/src/dns-transport.bend as Session
import ../packages/runtime/src/dns-transport.bend as Servers
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/socket.bend as SocketIO
import ../packages/runtime/src/socket.bend as Interrupt
import ../packages/runtime/src/dns-message.bend as Id
import ../packages/runtime/test/utf8-runner.bend as Scalar

def udp(failure: UDP.UdpServersFailure<String>, end: Scope.End<String>) -> Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>:
  Fail{Lookup.Transport{Transport.Datagram{UDP.UdpServersFailed{UDP.UdpServersReport{Endpoint.EndpointV4{IPv4.Address{2130706433}, 53}, failure, end}}}}}

def flags(reason: Policy.UdpPolicyRejection) -> U32:
  match reason:
    case Policy.ServerFailure{}: 33154
    case Policy.NotImplemented{}: 33156
    case Policy.Refused{}: 33157
    case Policy.UnhelpfulEmpty{}: 32768

def rejected(+reason: Policy.UdpPolicyRejection, end: Scope.End<String>) -> Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>:
  udp(UDP.UdpServersRejected{Message.Header{42, flags(reason), 1, 0, 0, 0}, reason}, end)

type InputMode is Data:
  AnswerIPv4{}
  AnswerIPv6{}
  EmptyAnswer{}
  UDPServerFailure{}
  UDPNotImplemented{}
  UDPRefused{}
  UDPUnhelpful{}
  UDPExpiredServerFailure{}
  UDPParentAbort{}
  UDPDefaultAbort{}
  UDPTimeout{}
  UDPRefusedSocket{}
  UDPOtherSocket{}
  TCPEOF{}
  TCPRefusedSocket{}
  TCPOtherSocket{}
  TCPCleanup{}
  ParentAbort{}
  EntropyFailure{}
  InvalidAnswer{}
  UnsupportedKind{}
  NoServersMode{}
  Coded{token: String}

def inputMode(+token: String) -> InputMode:
  Bool.pick(InputMode, String.eq(token, "a4"), AnswerIPv4{}, Bool.pick(InputMode, String.eq(token, "a6"), AnswerIPv6{}, Bool.pick(InputMode, String.eq(token, "empty"), EmptyAnswer{}, Bool.pick(InputMode, String.eq(token, "u2"), UDPServerFailure{}, Bool.pick(InputMode, String.eq(token, "u4"), UDPNotImplemented{}, Bool.pick(InputMode, String.eq(token, "u5"), UDPRefused{}, Bool.pick(InputMode, String.eq(token, "uempty"), UDPUnhelpful{}, Bool.pick(InputMode, String.eq(token, "uexpired2"), UDPExpiredServerFailure{}, Bool.pick(InputMode, String.eq(token, "uparent"), UDPParentAbort{}, Bool.pick(InputMode, String.eq(token, "udefault"), UDPDefaultAbort{}, Bool.pick(InputMode, String.eq(token, "utimeout"), UDPTimeout{}, Bool.pick(InputMode, String.eq(token, "uerrno111"), UDPRefusedSocket{}, Bool.pick(InputMode, String.eq(token, "uerrno110"), UDPOtherSocket{}, Bool.pick(InputMode, String.eq(token, "teof"), TCPEOF{}, Bool.pick(InputMode, String.eq(token, "terrno111"), TCPRefusedSocket{}, Bool.pick(InputMode, String.eq(token, "terrno110"), TCPOtherSocket{}, Bool.pick(InputMode, String.eq(token, "tcleanup"), TCPCleanup{}, Bool.pick(InputMode, String.eq(token, "abort"), ParentAbort{}, Bool.pick(InputMode, String.eq(token, "entropy"), EntropyFailure{}, Bool.pick(InputMode, String.eq(token, "invalid"), InvalidAnswer{}, Bool.pick(InputMode, String.eq(token, "unsupported"), UnsupportedKind{}, Bool.pick(InputMode, String.eq(token, "noservers"), NoServersMode{}, Coded{token}))))))))))))))))))))))

def coded(token: String) -> Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>:
  match token:
    case SCon{'c', code}: Fail{Lookup.AddressLookupSelection{Answer.ResponseCode{Scalar.decimal(code, 0)}}}
    case _: Fail{Lookup.InvalidReadSize{}}

def selectedInput(mode: InputMode) -> Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>:
  match mode:
    case AnswerIPv4{}: Done{Answer.Selection{Name.Name{(97 <> Nil{}) <> Nil{}}, Answer.V4{IPv4.Address{16909060}, 61} <> Nil{}}}
    case AnswerIPv6{}: Done{Answer.Selection{Name.Name{(98 <> Nil{}) <> Nil{}}, Answer.V6{IPv6.Ipv6Address{0, 0, 0, 1}, 73} <> Nil{}}}
    case EmptyAnswer{}: Done{Answer.Selection{Name.Name{Nil{}}, Nil{}}}
    case UDPServerFailure{}: rejected(Policy.ServerFailure{}, Scope.Active{})
    case UDPNotImplemented{}: rejected(Policy.NotImplemented{}, Scope.Active{})
    case UDPRefused{}: rejected(Policy.Refused{}, Scope.Active{})
    case UDPUnhelpful{}: rejected(Policy.UnhelpfulEmpty{}, Scope.Active{})
    case UDPExpiredServerFailure{}: rejected(Policy.ServerFailure{}, Scope.AttemptExpired{})
    case UDPParentAbort{}: rejected(Policy.ServerFailure{}, Scope.ParentAborted{Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{"parent marker"}}}})
    case UDPDefaultAbort{}: rejected(Policy.Refused{}, Scope.UnexpectedDefaultAbort{})
    case UDPTimeout{}: udp(UDP.Exchange{Datagram.Aborted{Abort.Supplied{Deadline.Expired{}}}}, Scope.AttemptExpired{})
    case UDPRefusedSocket{}: udp(UDP.Exchange{Datagram.UdpQueryTransport{SocketIO.DatagramSocketError{111, "udp refused marker"}}}, Scope.Active{})
    case UDPOtherSocket{}: udp(UDP.Exchange{Datagram.UdpQueryTransport{SocketIO.DatagramSocketError{110, "udp timeout marker"}}}, Scope.Active{})
    case TCPEOF{}: Fail{Lookup.Transport{Transport.Stream{Servers.Failed{TCP.Completed{Fail{TCP.Terminated{Session.EndOfStream{}}}, Done{Unit{}}}}}}}
    case TCPRefusedSocket{}: Fail{Lookup.Exchange{TCP.TcpQueryConnection{Connect.SocketError{111, "tcp refused marker"}}}}
    case TCPOtherSocket{}: Fail{Lookup.Exchange{TCP.TcpQueryConnection{Connect.SocketError{110, "tcp timeout marker"}}}}
    case TCPCleanup{}: Fail{Lookup.Transport{Transport.Stream{Servers.Failed{TCP.Completed{Fail{TCP.Terminated{Session.EndOfStream{}}}, Fail{Interrupt.InterruptError{9, "cleanup marker"}}}}}}}
    case ParentAbort{}: Fail{Lookup.Aborted{Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{"abort marker"}}}}}
    case EntropyFailure{}: Fail{Lookup.Identifier{Id.SourceFailure{87, "entropy marker"}}}
    case InvalidAnswer{}: Fail{Lookup.AddressLookupSelection{Answer.AliasLoop{}}}
    case UnsupportedKind{}: Fail{Lookup.AddressLookupUnsupportedType{}}
    case NoServersMode{}: Fail{Lookup.NoServers{}}
    case Coded{token}: coded(token)

def input(token: String) -> Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>:
  selectedInput(inputMode(token))

def cause(value: Response.Cause) -> String:
  match value:
    case Response.EmptyAnswer{}: "empty"
    case Response.Missing{}: "missing"
    case Response.ServerFailure{}: "server"
    case Response.TemporaryFailure{}: "temporary"
    case Response.Unrecoverable{}: "unrecoverable"
    case Response.ConnectionRefused{}: "refused"

def disposition(value: Pair.Disposition) -> String:
  match value:
    case Pair.Answer{}: "answer"
    case Pair.Terminal{}: "terminal"
    case Pair.Reply{code}: "reply:" ++ U32.show(code)
    case Pair.Unavailable{why}: "unavailable:" ++ cause(why)

def reports(value: Pair.PairResultReports<Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>>) -> String:
  match value:
    case Pair.PairResultReports{Pair.Classified{_, a}, Pair.Classified{_, b}}: disposition(a) ++ "/" ++ disposition(b)

def outcome(value: Run.Outcome<Pair.PairResultReports<Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>>, Pair.PairResultReports<Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>>>) -> String:
  match value:
    case Run.Answer{values}: "answer:" ++ reports(values)
    case Run.SearchHalt{values}: "halt:" ++ reports(values)
    case Run.SearchRunFailed{why}: "failed:" ++ cause(why)

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> left <> right <> rest:
      do IO<Unit>:
        +a : Pair.Classified<Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>> <- Classify.classify(~String, input(left))
        +b : Pair.Classified<Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>> <- Classify.classify(~String, input(right))
        IO.print(reports(Pair.PairResultReports{a, b}) ++ "=" ++ outcome(Pair.merge(Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>, Bool.pick(Pair.Priority, String.eq(first, "4"), Pair.IPv4First{}, Pair.IPv6First{}), a, b)))
        args(rest)
    case _: IO.die(Unit, 1, "expected report pairs")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
