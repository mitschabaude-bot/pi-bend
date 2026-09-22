import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./callback.bend as C
import ./url-record.bend as URL
import ./headers.bend as Headers
import ./http-buffered-request.bend as Request
import ./http-buffered-body.bend as Body
import ./http-resolved-exchange.bend as HTTP
import ./http-exchange-plan.bend as Plan
import ./http-exchange-response.bend as Head
import ./http-socket-exchange.bend as Exchange
import ./http-socket-source.bend as Source
import ./http-response.bend as Response
import ./http-response-progress.bend as Progress
import ./http-response-reader.bend as Reader
import ./http-connect.bend as Connect
import ./http-host-route.bend as Route
import ./hosts-resolve.bend as HostsResolve
import ./connection-driver.bend as Driver
import ./connection-progress.bend as Connection
import ./abortable-socket.bend as Socket
import ./socket-upload.bend as Upload
import ./dns-resolver.bend as Resolver
import ./dns-pair-hosts-resolver.bend as Named
import ./dns-pair-search.bend as DNS
import ./dns-pair-setup.bend as Setup
import ./dns-search-run.bend as Search
import ./resolver-system-config.bend as System
import ./resolver-diagnostic.bend as Diagnostic
import ./hosts-load.bend as HostsFile
import ./hosts.bend as Hosts
import ./hosts-file.bend as File
import ./utf8-strict.bend as UTF8
import ./random-index.bend as Index

# Native replacement for the host platform's `fetch`: a cleartext HTTP/1.1
# request over the pure DNS resolver and socket exchange. A request acquires
# the response through its final headers and leaves the body unread; the body
# owns its transport until the caller closes it. HTTPS is rejected by the plan.

def Signal(-Reason: Data) -> Data: Abort.AbortSignal<Deadline.Cause<Reason>>
def Transport(-Reason: Data) -> Type: Exchange.Exchange<Deadline.Cause<Reason>>
def SourceError() -> Data: HostsFile.Error<UTF8.Error>
def HostsResult() -> Data: Result<&2, &2, SourceError(), List<&2, Hosts.Entry<File.Address>>>

type Input<-Reason: Data> is Data:
  Input{url: URL.URL, method: String, headers: Headers.Headers, body: String, signal: Signal(Reason)}

type Error<-Reason: Data> is Data:
  InvalidRequest{cause: Request.URLRequestError}
  Rejected{cause: Plan.Error}
  Unresolved{resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError())}
  ExchangeFailure{resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError()), attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>, cause: HTTP.Error<Deadline.Cause<Reason>>}
  HeaderFailure{resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError()), attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>, cause: Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>}

def Result_(-Reason: Data) -> Type: Result<&2, &1, Error<Reason>, Response.Response<Transport(Reason)>>
def Fetch(-Reason: Data) -> Data: C.Callback<Input<Reason>, Result_(Reason)>

# System configuration
# --------------------

# Paths and bounds are explicit so embedders and tests can replace them.
type Files is Data:
  Files{resolver: String, hosts: String, chunkSize: U32, byteLimit: Nat, dnsMilliseconds: U32, dnsMaximum: U32}

def linuxFiles() -> Files:
  Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}

type InitError is Data:
  ConfigurationFailure{cause: System.Error<UTF8.Error>}
  EntropyFailure{cause: Index.Error}

# A hosts-file failure only affects named resolution; numeric addresses never
# consult that source, so it is retained as a per-lookup error, not an init error.
type Runtime is Type:
  Runtime{resolver: Resolver.Owner, hosts: HostsResult(), options: HTTP.Options}

def created(hosts: HostsResult(), options: HTTP.Options, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> Result<&2, &1, InitError, Runtime>:
  match result:
    case Fail{cause}: Fail{EntropyFailure{cause}}
    case Done{resolver}: Done{Runtime{resolver, hosts, options}}

def configured(files: Files, options: HTTP.Options, result: Result<&2, &2, System.Error<UTF8.Error>, System.Prepared>) -> IO(Result<&2, &1, InitError, Runtime>):
  match files result:
    case _ Fail{cause}: IO.pure(Result<&2, &1, InitError, Runtime>, Fail{ConfigurationFailure{cause}})
    case Files{_, path, chunkSize, byteLimit, _, _} Done{System.Prepared{_, _, config}}:
      do IO<Result<&2, &1, InitError, Runtime>>:
        hosts : HostsResult() <- HostsFile.read(path, chunkSize, byteLimit)
        resolver : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.create(config)
        return created(hosts, options, resolver)

def create(+files: Files, options: HTTP.Options) -> IO(Result<&2, &1, InitError, Runtime>):
  match files:
    case Files{path, _, chunkSize, byteLimit, milliseconds, maximum}:
      do IO<Result<&2, &1, InitError, Runtime>>:
        settings : Result<&2, &2, System.Error<UTF8.Error>, System.Prepared> <- System.loadWith(~UTF8.Error, ~UTF8.decode, path, chunkSize, byteLimit, milliseconds, maximum)
        configured(files, options, settings)

def dispose(runtime: Runtime) -> IO(Unit):
  match runtime:
    case Runtime{resolver, _, _}: Resolver.close(resolver)

# Requests
# --------

type Context is Data:
  Context{resolver: Resolver.Resolver, hosts: HostsResult(), options: HTTP.Options}

def headed(-Reason: Data, resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError()), attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>, result: Result<&2, &1, Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>, Response.Response<Transport(Reason)>>) -> Result_(Reason):
  match result:
    case Fail{cause}: Fail{HeaderFailure{resolution, attempts, cause}}
    case Done{response}: Done{response}

def reported(~Reason: Data, report: HTTP.Report<Deadline.Cause<Reason>, SourceError()>) -> IO(Result_(Reason)):
  match report:
    case HTTP.Rejected{cause}: IO.pure(Result_(Reason), Fail{Rejected{cause}})
    case HTTP.Unresolved{resolution}: IO.pure(Result_(Reason), Fail{Unresolved{resolution}})
    case HTTP.Attempted{resolution, attempts, Fail{cause}}: IO.pure(Result_(Reason), Fail{ExchangeFailure{resolution, attempts, cause}})
    case HTTP.Attempted{resolution, attempts, Done{exchange}}:
      do IO<Result_(Reason)>:
        result : Result<&2, &1, Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>, Response.Response<Transport(Reason)>> <- Head.start(~Deadline.Cause<Reason>, exchange)
        return headed(Reason, resolution, attempts, result)

def prepared(~Reason: Data, context: Context, signal: Signal(Reason), request: Result<&2, &2, Request.URLRequestError, Request.URLPrepared>) -> IO(Result_(Reason)):
  match context request:
    case _ Fail{cause}: IO.pure(Result_(Reason), Fail{InvalidRequest{cause}})
    case Context{resolver, hosts, options} Done{request}:
      do IO<Result_(Reason)>:
        report : HTTP.Report<Deadline.Cause<Reason>, SourceError()> <- HTTP.start(~Deadline.Cause<Reason>, ~(SourceError()), resolver, signal, hosts, options, request)
        reported(~Reason, report)

def invoke(~Reason: Data, context: Context, input: Input<Reason>) -> IO(Result_(Reason)):
  match input:
    case Input{url, method, headers, body, signal}: prepared(~Reason, context, signal, Request.prepareURL(url, method, headers, Body.Text{body}))

def borrowed(~Reason: Data, +hosts: HostsResult(), +options: HTTP.Options, pair: Resolver.Owner & Resolver.Resolver) -> IO(Runtime & Fetch(Reason)):
  match pair:
    case Tuple{owner, resolver}:
      do IO<Runtime & Fetch(Reason)>:
        fetch : Fetch(Reason) <- C.create(~Context, ~Input<Reason>, ~(Result_(Reason)), ~(invoke(~Reason)), Context{resolver, hosts, options})
        return (Runtime{owner, hosts, options}, fetch)

# The callback borrows the runtime's resolver: retire it before the runtime.
def callback(~Reason: Data, runtime: Runtime) -> IO(Runtime & Fetch(Reason)):
  match runtime:
    case Runtime{resolver, hosts, options}: borrowed(~Reason, hosts, options, Resolver.borrow(resolver))

def retire(-Reason: Data, fetch: Fetch(Reason)) -> IO(Unit):
  C.dispose(Input<Reason>, Result_(Reason), fetch)

# Retry classification
# --------------------

# Only the policy question "is this a connection failure, a timeout or a
# terminal error?" is answered here. Callers keep the complete typed error.
type Category is Data:
  NonRetryable{}
  Connection{}
  Timeout{}

def requestAbort(-Reason: Data, reason: Abort.AbortReason<Deadline.Cause<Reason>>) -> Category:
  match reason:
    case Abort.Supplied{Deadline.Expired{}}: Timeout{}
    case _: NonRetryable{}

# DNS owns a deadline nested inside the request deadline. Either expiration is
# a timeout; a parent's explicit or default cancellation remains terminal.
def dnsAbort(-Reason: Data, reason: Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>) -> Category:
  match reason:
    case Abort.Supplied{Deadline.Expired{}}: Timeout{}
    case Abort.Supplied{Deadline.ParentAbort{why}}: requestAbort(Reason, why)
    case Abort.DefaultAbort{}: NonRetryable{}

def dnsDeadline(-Reason: Data, fallback: Category, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>>) -> Category:
  match reason:
    case None{}: fallback
    case Some{why}: dnsAbort(Reason, why)

def setup(-Reason: Data, error: Setup.Error<Deadline.Cause<Reason>>) -> Category:
  match error:
    case Setup.Aborted{why}: dnsAbort(Reason, why)
    case _: NonRetryable{}

# QueryFailed is the resolver's terminal outcome; ordinary network failures,
# negative replies and exhausted attempts produce NoAnswer instead.
def dnsReport(-Reason: Data, report: DNS.Report<Deadline.Cause<Reason>>) -> Category:
  match report:
    case DNS.Report{Fail{Search.Halted{DNS.SetupFailed{cause}}}, _}: setup(Reason, cause)
    case DNS.Report{Fail{Search.Halted{DNS.QueryFailed{_}}}, why}: dnsDeadline(Reason, NonRetryable{}, why)
    case DNS.Report{Fail{Search.NoAnswer{_}}, why}: dnsDeadline(Reason, Connection{}, why)
    case DNS.Report{Done{_}, why}: dnsDeadline(Reason, Connection{}, why)

def resolutionCategory(-Reason: Data, report: Connect.Resolution(Deadline.Cause<Reason>, SourceError())) -> Category:
  match report:
    case Done{Route.Named{HostsResolve.FromNetwork{Named.Completed{report}}}}: dnsReport(Reason, report)
    case _: NonRetryable{}

def socket(-Reason: Data, error: Socket.Error<Deadline.Cause<Reason>>) -> Category:
  match error:
    case Socket.Aborted{why}: requestAbort(Reason, why)
    case Socket.SocketError{_, _}: Connection{}

def source(-Reason: Data, error: Source.Error<Deadline.Cause<Reason>>) -> Category:
  match error:
    case Source.SocketFailure{cause}: socket(Reason, cause)
    case Source.UploadFailure{Upload.WriteFailure{cause, None{}}}: socket(Reason, cause)
    case _: NonRetryable{}

def reader(-Reason: Data, error: Reader.ReadError<Source.Error<Deadline.Cause<Reason>>>) -> Category:
  match error:
    case Reader.PrimaryFailure{Reader.SourceError{cause}}: source(Reason, cause)
    case Reader.PrimaryFailure{Reader.DecodeError{_}}: Connection{}
    case Reader.ReleaseFailure{cause}: source(Reason, cause)
    case Reader.FailureWithRelease{_, _}: NonRetryable{}

def exchangeRead(-Reason: Data, error: Exchange.ReadError<Deadline.Cause<Reason>>) -> Category:
  match error:
    case Exchange.ResponseFailure{cause}: reader(Reason, cause)
    case Exchange.DisposalFailure{cause}: source(Reason, cause)
    case Exchange.ResponseWithDisposal{_, _}: NonRetryable{}

def header(-Reason: Data, error: Progress.Error<Exchange.ReadError<Deadline.Cause<Reason>>>) -> Category:
  match error:
    case Progress.PrimaryFailure{Progress.TransportFailure{cause}}: exchangeRead(Reason, cause)
    case Progress.PrimaryFailure{Progress.MissingHead{}}: Connection{}
    case Progress.PrimaryFailure{Progress.MissingCompletion{}}: Connection{}
    case Progress.PrimaryFailure{Progress.UnexpectedEvent{_}}: NonRetryable{}
    case Progress.CleanupFailure{cause}: exchangeRead(Reason, cause)
    case Progress.FailureWithCleanup{_, _}: NonRetryable{}

def exchangeCategory(-Reason: Data, error: HTTP.Error<Deadline.Cause<Reason>>) -> Category:
  match error:
    case HTTP.ConnectionFailure{Connection.Exhausted{}}: Connection{}
    case HTTP.ConnectionFailure{Connection.Aborted{why}}: requestAbort(Reason, why)
    case HTTP.ConnectionFailure{_}: NonRetryable{}
    case HTTP.ExchangeFailure{Exchange.SocketFailure{cause}}: socket(Reason, cause)
    case HTTP.ExchangeFailure{Exchange.WriteFailure{cause, None{}}}: socket(Reason, cause)
    case HTTP.ExchangeFailure{Exchange.SourceFailure{cause}}: source(Reason, cause)
    case HTTP.ExchangeFailure{_}: NonRetryable{}

def classify(-Reason: Data, error: Error<Reason>) -> Category:
  match error:
    case InvalidRequest{_}: NonRetryable{}
    case Rejected{_}: NonRetryable{}
    case Unresolved{report}: resolutionCategory(Reason, report)
    case ExchangeFailure{_, _, cause}: exchangeCategory(Reason, cause)
    case HeaderFailure{_, _, cause}: header(Reason, cause)

# Initialization diagnostics
# --------------------------

def entropy(error: Index.Error) -> String:
  match error:
    case Index.InvalidBound{}: "Invalid resolver random-index bound"
    case Index.InvalidBytes{}: "Resolver entropy source returned invalid bytes"
    case Index.SourceFailure{code, message}: Diagnostic.operatingSystem("Could not obtain resolver entropy", code, message)

def messages(error: InitError) -> List<&2, String>:
  match error:
    case ConfigurationFailure{cause}: Diagnostic.messages(cause)
    case EntropyFailure{cause}: entropy(cause) <> Nil{}

def joined(messages: List<&2, String>) -> String:
  match messages:
    case Nil{}: ""
    case first <> rest: "; " ++ first ++ joined(rest)

def display(messages: List<&2, String>) -> String:
  match messages:
    case Nil{}: "Invalid resolver configuration"
    case first <> rest: first ++ joined(rest)

def format(error: InitError) -> String: display(messages(error))
