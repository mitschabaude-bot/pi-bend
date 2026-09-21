import Base
import ./openai-responses-attempt.bend as Attempt
import ./openai-responses-cleartext-fetch.bend as Native
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/deadline.bend as Deadline
import ../../../runtime/src/http-connect.bend as Connect
import ../../../runtime/src/http-host-route.bend as Route
import ../../../runtime/src/hosts-resolve.bend as Hosts
import ../../../runtime/src/dns-pair-hosts-resolver.bend as Named
import ../../../runtime/src/dns-pair-search.bend as DNS
import ../../../runtime/src/dns-pair-setup.bend as Setup
import ../../../runtime/src/dns-search-run.bend as Search
import ../../../runtime/src/connection-progress.bend as Connection
import ../../../runtime/src/http-resolved-exchange.bend as HTTP
import ../../../runtime/src/http-socket-exchange.bend as Exchange
import ../../../runtime/src/http-socket-source.bend as Source
import ../../../runtime/src/http-response-reader.bend as Reader
import ../../../runtime/src/http-response-progress.bend as Progress
import ../../../runtime/src/abortable-socket.bend as Socket
import ../../../runtime/src/socket-upload.bend as Upload

# This is retry policy only. Attempt.fetchFailure retains the complete native
# error, including resolution/connection traces and compound cleanup failures.
def connection() -> Attempt.FetchCategory:
  Attempt.Connection{"Connection error."}

def requestAbort(-Reason: Data, reason: Abort.AbortReason<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match reason:
    case Abort.Supplied{Deadline.Expired{}}: Attempt.Timeout{}
    case _: Attempt.NonRetryable{}

# DNS owns a deadline nested inside the request deadline. Either expiration
# is a timeout; a parent's explicit/default cancellation remains terminal.
def dnsAbort(-Reason: Data, reason: Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>) -> Attempt.FetchCategory:
  match reason:
    case Abort.Supplied{Deadline.Expired{}}: Attempt.Timeout{}
    case Abort.Supplied{Deadline.ParentAbort{why}}: requestAbort(Reason, why)
    case Abort.DefaultAbort{}: Attempt.NonRetryable{}

def dnsDeadline(-Reason: Data, fallback: Attempt.FetchCategory, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>>) -> Attempt.FetchCategory:
  match reason:
    case None{}: fallback
    case Some{why}: dnsAbort(Reason, why)

def setup(-Reason: Data, error: Setup.Error<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match error:
    case Setup.Aborted{why}: dnsAbort(Reason, why)
    case _: Attempt.NonRetryable{}

# QueryFailed is the resolver's terminal outcome: ordinary network failures,
# negative replies and exhausted attempts instead produce Search.NoAnswer.
# A retained deadline still distinguishes an interrupted query from a local or
# protocol halt. Setup errors retain their own cause ahead of a late deadline.
def dnsReport(-Reason: Data, report: DNS.Report<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match report:
    case DNS.Report{Fail{Search.Halted{DNS.SetupFailed{cause}}}, _}: setup(Reason, cause)
    case DNS.Report{Fail{Search.Halted{DNS.QueryFailed{_}}}, why}: dnsDeadline(Reason, Attempt.NonRetryable{}, why)
    case DNS.Report{Fail{Search.NoAnswer{_}}, why}: dnsDeadline(Reason, connection(), why)
    case DNS.Report{Done{_}, why}: dnsDeadline(Reason, connection(), why)

def resolution(-Reason: Data, -SourceError: Data, report: Connect.Resolution(Deadline.Cause<Reason>, SourceError)) -> Attempt.FetchCategory:
  match report:
    case Fail{_}: Attempt.NonRetryable{}
    case Done{Route.Named{Hosts.FailedSource{_}}}: Attempt.NonRetryable{}
    case Done{Route.Named{Hosts.FromNetwork{Named.InvalidName{_}}}}: Attempt.NonRetryable{}
    case Done{Route.Named{Hosts.FromNetwork{Named.Completed{report}}}}: dnsReport(Reason, report)
    case Done{_}: Attempt.NonRetryable{}

def socket(-Reason: Data, error: Socket.Error<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match error:
    case Socket.Aborted{why}: requestAbort(Reason, why)
    case Socket.SocketError{_, _}: connection()

def upload(-Reason: Data, error: Upload.Error<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match error:
    case Upload.WriteFailure{cause, None{}}: socket(Reason, cause)
    case _: Attempt.NonRetryable{}

def source(-Reason: Data, error: Source.Error<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match error:
    case Source.SocketFailure{cause}: socket(Reason, cause)
    case Source.UploadFailure{cause}: upload(Reason, cause)
    case Source.CleanupFailure{_}: Attempt.NonRetryable{}
    case Source.UploadWithCleanup{_, _}: Attempt.NonRetryable{}
    case Source.Released{}: Attempt.NonRetryable{}
    case Source.InvalidReadSize{}: Attempt.NonRetryable{}

def readerPrimary(-Reason: Data, error: Reader.PrimaryError<Source.Error<Deadline.Cause<Reason>>>) -> Attempt.FetchCategory:
  match error:
    case Reader.SourceError{cause}: source(Reason, cause)
    case Reader.DecodeError{_}: connection()

def reader(-Reason: Data, error: Reader.ReadError<Source.Error<Deadline.Cause<Reason>>>) -> Attempt.FetchCategory:
  match error:
    case Reader.PrimaryFailure{cause}: readerPrimary(Reason, cause)
    case Reader.ReleaseFailure{cause}: source(Reason, cause)
    case Reader.FailureWithRelease{_, _}: Attempt.NonRetryable{}

def exchangeRead(-Reason: Data, error: Exchange.ReadError<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match error:
    case Exchange.ResponseFailure{cause}: reader(Reason, cause)
    case Exchange.DisposalFailure{cause}: source(Reason, cause)
    case Exchange.ResponseWithDisposal{_, _}: Attempt.NonRetryable{}

def headerPrimary(-Reason: Data, error: Progress.PrimaryError<Exchange.ReadError<Deadline.Cause<Reason>>>) -> Attempt.FetchCategory:
  match error:
    case Progress.TransportFailure{cause}: exchangeRead(Reason, cause)
    case Progress.MissingHead{}: connection()
    case Progress.MissingCompletion{}: connection()
    case Progress.UnexpectedEvent{_}: Attempt.NonRetryable{}

def header(-Reason: Data, error: Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>) -> Attempt.FetchCategory:
  match error:
    case Progress.PrimaryFailure{cause}: headerPrimary(Reason, cause)
    case Progress.CleanupFailure{cause}: exchangeRead(Reason, cause)
    case Progress.FailureWithCleanup{_, _}: Attempt.NonRetryable{}

def connectionFailure(-Reason: Data, error: Connection.Error<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match error:
    case Connection.Exhausted{}: connection()
    case Connection.Aborted{why}: requestAbort(Reason, why)
    case Connection.NoAddresses{}: Attempt.NonRetryable{}
    case Connection.UnexpectedDefaultAbort{}: Attempt.NonRetryable{}

def exchangeStart(-Reason: Data, error: Exchange.StartError<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match error:
    case Exchange.InvalidReadSize{}: Attempt.NonRetryable{}
    case Exchange.SocketFailure{cause}: socket(Reason, cause)
    case Exchange.WriteFailure{cause, None{}}: socket(Reason, cause)
    case Exchange.WriteFailure{_, Some{_}}: Attempt.NonRetryable{}
    case Exchange.SourceFailure{cause}: source(Reason, cause)

def exchange(-Reason: Data, error: HTTP.Error<Deadline.Cause<Reason>>) -> Attempt.FetchCategory:
  match error:
    case HTTP.ConnectionFailure{cause}: connectionFailure(Reason, cause)
    case HTTP.ExchangeFailure{cause}: exchangeStart(Reason, cause)

def classify(-Reason: Data, -SourceError: Data, error: Native.Error<Reason, SourceError>) -> Attempt.FetchCategory:
  match error:
    case Native.InvalidRequest{_}: Attempt.NonRetryable{}
    case Native.Rejected{_}: Attempt.NonRetryable{}
    case Native.Unresolved{report}: resolution(Reason, SourceError, report)
    case Native.ExchangeFailure{_, _, cause}: exchange(Reason, cause)
    case Native.HeaderFailure{_, _, cause}: header(Reason, cause)
