import Base
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/tls-socket.bend as TLS
import ../packages/runtime/src/tls13-client.bend as Client
import ../packages/runtime/src/tls13-handshake.bend as Handshake
import ../packages/runtime/src/x509.bend as X509
import ../packages/runtime/src/socket.bend as Socket
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline

# Retryability is identical at TLS connection setup and pre-header reads.
def category(value: Fetch.Category) -> String:
  match value:
    case Fetch.Connection{}: "connection"
    case Fetch.Timeout{}: "timeout"
    case Fetch.NonRetryable{}: "terminal"

def expect(label: String, expected: String, actual: Fetch.Category) -> IO(Unit):
  Bool.pick(IO(Unit),String.eq(expected,category(actual)),IO.pure(Unit,Unit{}),IO.die(Unit,1,label))

def check(+label: String, +expected: String, +error: TLS.Error<Deadline.Cause<Unit>>) -> IO(Unit):
  do IO<Unit>:
    expect(label ++ " source",expected,Fetch.source(Unit,HTTP.TLSSourceFailure{error}))
    expect(label ++ " setup",expected,Fetch.exchangeCategory(Unit,HTTP.ResolvedExchangeFailure{HTTP.TLSStartFailure{error}}))

def main() -> IO(Unit):
  do IO<Unit>:
    check("reset","connection",TLS.Network{Socket.SocketError{104,"connection reset"}})
    check("deadline","timeout",TLS.Network{Socket.Aborted{Abort.Supplied{Deadline.Expired{}}}})
    check("parent abort","terminal",TLS.Network{Socket.Aborted{Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{Unit{}}}}}})
    check("default abort","terminal",TLS.Network{Socket.Aborted{Abort.DefaultAbort{}}})
    check("protocol","terminal",TLS.Protocol{Client.UnexpectedMessage{}})
    check("certificate","terminal",TLS.Protocol{Client.HandshakeFailure{Handshake.CertificateFailure{X509.InvalidCertificate{}}}})
    check("configuration","terminal",TLS.InvalidOptions{})
    expect("combined cleanup","terminal",Fetch.source(Unit,HTTP.TLSWithCleanup{TLS.Network{Socket.SocketError{104,"reset"}},TLS.Closed{}}))
    IO.print("PASS 15 TLS setup/source retry classifications")
