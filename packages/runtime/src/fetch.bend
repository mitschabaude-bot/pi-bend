import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./callback.bend as C
import ./url.bend as URL
import ./http-message.bend as Headers
import ./http-message.bend as Request
import ./http-message.bend as Body
import ./http-exchange.bend as HTTP
import ./http-message.bend as Plan
import ./http-exchange.bend as Head
import ./http-exchange.bend as Exchange
import ./http-exchange.bend as Source
import ./http-response.bend as Response
import ./http-response.bend as Progress
import ./http-response.bend as Reader
import ./http-exchange.bend as Connect
import ./http-exchange.bend as Route
import ./hosts.bend as HostsResolve
import ./connection-driver.bend as Driver
import ./connection-driver.bend as Connection
import ./tls-socket.bend as TLS
import ./socket.bend as Socket
import ./socket.bend as Upload
import ./dns-resolver.bend as Resolver
import ./dns-resolver.bend as Named
import ./dns-resolver.bend as DNS
import ./dns-resolver.bend as Setup
import ./dns-message.bend as Search
import ./dns-resolver.bend as System
import ./dns-resolver.bend as Diagnostic
import ./hosts.bend as HostsFile
import ./hosts.bend as Hosts
import ./hosts.bend as File
import ./utf8.bend as UTF8
import ./random.bend as Index
import ./http-proxy.bend as Proxy

# Native HTTP/1.1 fetch over the pure DNS resolver and plain/TLS socket exchange.
# A request acquires final response headers and leaves the body unread; the
# body owns its transport until closed. HTTPS requires an explicit authorizer.

def Signal(-Reason: Data) -> Data: Abort.AbortSignal<Deadline.Cause<Reason>>
def Transport(-Reason: Data) -> Type: Exchange.Exchange<Deadline.Cause<Reason>>
def SourceError() -> Data: HostsFile.LoadError<UTF8.Error>
def HostsResult() -> Data: Result<&2, &2, SourceError(), List<&2, Hosts.Entry<File.Address>>>

type Input<-Reason: Data> is Data:
  Input{url: URL.URL, method: String, headers: Headers.Headers, body: Body.Input, signal: Signal(Reason)}

type Error<-Reason: Data> is Data:
  InvalidRequest{cause: Request.URLRequestError}
  Rejected{cause: Plan.ExchangePlanError}
  Unresolved{resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError())}
  ExchangeFailure{resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError()), attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>, cause: HTTP.ResolvedExchangeError<Deadline.Cause<Reason>>}
  HeaderFailure{resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError()), attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>, cause: Progress.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>}
  ReusedExchangeFailure{cause: HTTP.ResolvedExchangeError<Deadline.Cause<Reason>>}
  ReusedHeaderFailure{cause: Progress.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>}

# Actionable operating-system failures retained by a request. A fetch may try
# several addresses, so callers that present diagnostics receive the complete
# ordered list rather than an opaque top-level "fetch failed".
type NetworkFailure is Data:
  NetworkFailure{code: Maybe<&2, U32>, message: String}

def socketFailures(-Reason: Data, error: Socket.Error<Reason>) -> List<&2, NetworkFailure>:
  match error:
    case Socket.SocketError{code, message}: [NetworkFailure{Some{code}, message}]
    case Socket.Aborted{_}: Nil{}

def interruptFailures(error: Socket.InterruptError) -> List<&2, NetworkFailure>:
  match error:
    case Socket.InterruptError{code, message}: [NetworkFailure{Some{code}, message}]

def optionalInterruptFailures(error: Maybe<&2, Socket.InterruptError>) -> List<&2, NetworkFailure>:
  match error:
    case None{}: Nil{}
    case Some{value}: interruptFailures(value)

def uploadFailures(-Reason: Data, error: Upload.UploadError<Reason>) -> List<&2, NetworkFailure>:
  match error:
    case Upload.WriteFailure{cause, cleanup}: List.append(&2, NetworkFailure, socketFailures(Reason, cause), optionalInterruptFailures(cleanup))
    case Upload.InterruptFailure{cause}: interruptFailures(cause)

def tlsFailures(-Reason: Data, error: TLS.Error<Reason>) -> List<&2, NetworkFailure>:
  match error:
    case TLS.Network{cause}: socketFailures(Reason, cause)
    case TLS.ShutdownFailure{cause}: interruptFailures(cause)
    case _: Nil{}

def sourceFailures(-Reason: Data, error: Source.SocketSourceError<Reason>) -> List<&2, NetworkFailure>:
  match error:
    case Source.SocketSourceSocketFailure{cause}: socketFailures(Reason, cause)
    case Source.CleanupFailure{cause}: interruptFailures(cause)
    case Source.UploadFailure{cause}: uploadFailures(Reason, cause)
    case Source.UploadWithCleanup{cause, cleanup}: List.append(&2, NetworkFailure, uploadFailures(Reason, cause), interruptFailures(cleanup))
    case Source.TLSSourceFailure{cause}: tlsFailures(Reason, cause)
    case Source.TLSWithCleanup{cause, cleanup}: List.append(&2, NetworkFailure, tlsFailures(Reason, cause), tlsFailures(Reason, cleanup))
    case _: Nil{}

def readerPrimaryFailures(-Reason: Data, error: Reader.ResponseReaderPrimaryError<Source.SocketSourceError<Reason>>) -> List<&2, NetworkFailure>:
  match error:
    case Reader.SourceError{cause}: sourceFailures(Reason, cause)
    case Reader.DecodeError{_}: Nil{}

def readerFailures(-Reason: Data, error: Reader.ReadError<Source.SocketSourceError<Reason>>) -> List<&2, NetworkFailure>:
  match error:
    case Reader.ResponseReaderPrimaryFailure{cause}: readerPrimaryFailures(Reason, cause)
    case Reader.ReleaseFailure{cause}: sourceFailures(Reason, cause)
    case Reader.FailureWithRelease{primary, release}: List.append(&2, NetworkFailure, readerPrimaryFailures(Reason, primary), sourceFailures(Reason, release))

def exchangeReadFailures(-Reason: Data, error: Exchange.ReadError<Reason>) -> List<&2, NetworkFailure>:
  match error:
    case Exchange.ResponseFailure{cause}: readerFailures(Reason, cause)
    case Exchange.DisposalFailure{cause}: sourceFailures(Reason, cause)
    case Exchange.ResponseWithDisposal{cause, disposal}: List.append(&2, NetworkFailure, readerFailures(Reason, cause), sourceFailures(Reason, disposal))

def progressPrimaryFailures(-Reason: Data, error: Progress.ResponseProgressPrimaryError<Exchange.ReadError<Reason>>) -> List<&2, NetworkFailure>:
  match error:
    case Progress.TransportFailure{cause}: exchangeReadFailures(Reason, cause)
    case _: Nil{}

def progressFailures(-Reason: Data, error: Progress.ResponseProgressError<Exchange.ReadError<Reason>>) -> List<&2, NetworkFailure>:
  match error:
    case Progress.ResponseProgressPrimaryFailure{cause}: progressPrimaryFailures(Reason, cause)
    case Progress.ResponseProgressCleanupFailure{cause}: exchangeReadFailures(Reason, cause)
    case Progress.ResponseProgressFailureWithCleanup{primary, cleanup}: List.append(&2, NetworkFailure, progressPrimaryFailures(Reason, primary), exchangeReadFailures(Reason, cleanup))

def tunnelFailures(-Reason: Data, error: Proxy.TunnelError<Reason>) -> List<&2, NetworkFailure>:
  match error:
    case Proxy.TunnelSocket{cause}: socketFailures(Reason, cause)
    case _: Nil{}

def startFailures(-Reason: Data, error: Exchange.StartError<Reason>) -> List<&2, NetworkFailure>:
  match error:
    case Exchange.TLSStartFailure{cause}: tlsFailures(Reason, cause)
    case Exchange.SocketFailure{cause}: socketFailures(Reason, cause)
    case Exchange.WriteFailure{cause, cleanup}: List.append(&2, NetworkFailure, socketFailures(Reason, cause), optionalInterruptFailures(cleanup))
    case Exchange.SourceFailure{cause}: sourceFailures(Reason, cause)
    case Exchange.TunnelFailure{cause}: tunnelFailures(Reason, cause)
    case _: Nil{}

def resolvedFailures(-Reason: Data, error: HTTP.ResolvedExchangeError<Reason>) -> List<&2, NetworkFailure>:
  match error:
    case HTTP.ResolvedExchangeConnectionFailure{_}: Nil{}
    case HTTP.ResolvedExchangeFailure{cause}: startFailures(Reason, cause)

def attemptFailures(-Reason: Data, attempts: List<&2, Driver.Entry<Reason>>) -> List<&2, NetworkFailure>:
  match attempts:
    case Nil{}: Nil{}
    case Driver.Entry{_, _, Fail{Driver.SocketFailure{code, message}}, _} <> rest: NetworkFailure{Some{code}, message} <> attemptFailures(Reason, rest)
    case Driver.Entry{_, _, Fail{Driver.TimedOut{}}, _} <> rest: NetworkFailure{None{}, "connect timed out"} <> attemptFailures(Reason, rest)
    case _ <> rest: attemptFailures(Reason, rest)

def networkFailures(-Reason: Data, error: Error<Reason>) -> List<&2, NetworkFailure>:
  match error:
    case ExchangeFailure{_, attempts, cause}: List.append(&2, NetworkFailure, attemptFailures(Deadline.Cause<Reason>, attempts), resolvedFailures(Deadline.Cause<Reason>, cause))
    case HeaderFailure{_, attempts, cause}: List.append(&2, NetworkFailure, attemptFailures(Deadline.Cause<Reason>, attempts), progressFailures(Deadline.Cause<Reason>, cause))
    case ReusedExchangeFailure{cause}: resolvedFailures(Deadline.Cause<Reason>, cause)
    case ReusedHeaderFailure{cause}: progressFailures(Deadline.Cause<Reason>, cause)
    case _: Nil{}

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
  ConfigurationFailure{cause: System.SystemConfigError<UTF8.Error>}
  EntropyFailure{cause: Index.Error}

# A hosts-file failure only affects named resolution; numeric addresses never
# consult that source, so it is retained as a per-lookup error, not an init error.
# Each fetch callback's keep-alive pool is closed with the runtime.
# Requests go through the runtime's HTTP proxies (http-proxy.bend); a runtime
# from `create` has none.
type Runtime is Type:
  Runtime{resolver: Resolver.Owner, hosts: HostsResult(), options: HTTP.Options, proxies: Proxy.Config, pools: List<&2, C.Callback<Unit, Unit>>}

def created(hosts: HostsResult(), options: HTTP.Options, proxies: Proxy.Config, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> Result<&2, &1, InitError, Runtime>:
  match result:
    case Fail{cause}: Fail{EntropyFailure{cause}}
    case Done{resolver}: Done{Runtime{resolver, hosts, options, proxies, Nil{}}}

def configured(files: Files, options: HTTP.Options, proxies: Proxy.Config, result: Result<&2, &2, System.SystemConfigError<UTF8.Error>, System.SystemConfigPrepared>) -> IO(Result<&2, &1, InitError, Runtime>):
  match files result:
    case _ Fail{cause}: IO.pure(Result<&2, &1, InitError, Runtime>, Fail{ConfigurationFailure{cause}})
    case Files{_, path, chunkSize, byteLimit, _, _} Done{System.SystemConfigPrepared{_, _, config}}:
      do IO<Result<&2, &1, InitError, Runtime>>:
        hosts : HostsResult() <- HostsFile.read(path, chunkSize, byteLimit)
        resolver : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.create(config)
        return created(hosts, options, proxies, resolver)

# A runtime whose requests use the given proxies (undici's EnvHttpProxyAgent,
# as the coding agent installs it).
def createWithProxy(+files: Files, options: HTTP.Options, proxies: Proxy.Config) -> IO(Result<&2, &1, InitError, Runtime>):
  match files:
    case Files{path, _, chunkSize, byteLimit, milliseconds, maximum}:
      do IO<Result<&2, &1, InitError, Runtime>>:
        settings : Result<&2, &2, System.SystemConfigError<UTF8.Error>, System.SystemConfigPrepared> <- System.loadWith(~UTF8.Error, ~UTF8.decodeStrict, path, chunkSize, byteLimit, milliseconds, maximum)
        configured(files, options, proxies, settings)

def create(+files: Files, options: HTTP.Options) -> IO(Result<&2, &1, InitError, Runtime>): createWithProxy(files, options, Proxy.none())

def closePools(pools: List<&2, C.Callback<Unit, Unit>>) -> IO(Unit):
  match pools:
    case Nil{}: IO.pure(Unit, Unit{})
    case +closer <> rest:
      do IO<Unit>:
        C.call(Unit, Unit, closer, Unit{})
        C.dispose(Unit, Unit, closer)
        closePools(rest)

# Retire every fetch callback first: their idle keep-alive connections close
# here, before the resolver.
def dispose(runtime: Runtime) -> IO(Unit):
  match runtime:
    case Runtime{resolver, _, _, _, pools}:
      do IO<Unit>:
        closePools(pools)
        Resolver.close(resolver)

# Requests
# --------

type Context<-Reason: Data> is Data:
  Context{resolver: Resolver.Resolver, hosts: HostsResult(), options: HTTP.Options, proxies: Proxy.Config, security: HTTP.Security, pool: HTTP.Pool<Deadline.Cause<Reason>>}

def headed(-Reason: Data, resolution: Connect.Resolution(Deadline.Cause<Reason>, SourceError()), attempts: List<&2, Driver.Entry<Deadline.Cause<Reason>>>, result: Result<&2, &1, Progress.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>, Response.Response<Transport(Reason)>>) -> Result_(Reason):
  match result:
    case Fail{cause}: Fail{HeaderFailure{resolution, attempts, cause}}
    case Done{response}: Done{response}

def reusedHead(-Reason: Data, result: Result<&2, &1, Progress.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>, Response.Response<Transport(Reason)>>) -> Result_(Reason):
  match result:
    case Fail{cause}: Fail{ReusedHeaderFailure{cause}}
    case Done{response}: Done{response}

def reported(~Reason: Data, report: HTTP.Report<Deadline.Cause<Reason>, SourceError()>) -> IO(Result_(Reason)):
  match report:
    case HTTP.Reused{Fail{cause}}: IO.pure(Result_(Reason), Fail{ReusedExchangeFailure{cause}})
    case HTTP.Reused{Done{exchange}}:
      do IO<Result_(Reason)>:
        result : Result<&2, &1, Progress.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>, Response.Response<Transport(Reason)>> <- Head.startExchangeResponse(~Deadline.Cause<Reason>, exchange)
        return reusedHead(Reason, result)
    case HTTP.Rejected{cause}: IO.pure(Result_(Reason), Fail{Rejected{cause}})
    case HTTP.Unresolved{resolution}: IO.pure(Result_(Reason), Fail{Unresolved{resolution}})
    case HTTP.Attempted{resolution, attempts, Fail{cause}}: IO.pure(Result_(Reason), Fail{ExchangeFailure{resolution, attempts, cause}})
    case HTTP.Attempted{resolution, attempts, Done{exchange}}:
      do IO<Result_(Reason)>:
        result : Result<&2, &1, Progress.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>, Response.Response<Transport(Reason)>> <- Head.startExchangeResponse(~Deadline.Cause<Reason>, exchange)
        return headed(Reason, resolution, attempts, result)

def prepared(~Reason: Data, context: Context<Reason>, signal: Signal(Reason), request: Result<&2, &2, Request.URLRequestError, Request.URLPrepared>) -> IO(Result_(Reason)):
  match context request:
    case _ Fail{cause}: IO.pure(Result_(Reason), Fail{InvalidRequest{cause}})
    case Context{resolver, hosts, options, proxies, security, pool} Done{request}:
      do IO<Result_(Reason)>:
        report : HTTP.Report<Deadline.Cause<Reason>, SourceError()> <- HTTP.startPooled(~Deadline.Cause<Reason>, ~(SourceError()), pool, proxies, security, resolver, signal, hosts, options, request)
        reported(~Reason, report)

def invoke(~Reason: Data, context: Context<Reason>, input: Input<Reason>) -> IO(Result_(Reason)):
  match input:
    case Input{url, method, headers, body, signal}: prepared(~Reason, context, signal, Request.prepareURL(url, method, headers, body))

def closePool(-Reason: Data, pool: HTTP.Pool<Deadline.Cause<Reason>>, unused: Unit) -> IO(Unit): HTTP.disposePool(Deadline.Cause<Reason>, pool)

def borrowed(~Reason: Data, security: HTTP.Security, +hosts: HostsResult(), +options: HTTP.Options, +proxies: Proxy.Config, pools: List<&2, C.Callback<Unit, Unit>>, pair: Resolver.Owner & Resolver.Resolver) -> IO(Runtime & Fetch(Reason)):
  match pair:
    case Tuple{owner, resolver}:
      do IO<Runtime & Fetch(Reason)>:
        +pool : HTTP.Pool<Deadline.Cause<Reason>> <- HTTP.newPool(Deadline.Cause<Reason>)
        closer : C.Callback<Unit, Unit> <- C.create(~HTTP.Pool<Deadline.Cause<Reason>>, ~Unit, ~Unit, ~closePool(Reason), pool)
        fetch : Fetch(Reason) <- C.create(~Context<Reason>, ~Input<Reason>, ~(Result_(Reason)), ~(invoke(~Reason)), Context{resolver, hosts, options, proxies, security, pool})
        return (Runtime{owner, hosts, options, proxies, closer <> pools}, fetch)

# The callback borrows the runtime's resolver: retire it before the runtime.
def callback(~Reason: Data, runtime: Runtime) -> IO(Runtime & Fetch(Reason)):
  match runtime:
    case Runtime{resolver, hosts, options, proxies, pools}: borrowed(~Reason, HTTP.NoTLS{}, hosts, options, proxies, pools, Resolver.borrow(resolver))

# The fetch callback borrows the supplied authorizer factory as well as the
# resolver. Retire fetch callbacks before disposing either owner.
def callbackWithSecurity(~Reason: Data, runtime: Runtime, security: HTTP.Security) -> IO(Runtime & Fetch(Reason)):
  match runtime:
    case Runtime{resolver, hosts, options, proxies, pools}: borrowed(~Reason, security, hosts, options, proxies, pools, Resolver.borrow(resolver))

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

def setup(-Reason: Data, error: Setup.PairSetupError<Deadline.Cause<Reason>>) -> Category:
  match error:
    case Setup.PairSetupAborted{why}: dnsAbort(Reason, why)
    case _: NonRetryable{}

# QueryFailed is the resolver's terminal outcome; ordinary network failures,
# negative replies and exhausted attempts produce NoAnswer instead.
def dnsReport(-Reason: Data, report: DNS.PairSearchReport<Deadline.Cause<Reason>>) -> Category:
  match report:
    case DNS.PairSearchReport{Fail{Search.Halted{DNS.SetupFailed{cause}}}, _}: setup(Reason, cause)
    case DNS.PairSearchReport{Fail{Search.Halted{DNS.QueryFailed{_}}}, why}: dnsDeadline(Reason, NonRetryable{}, why)
    case DNS.PairSearchReport{Fail{Search.NoAnswer{_}}, why}: dnsDeadline(Reason, Connection{}, why)
    case DNS.PairSearchReport{Done{_}, why}: dnsDeadline(Reason, Connection{}, why)

def resolutionCategory(-Reason: Data, report: Connect.Resolution(Deadline.Cause<Reason>, SourceError())) -> Category:
  match report:
    case Done{Route.Named{HostsResolve.FromNetwork{Named.PairHostsResolverCompleted{report}}}}: dnsReport(Reason, report)
    case _: NonRetryable{}

def socket(-Reason: Data, error: Socket.Error<Deadline.Cause<Reason>>) -> Category:
  match error:
    case Socket.Aborted{why}: requestAbort(Reason, why)
    case Socket.SocketError{_, _}: Connection{}

def source(-Reason: Data, error: Source.SocketSourceError<Deadline.Cause<Reason>>) -> Category:
  match error:
    case Source.SocketSourceSocketFailure{cause}: socket(Reason, cause)
    case Source.TLSSourceFailure{TLS.Network{cause}}: socket(Reason, cause)
    case Source.UploadFailure{Upload.WriteFailure{cause, None{}}}: socket(Reason, cause)
    case _: NonRetryable{}

def reader(-Reason: Data, error: Reader.ReadError<Source.SocketSourceError<Deadline.Cause<Reason>>>) -> Category:
  match error:
    case Reader.ResponseReaderPrimaryFailure{Reader.SourceError{cause}}: source(Reason, cause)
    case Reader.ResponseReaderPrimaryFailure{Reader.DecodeError{_}}: Connection{}
    case Reader.ReleaseFailure{cause}: source(Reason, cause)
    case Reader.FailureWithRelease{_, _}: NonRetryable{}

def exchangeRead(-Reason: Data, error: Exchange.ReadError<Deadline.Cause<Reason>>) -> Category:
  match error:
    case Exchange.ResponseFailure{cause}: reader(Reason, cause)
    case Exchange.DisposalFailure{cause}: source(Reason, cause)
    case Exchange.ResponseWithDisposal{_, _}: NonRetryable{}

def header(-Reason: Data, error: Progress.ResponseProgressError<Exchange.ReadError<Deadline.Cause<Reason>>>) -> Category:
  match error:
    case Progress.ResponseProgressPrimaryFailure{Progress.TransportFailure{cause}}: exchangeRead(Reason, cause)
    case Progress.ResponseProgressPrimaryFailure{Progress.MissingHead{}}: Connection{}
    case Progress.ResponseProgressPrimaryFailure{Progress.MissingCompletion{}}: Connection{}
    case Progress.ResponseProgressPrimaryFailure{Progress.UnexpectedEvent{_}}: NonRetryable{}
    case Progress.ResponseProgressCleanupFailure{cause}: exchangeRead(Reason, cause)
    case Progress.ResponseProgressFailureWithCleanup{_, _}: NonRetryable{}

def exchangeCategory(-Reason: Data, error: HTTP.ResolvedExchangeError<Deadline.Cause<Reason>>) -> Category:
  match error:
    case HTTP.ResolvedExchangeConnectionFailure{Connection.Exhausted{}}: Connection{}
    case HTTP.ResolvedExchangeConnectionFailure{Connection.ProgressAborted{why}}: requestAbort(Reason, why)
    case HTTP.ResolvedExchangeConnectionFailure{_}: NonRetryable{}
    case HTTP.ResolvedExchangeFailure{Exchange.SocketFailure{cause}}: socket(Reason, cause)
    case HTTP.ResolvedExchangeFailure{Exchange.TLSStartFailure{TLS.Network{cause}}}: socket(Reason, cause)
    case HTTP.ResolvedExchangeFailure{Exchange.WriteFailure{cause, None{}}}: socket(Reason, cause)
    case HTTP.ResolvedExchangeFailure{Exchange.SourceFailure{cause}}: source(Reason, cause)
    case HTTP.ResolvedExchangeFailure{Exchange.TunnelFailure{Proxy.TunnelSocket{cause}}}: socket(Reason, cause)
    case HTTP.ResolvedExchangeFailure{Exchange.TunnelFailure{_}}: Connection{}
    case HTTP.ResolvedExchangeFailure{_}: NonRetryable{}

def classify(-Reason: Data, error: Error<Reason>) -> Category:
  match error:
    case InvalidRequest{_}: NonRetryable{}
    case Rejected{_}: NonRetryable{}
    case Unresolved{report}: resolutionCategory(Reason, report)
    case ExchangeFailure{_, _, cause}: exchangeCategory(Reason, cause)
    case HeaderFailure{_, _, cause}: header(Reason, cause)
    case ReusedExchangeFailure{cause}: exchangeCategory(Reason, cause)
    case ReusedHeaderFailure{cause}: header(Reason, cause)

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
