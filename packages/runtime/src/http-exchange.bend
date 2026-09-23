import Base
import ./tls-socket.bend as TLS
import ./tls13-client.bend as TLSClient
import ./dns-resolver.bend as Pair
import ./http-response.bend as Response
import ./socket.bend as Connect
import ./hosts.bend as Hosts
import ./connection-driver.bend as Dispatch
import ./abort.bend as Abort
import ./http-message.bend as Request
import ./url.bend as Host
import ./dns-message.bend as Id
import ./serial-resource.bend as Resource
import ./callback.bend as C
import ./schema-value.bend as Value
import ./ref.bend as R
import ./clock.bend as Clock
import ./f64.bend as F
import ./text.bend as Text

type Plan is Data:
  Numeric{address: Connect.Address}
  Lookup{name: String}
  Invalid{}

type HostRouteError is Data:
  InvalidHost{}

type HostRouteResolution<-Report: Data> is Data:
  NumericAddress{address: Connect.Address}
  Named{report: Report}

# Consume the normalized URL host without serializing or reparsing it. URL
# IPv6 literals have no interface zone. Empty/opaque hosts are invalid for HTTP.
def plan(host: Host.Host) -> Plan:
  match host:
    case Host.IPv4{address}: Numeric{Connect.V4{address}}
    case Host.IPv6{address}: Numeric{Connect.V6{address, 0}}
    case Host.Domain{SNil{}}: Invalid{}
    case Host.Domain{name}: Lookup{name}
    case _: Invalid{}

def execute(~Context: Data, ~Report: Data, ~lookup: Context -> String -> IO(Report), context: Context, plan: Plan) -> IO(Result<&2, &2, HostRouteError, HostRouteResolution<Report>>):
  match plan:
    case Invalid{}: IO.pure(Result<&2, &2, HostRouteError, HostRouteResolution<Report>>, Fail{InvalidHost{}})
    case Numeric{address}: IO.pure(Result<&2, &2, HostRouteError, HostRouteResolution<Report>>, Done{NumericAddress{address}})
    case Lookup{name}:
      do IO<Result<&2, &2, HostRouteError, HostRouteResolution<Report>>>:
        report : Report <- lookup(context, name)
        return Done{Named{report}}

def resolveWithHostRoute(~Context: Data, ~Report: Data, ~lookup: Context -> String -> IO(Report), context: Context, host: Host.Host) -> IO(Result<&2, &2, HostRouteError, HostRouteResolution<Report>>):
  execute(~Context, ~Report, ~lookup, context, plan(host))

def family(-Reason: Data, report: Pair.Classified<Result<&2, &2, Pair.AddressLookupError<Reason>, Pair.Selection>>) -> List<&2, Connect.Address>:
  match report:
    case Pair.Classified{Done{Pair.Selection{_, addresses}}, Pair.Answer{}}: Dispatch.answers(addresses)
    case _: Nil{}

def network(-Original: Data, -Reason: Data, original: Original, report: Pair.PairSearchReport<Reason>) -> Dispatch.Plan<Original>:
  match report:
    case Pair.PairSearchReport{Done{Pair.PairResultReports{ipv4, ipv6}}, _}: Dispatch.paired(Original, original, family(Reason, ipv4), family(Reason, ipv6))
    case _: Dispatch.NoAddresses{original}

def named(-Original: Data, -Reason: Data, -Error: Data, original: Original, report: Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>) -> Dispatch.Plan<Original>:
  match report:
    case Hosts.FromHosts{first, rest}: Dispatch.ordered(Original, original, Dispatch.hosts(first <> rest))
    case Hosts.FromNetwork{Pair.PairHostsResolverCompleted{report}}: network(Original, Reason, original, report)
    case _: Dispatch.NoAddresses{original}

def project(-Original: Data, -Reason: Data, -Error: Data, original: Original, result: Result<&2, &2, HostRouteError, HostRouteResolution<Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>>>) -> Dispatch.Plan<Original>:
  match result:
    case Done{NumericAddress{address}}: Dispatch.Addresses{original, Dispatch.Ordered{address, Nil{}}}
    case Done{Named{report}}: named(Original, Reason, Error, original, report)
    case Fail{_}: Dispatch.NoAddresses{original}

# Retain the complete resolution result alongside every projection, including
# negative siblings, canonical names, TTLs and source/deadline errors. A halted
# DNS report never yields candidates, even if one family previously succeeded.
def prepare(-Reason: Data, -Error: Data, +result: Result<&2, &2, HostRouteError, HostRouteResolution<Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>>>) -> Dispatch.Plan<Result<&2, &2, HostRouteError, HostRouteResolution<Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>>>>:
  project(Result<&2, &2, HostRouteError, HostRouteResolution<Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>>>, Reason, Error, result, result)

type Context<-Environment: Data, -Reason: Data, -Error: Data> is Data:
  Context{environment: Environment, resolver: Pair.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>}

def namedHostResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~Error: Data, context: Context<Environment, Reason, Error>, name: String) -> IO(Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>):
  match context:
    case Context{environment, resolver, parent, priority, hosts}: Pair.lookupWithPairHostsResolver(~Environment, ~draw, ~Reason, ~Error, environment, resolver, parent, priority, name, hosts)

# Numeric URL hosts bypass hosts results and DNS, including failed hosts
# snapshots. Domain hosts retain the complete existing hosts/DNS report. The
# resolver and parent remain borrowed; this layer creates no connection.
def resolveWithHostResolver(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Pair.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>) -> IO(Result<&2, &2, HostRouteError, HostRouteResolution<Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>>>):
  resolveWithHostRoute(~Context<Environment, Reason, Error>, ~Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>, ~namedHostResolver(~Environment, ~draw, ~Reason, ~Error), Context{environment, resolver, parent, priority, hosts}, host)

def resolve(~Reason: Data, ~Error: Data, resolver: Pair.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>) -> IO(Result<&2, &2, HostRouteError, HostRouteResolution<Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>>>):
  resolveWithHostResolver(~Unit, ~Id.random, ~Reason, ~Error, Unit{}, resolver, parent, priority, host, hosts)

def Resolution(-Reason: Data, -Error: Data) -> Data:
  Result<&2, &2, HostRouteError, HostRouteResolution<Hosts.Report<Error, Pair.PairHostsResolverDNS<Reason>>>>

# Both adapters are injectable. The ID source and connector are independent;
# resolution error priority and connection family preference are also distinct.
def resolveWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Context: Data, ~Reason: Data, ~Error: Data, ~Value: Type, ~connect: Context -> List<&2, Connect.Address> -> IO(Dispatch.Report<Reason, Value>), environment: Environment, context: Context, resolver: Pair.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, preference: Dispatch.Preference, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>) -> IO(Dispatch.PlanReport<Resolution(Reason, Error), Reason, Value>):
  do IO<Dispatch.PlanReport<Resolution(Reason, Error), Reason, Value>>:
    resolution : Resolution(Reason, Error) <- resolveWithHostResolver(~Environment, ~draw, ~Reason, ~Error, environment, resolver, parent, priority, host, hosts)
    Dispatch.executeWith(Context, Resolution(Reason, Error), Reason, Value, connect, context, preference, prepare(Reason, Error, resolution))

type Connection<-Reason: Data> is Data:
  Connection{options: Dispatch.Options, parent: Abort.AbortSignal<Reason>}

def native(~Reason: Data, context: Connection<Reason>, addresses: List<&2, Connect.Address>) -> IO(Dispatch.Report<Reason, Socket>):
  match context:
    case Connection{options, parent}: Dispatch.run(~Reason, options, addresses, parent)

# Establish TCP only. The caller still owns resolver/parent and must complete
# TLS (when required) before sending HTTP application data over this socket.
def openWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Pair.Resolver, +parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, preference: Dispatch.Preference, options: Dispatch.Options, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>) -> IO(Dispatch.PlanReport<Resolution(Reason, Error), Reason, Socket>):
  resolveWith(~Environment, ~draw, ~Connection<Reason>, ~Reason, ~Error, ~Socket, ~native(~Reason), environment, Connection{options, parent}, resolver, parent, priority, preference, host, hosts)

def open(~Reason: Data, ~Error: Data, resolver: Pair.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, preference: Dispatch.Preference, options: Dispatch.Options, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<Hosts.Address>>>) -> IO(Dispatch.PlanReport<Resolution(Reason, Error), Reason, Socket>):
  openWith(~Unit, ~Id.random, ~Reason, ~Error, Unit{}, resolver, parent, priority, preference, options, host, hosts)

# A dedicated connected socket lease. Release closes the connection; pooling
# and reuse of response remainder belong to a different source implementation.
type SocketSourceError<-Reason: Data> is Data:
  SocketSourceSocketFailure{error: Connect.Error<Reason>}
  CleanupFailure{error: Connect.InterruptError}
  UploadFailure{error: Connect.UploadError<Reason>}
  UploadWithCleanup{error: Connect.UploadError<Reason>, cleanup: Connect.InterruptError}
  TLSSourceFailure{error: TLS.Error<Reason>}
  TLSWithCleanup{error: TLS.Error<Reason>, cleanup: TLS.Error<Reason>}
  Released{}
  SocketSourceInvalidReadSize{}

# The source owns both directions. Its upload must finish before the shared
# connection's watcher and interrupt descriptor can be retired.
type Lease<-Reason: Data> is Type:
  Lease{connection: Connect.Owner<Reason>, upload: Maybe<&1, Connect.UploadOwner<Reason>>}
  Secure{connection: TLS.Connection<Reason>, upload: Chan(Result<&2, &2, TLS.Error<Reason>, Unit>), control: TLS.Writer<Reason>, reported: Bool}

# Keep-alive (undici's Agent as bundled with Node 24): idle connections by
# origin, each running under its own abort controller that the request in
# flight links its signal to. A response read to completion on a persistent
# HTTP/1.1 connection parks the connection instead of closing it.
type Origin is Data:
  Origin{secure: Bool, host: String, port: U32}

type Parked<-Reason: Data> is Type:
  ParkedPlain{connection: Connect.Owner<Reason>}
  ParkedSecure{connection: TLS.Connection<Reason>, control: TLS.Writer<Reason>}

type Idle<-Reason: Data> is Type:
  Idle{origin: Origin, parked: Parked<Reason>, controller: Abort.AbortController<Reason>, expires: F64}

type Pool<-Reason: Data> is Data:
  Pool{idle: R.Ref<List<&1, Idle<Reason>>>, clock: Clock.Clock}

# How a response returns its connection to the pool.
type Keep<-Reason: Data> is Data:
  Keep{pool: Pool<Reason>, origin: Origin, controller: Abort.AbortController<Reason>, link: R.Ref<Maybe<&1, Abort.Link<Reason>>>, method: String}

type Environment<-Reason: Data> is Data:
  Environment{resource: Resource.Handle<Maybe<&1, Lease<Reason>>>, maximum: U32, keep: Maybe<&2, Keep<Reason>>}

type Owner<-Reason: Data> is Type:
  Owner{resource: Resource.Owner<Maybe<&1, Lease<Reason>>>, source: Response.Source<SocketSourceError<Reason>>}

def sourceBytes(-Reason: Data, value: Result<&2, &2, Connect.Error<Reason>, List<&2, U32>>) -> Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>:
  match value:
    case Fail{error}: Fail{SocketSourceSocketFailure{error}}
    case Done{Nil{}}: Done{None{}}
    case Done{head <> rest}: Done{Some{head <> rest}}

def checkedUpload(-Reason: Data, pair: Connect.UploadOwner<Reason> & Maybe<&2, Connect.Error<Reason>>) -> Maybe<&1, Connect.UploadOwner<Reason>> & Maybe<&2, Connect.Error<Reason>>:
  match pair:
    case (owner, error): (Some{owner}, error)

def checkUpload(-Reason: Data, upload: Maybe<&1, Connect.UploadOwner<Reason>>) -> IO(Maybe<&1, Connect.UploadOwner<Reason>> & Maybe<&2, Connect.Error<Reason>>):
  match upload:
    case None{}: IO.pure(Maybe<&1, Connect.UploadOwner<Reason>> & Maybe<&2, Connect.Error<Reason>>, (None{}, None{}))
    case Some{owner}:
      do IO<Maybe<&1, Connect.UploadOwner<Reason>> & Maybe<&2, Connect.Error<Reason>>>:
        result : Connect.UploadOwner<Reason> & Maybe<&2, Connect.Error<Reason>> <- Connect.checkUpload(Reason, owner)
        return checkedUpload(Reason, result)

def observed(-Reason: Data, connection: Connect.Owner<Reason>, result: Result<&2, &2, Connect.Error<Reason>, List<&2, U32>>, pair: Maybe<&1, Connect.UploadOwner<Reason>> & Maybe<&2, Connect.Error<Reason>>) -> Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>:
  match pair:
    case (upload, Some{error}): (Some{Lease{connection, upload}}, Fail{SocketSourceSocketFailure{error}})
    case (upload, None{}): (Some{Lease{connection, upload}}, sourceBytes(Reason, result))

def received(-Reason: Data, upload: Maybe<&1, Connect.UploadOwner<Reason>>, pair: Connect.Owner<Reason> & Result<&2, &2, Connect.Error<Reason>, List<&2, U32>>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>):
  match pair:
    case (connection, result):
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>>:
        checked : Maybe<&1, Connect.UploadOwner<Reason>> & Maybe<&2, Connect.Error<Reason>> <- checkUpload(Reason, upload)
        return observed(Reason, connection, result, checked)

def readChecked(-Reason: Data, maximum: U32, connection: Connect.Owner<Reason>, pair: Maybe<&1, Connect.UploadOwner<Reason>> & Maybe<&2, Connect.Error<Reason>>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>):
  match pair:
    case (upload, Some{error}): IO.pure(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>, (Some{Lease{connection, upload}}, Fail{SocketSourceSocketFailure{error}}))
    case (upload, None{}):
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>>:
        result : Connect.Owner<Reason> & Result<&2, &2, Connect.Error<Reason>, List<&2, U32>> <- Connect.recvSocket(Reason, connection, maximum)
        received(Reason, upload, result)

def receivedTLS(-Reason: Data, upload: Chan(Result<&2, &2, TLS.Error<Reason>, Unit>), control: TLS.Writer<Reason>, reported: Bool, pair: TLS.Connection<Reason> & Result<&2, &2, TLS.Error<Reason>, List<&2, U32>>) -> Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>:
  match pair:
    case (connection, Fail{error}): (Some{Secure{connection, upload, control, True{}}}, Fail{TLSSourceFailure{error}})
    case (connection, Done{Nil{}}): (Some{Secure{connection, upload, control, reported}}, Done{None{}})
    case (connection, Done{bytes}): (Some{Secure{connection, upload, control, reported}}, Done{Some{bytes}})

def readOwned(-Reason: Data, maximum: U32, value: Maybe<&1, Lease<Reason>>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>):
  match value:
    case None{}: IO.pure(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>, (None{}, Fail{Released{}}))
    case Some{Secure{connection, upload, control, reported}}:
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>>:
        result : TLS.Connection<Reason> & Result<&2, &2, TLS.Error<Reason>, List<&2, U32>> <- TLS.recv(Reason, connection, maximum)
        return receivedTLS(Reason, upload, control, reported, result)
    case Some{Lease{connection, upload}}:
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>>:
        checked : Maybe<&1, Connect.UploadOwner<Reason>> & Maybe<&2, Connect.Error<Reason>> <- checkUpload(Reason, upload)
        readChecked(Reason, maximum, connection, checked)

def classified(-Reason: Data, isReset: Bool, error: SocketSourceError<Reason>) -> Response.ReadResult<SocketSourceError<Reason>>:
  match isReset:
    case True{}: Response.Reset{error}
    case False{}: Response.Failed{error}

def classify(-Reason: Data, result: Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>) -> IO(Response.ReadResult<SocketSourceError<Reason>>):
  match result:
    case Fail{SocketSourceSocketFailure{Connect.SocketError{+code, message}}}:
      do IO<Response.ReadResult<SocketSourceError<Reason>>>:
        isReset : Bool <- Socket.isConnectionReset(code)
        return classified(Reason, isReset, SocketSourceSocketFailure{Connect.SocketError{code, message}})
    case value: IO.pure(Response.ReadResult<SocketSourceError<Reason>>, Response.fromResult(SocketSourceError<Reason>, value))

def readCallback(-Reason: Data, environment: Environment<Reason>, unused: Unit) -> IO(Response.ReadResult<SocketSourceError<Reason>>):
  match environment:
    case Environment{resource, maximum, _}:
      do IO<Response.ReadResult<SocketSourceError<Reason>>>:
        result : Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>> <- Resource.run(Maybe<&1, Lease<Reason>>, Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>, resource, value => readOwned(Reason, maximum, value))
        classify(Reason, result)

def sourceCleanup(-Reason: Data, value: Result<&2, &2, Connect.InterruptError, Unit>) -> Result<&2, &2, SocketSourceError<Reason>, Unit>:
  match value:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{CleanupFailure{error}}

def stopUpload(-Reason: Data, upload: Maybe<&1, Connect.UploadOwner<Reason>>) -> IO(Result<&2, &2, Connect.UploadError<Reason>, Unit>):
  match upload:
    case None{}: IO.pure(Result<&2, &2, Connect.UploadError<Reason>, Unit>, Done{Unit{}})
    case Some{owner}: Connect.stop(Reason, owner)

def closedSource(-Reason: Data, upload: Result<&2, &2, Connect.UploadError<Reason>, Unit>, connection: Result<&2, &2, Connect.InterruptError, Unit>) -> Result<&2, &2, SocketSourceError<Reason>, Unit>:
  match upload connection:
    case Done{_} result: sourceCleanup(Reason, result)
    case Fail{error} Done{_}: Fail{UploadFailure{error}}
    case Fail{error} Fail{secondary}: Fail{UploadWithCleanup{error, secondary}}

def tlsCleanup(-Reason: Data, first: Result<&2, &2, TLS.Error<Reason>, Unit>, second: Result<&2, &2, TLS.Error<Reason>, Unit>) -> Result<&2, &2, TLS.Error<Reason>, Unit>:
  match first:
    case Fail{error}: Fail{error}
    case Done{_}: second

def tlsUploadResult(-Reason: Data, reported: Bool, result: Result<&2, &2, TLS.Error<Reason>, Unit>) -> Result<&2, &2, TLS.Error<Reason>, Unit>:
  match reported result:
    case True{} _: Done{Unit{}}
    case _ Fail{TLS.Closed{}}: Done{Unit{}}
    case _ result: result

def closedTLS(-Reason: Data, primary: Result<&2, &2, TLS.Error<Reason>, Unit>, cleanup: Result<&2, &2, TLS.Error<Reason>, Unit>) -> Result<&2, &2, SocketSourceError<Reason>, Unit>:
  match primary cleanup:
    case Done{_} Done{_}: Done{Unit{}}
    case Fail{error} Done{_}: Fail{TLSSourceFailure{error}}
    case Done{_} Fail{error}: Fail{TLSSourceFailure{error}}
    case Fail{error} Fail{cleanup}: Fail{TLSWithCleanup{error, cleanup}}

def closeOwned(-Reason: Data, value: Maybe<&1, Lease<Reason>>) -> IO(Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match value:
    case None{}: IO.pure(Result<&2, &2, SocketSourceError<Reason>, Unit>, Done{Unit{}})
    case Some{Secure{connection, upload, control, reported}}:
      do IO<Result<&2, &2, SocketSourceError<Reason>, Unit>>:
        stopped : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.cancel(Reason, control)
        joined : Result<&2, &2, TLS.Error<Reason>, Unit> <- IO.join(Result<&2, &2, TLS.Error<Reason>, Unit>, upload)
        disposed : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.dispose(Reason, connection)
        return closedTLS(Reason, tlsUploadResult(Reason, reported, joined), tlsCleanup(Reason, stopped, disposed))
    case Some{Lease{connection, upload}}:
      do IO<Result<&2, &2, SocketSourceError<Reason>, Unit>>:
        stopped : Result<&2, &2, Connect.UploadError<Reason>, Unit> <- stopUpload(Reason, upload)
        result : Result<&2, &2, Connect.InterruptError, Unit> <- Connect.close(Reason, connection)
        return closedSource(Reason, stopped, result)

def releaseOwned(-Reason: Data, value: Maybe<&1, Lease<Reason>>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>>:
    result : Result<&2, &2, SocketSourceError<Reason>, Unit> <- closeOwned(Reason, value)
    return (None{}, result)

# Pool bookkeeping
# ----------------

def disposeParked(-Reason: Data, parked: Parked<Reason>) -> IO(Unit):
  match parked:
    case ParkedPlain{connection}:
      do IO<Unit>:
        closed : Result<&2, &2, Connect.InterruptError, Unit> <- Connect.close(Reason, connection)
        return Unit{}
    case ParkedSecure{connection, control}:
      do IO<Unit>:
        stopped : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.cancel(Reason, control)
        disposed : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.dispose(Reason, connection)
        return Unit{}

def disposeIdle(-Reason: Data, idle: Idle<Reason>) -> IO(Unit):
  match idle:
    case Idle{_, parked, controller, _}:
      do IO<Unit>:
        disposeParked(Reason, parked)
        Abort.dispose(Reason, controller)

def disposeAllIdle(-Reason: Data, idle: List<&1, Idle<Reason>>) -> IO(Unit):
  match idle:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        disposeIdle(Reason, first)
        disposeAllIdle(Reason, rest)

def newPool(-Reason: Data) -> IO(Pool<Reason>):
  do IO<Pool<Reason>>:
    clock : Clock.Clock <- Clock.new()
    idle : R.Ref<List<&1, Idle<Reason>>> <- R.new(List<&1, Idle<Reason>>, Nil{})
    return Pool{idle, clock}

# Close every idle connection. Callers first finish all exchanges started
# from the pool.
def disposePool(-Reason: Data, pool: Pool<Reason>) -> IO(Unit):
  match pool:
    case Pool{idle, _}:
      do IO<Unit>:
        remaining : List<&1, Idle<Reason>> <- R.dispose(List<&1, Idle<Reason>>, idle)
        disposeAllIdle(Reason, remaining)

def takeLink(-Reason: Data, value: Maybe<&1, Abort.Link<Reason>>) -> Maybe<&1, Abort.Link<Reason>> & Maybe<&1, Abort.Link<Reason>>:
  match value:
    case taken: (None{}, taken)

def unlinkTaken(-Reason: Data, link: Maybe<&1, Abort.Link<Reason>>) -> IO(Unit):
  match link:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: Abort.unlink(Reason, value)

# Stop forwarding the request's signal to the connection controller.
def unlinkKeep(-Reason: Data, keep: Keep<Reason>) -> IO(Unit):
  match keep:
    case Keep{_, _, _, link, _}:
      do IO<Unit>:
        taken : Maybe<&1, Abort.Link<Reason>> <- R.modify(Maybe<&1, Abort.Link<Reason>>, Maybe<&1, Abort.Link<Reason>>, link, value => takeLink(Reason, value))
        unlinkTaken(Reason, taken)

# The request ended without parking: its link and the controller go.
def retireKeep(-Reason: Data, keep: Keep<Reason>) -> IO(Unit):
  match keep:
    case Keep{_, _, controller, link, _}:
      do IO<Unit>:
        remaining : Maybe<&1, Abort.Link<Reason>> <- R.dispose(Maybe<&1, Abort.Link<Reason>>, link)
        unlinkTaken(Reason, remaining)
        Abort.dispose(Reason, controller)

def retireMaybe(-Reason: Data, keep: Maybe<&2, Keep<Reason>>) -> IO(Unit):
  match keep:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: retireKeep(Reason, value)

# undici util.parseKeepAliveTimeout: the digits after the first "timeout=".
def digitsValue(chars: String, +value: Nat, +seen: Bool) -> Maybe<&2, Nat>:
  match chars:
    case SCon{Chr{+code}, rest}:
      Bool.pick(Unit -> Maybe<&2, Nat>, U32.is_ge(code, 48) && U32.is_le(code, 57), _ => digitsValue(rest, value * 10n + U32.to_nat((code - 48 : U32)), True{}), _ => Bool.pick(Maybe<&2, Nat>, seen, Some{value}, None{}))(Unit{})
    case SNil{}: Bool.pick(Maybe<&2, Nat>, seen, Some{value}, None{})

def timeoutSeconds(value: String) -> Maybe<&2, Nat>:
  match value:
    case SNil{}: None{}
    case SCon{+char, +rest}:
      Bool.pick(Unit -> Maybe<&2, Nat>, String.starts_with(SCon{char, rest}, "timeout="), _ => digitsValue(String.drop(SCon{char, rest}, 8n), 0n, False{}), _ => timeoutSeconds(rest))(Unit{})

def keepAliveField(fields: List<&2, Request.Header>) -> Maybe<&2, String>:
  match fields:
    case Nil{}: None{}
    case Request.Header{name, value} <> rest: Bool.pick(Unit -> Maybe<&2, String>, String.eq(Text.asciiLower(name), "keep-alive"), _ => Some{value}, _ => keepAliveField(rest))(Unit{})

# undici's client: a Keep-Alive timeout hint minus the 2 s threshold, capped
# at 10 minutes (no reuse when it is not positive); otherwise 4 s.
def hintedTimeout(seconds: Maybe<&2, Nat>) -> Maybe<&2, F64>:
  match seconds:
    case None{}: Some{F.fromU32(4000)}
    case Some{+value}: Bool.pick(Unit -> Maybe<&2, F64>, Nat.is_le(value * 1000n, 2000n), _ => None{}, _ => Some{F.fromNat(Nat.min(Nat.sub(value * 1000n, 2000n), 600000n))})(Unit{})

def idleTimeout(fields: List<&2, Request.Header>) -> Maybe<&2, F64>:
  hintedTimeout(Maybe.bind(&2, String, Nat, keepAliveField(fields), timeoutSeconds))

def modernVersion(+major: U32, minor: U32) -> Bool: U32.is_gt(major, 1) || (U32.is_eq(major, 1) && U32.is_ge(minor, 1))

def persistentHead(head: Request.ResponseHead) -> Maybe<&2, F64>:
  match head:
    case Request.ResponseHead{Request.StatusLine{major, minor, _, _}, +fields}:
      Bool.pick(Unit -> Maybe<&2, F64>, Response.persistent(modernVersion(major, minor), Response.terminationFields(fields, Response.Connection{False{}, False{}})), _ => idleTimeout(fields), _ => None{})(Unit{})

# A response is reusable once its message completed with nothing left over
# on a persistent connection; undici never reuses after HEAD.
def reusableTimeout(+method: String, release: Response.Release) -> Maybe<&2, F64>:
  match release:
    case Response.Release{Response.MessageComplete{Nil{}}, Some{head}}: Bool.pick(Unit -> Maybe<&2, F64>, String.eq(method, "HEAD"), _ => None{}, _ => persistentHead(head))(Unit{})
    case _: None{}

def parkedIn(-Reason: Data, keep: Keep<Reason>, parked: Parked<Reason>, milliseconds: F64) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match keep:
    case Keep{Pool{idle, clock}, origin, controller, link, _}:
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>>:
        now : F64 <- Clock.now(clock)
        R.modify(List<&1, Idle<Reason>>, Unit, idle, previous => (List.append(&1, Idle<Reason>, previous, Idle{origin, parked, controller, F.add(now, milliseconds)} <> Nil{}), Unit{}))
        remaining : Maybe<&1, Abort.Link<Reason>> <- R.dispose(Maybe<&1, Abort.Link<Reason>>, link)
        unlinkTaken(Reason, remaining)
        return (None{}, Done{Unit{}})

def closedKept(-Reason: Data, keep: Keep<Reason>, result: Result<&2, &2, SocketSourceError<Reason>, Unit>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>>:
    retireKeep(Reason, keep)
    return (None{}, result)

def closeKept(-Reason: Data, keep: Keep<Reason>, lease: Lease<Reason>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>>:
    result : Result<&2, &2, SocketSourceError<Reason>, Unit> <- closeOwned(Reason, Some{lease})
    closedKept(Reason, keep, result)

def plainUploaded(-Reason: Data, keep: Keep<Reason>, connection: Connect.Owner<Reason>, milliseconds: F64, stopped: Result<&2, &2, Connect.UploadError<Reason>, Unit>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match stopped:
    case Done{_}: parkedIn(Reason, keep, ParkedPlain{connection}, milliseconds)
    case Fail{_}: closeKept(Reason, keep, Lease{connection, None{}})

def plainSettled(-Reason: Data, keep: Keep<Reason>, connection: Connect.Owner<Reason>, milliseconds: F64, pair: Connect.UploadOwner<Reason> & Bool) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match pair:
    case (upload, False{}): closeKept(Reason, keep, Lease{connection, Some{upload}})
    case (upload, True{}):
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>>:
        stopped : Result<&2, &2, Connect.UploadError<Reason>, Unit> <- Connect.stop(Reason, upload)
        plainUploaded(Reason, keep, connection, milliseconds, stopped)

def secureUploaded(-Reason: Data, keep: Keep<Reason>, connection: TLS.Connection<Reason>, control: TLS.Writer<Reason>, milliseconds: F64, joined: Result<&2, &2, TLS.Error<Reason>, Unit>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match joined:
    case Done{_}: parkedIn(Reason, keep, ParkedSecure{connection, control}, milliseconds)
    case Fail{_}:
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>>:
        stopped : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.cancel(Reason, control)
        disposed : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.dispose(Reason, connection)
        closedKept(Reason, keep, closedTLS(Reason, Done{Unit{}}, tlsCleanup(Reason, stopped, disposed)))

# The request's upload must have finished before the connection is parked.
def parkLease(-Reason: Data, keep: Keep<Reason>, lease: Lease<Reason>, milliseconds: F64) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match lease:
    case Lease{connection, None{}}: parkedIn(Reason, keep, ParkedPlain{connection}, milliseconds)
    case Lease{connection, Some{upload}}:
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>>:
        pair : Connect.UploadOwner<Reason> & Bool <- Connect.uploadSettled(Reason, upload)
        plainSettled(Reason, keep, connection, milliseconds, pair)
    case Secure{connection, upload, control, _}:
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>>:
        joined : Result<&2, &2, TLS.Error<Reason>, Unit> <- IO.join(Result<&2, &2, TLS.Error<Reason>, Unit>, upload)
        secureUploaded(Reason, keep, connection, control, milliseconds, joined)

def parkChecked(-Reason: Data, keep: Keep<Reason>, lease: Lease<Reason>, aborted: Bool, timeout: Maybe<&2, F64>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match aborted timeout:
    case False{} Some{milliseconds}: parkLease(Reason, keep, lease, milliseconds)
    case _ _: closeKept(Reason, keep, lease)

def controllerOf(-Reason: Data, keep: Keep<Reason>) -> Abort.AbortController<Reason>:
  match keep:
    case Keep{_, _, controller, _, _}: controller

def methodOf(-Reason: Data, keep: Keep<Reason>) -> String:
  match keep:
    case Keep{_, _, _, _, method}: method

def releaseKept(-Reason: Data, +keep: Keep<Reason>, +release: Response.Release, value: Maybe<&1, Lease<Reason>>) -> IO(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match value:
    case None{}: IO.pure(Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>, (None{}, Done{Unit{}}))
    case Some{lease}:
      do IO<Maybe<&1, Lease<Reason>> & Result<&2, &2, SocketSourceError<Reason>, Unit>>:
        unlinkKeep(Reason, keep)
        aborted : Bool <- Abort.aborted(Reason, Abort.signal(Reason, controllerOf(Reason, keep)))
        parkChecked(Reason, keep, lease, aborted, reusableTimeout(methodOf(Reason, keep), release))

def releaseCallback(-Reason: Data, environment: Environment<Reason>, release: Response.Release) -> IO(Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match environment:
    case Environment{resource, _, None{}}: Resource.run(Maybe<&1, Lease<Reason>>, Result<&2, &2, SocketSourceError<Reason>, Unit>, resource, value => releaseOwned(Reason, value))
    case Environment{resource, _, Some{keep}}: Resource.run(Maybe<&1, Lease<Reason>>, Result<&2, &2, SocketSourceError<Reason>, Unit>, resource, value => releaseKept(Reason, keep, release, value))

def callbacks(~Reason: Data, +maximum: U32, +keep: Maybe<&2, Keep<Reason>>, pair: Resource.Owner<Maybe<&1, Lease<Reason>>> & Resource.Handle<Maybe<&1, Lease<Reason>>>) -> IO(Owner<Reason>):
  match pair:
    case (resource, +handle):
      do IO<Owner<Reason>>:
        reader : C.Callback<Unit, Response.ReadResult<SocketSourceError<Reason>>> <- C.create(~Environment<Reason>, ~Unit, ~Response.ReadResult<SocketSourceError<Reason>>, ~readCallback(Reason), Environment{handle, maximum, keep})
        release : C.Callback<Response.Release, Result<&2, &2, SocketSourceError<Reason>, Unit>> <- C.create(~Environment<Reason>, ~Response.Release, ~Result<&2, &2, SocketSourceError<Reason>, Unit>, ~releaseCallback(Reason), Environment{handle, maximum, keep})
        return Owner{resource, Response.TransportSource{reader, release}}

def adoptLease(~Reason: Data, maximum: U32, keep: Maybe<&2, Keep<Reason>>, lease: Lease<Reason>) -> IO(Owner<Reason>):
  do IO<Owner<Reason>>:
    resource : Resource.Owner<Maybe<&1, Lease<Reason>>> <- Resource.create(Maybe<&1, Lease<Reason>>, Some{lease})
    callbacks(~Reason, maximum, keep, Resource.borrow(Maybe<&1, Lease<Reason>>, resource))

def adoptedSource(~Reason: Data, maximum: U32, result: Result<&2, &1, Connect.Error<Reason>, Connect.Owner<Reason>>) -> IO(Result<&2, &1, SocketSourceError<Reason>, Owner<Reason>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &1, SocketSourceError<Reason>, Owner<Reason>>, Fail{SocketSourceSocketFailure{error}})
    case Done{owner}:
      do IO<Result<&2, &1, SocketSourceError<Reason>, Owner<Reason>>>:
        result : Owner<Reason> <- adoptLease(~Reason, maximum, None{}, Lease{owner, None{}})
        return Done{result}

# Transfers the connected socket on every path. A zero-size read would look
# like EOF to the decoder, so reject it before constructing the byte source.
def create(~Reason: Data, socket: Socket, signal: Abort.AbortSignal<Reason>, maximum: U32) -> IO(Result<&2, &1, SocketSourceError<Reason>, Owner<Reason>>):
  match maximum:
    case 0:
      do IO<Result<&2, &1, SocketSourceError<Reason>, Owner<Reason>>>:
        Socket.close(socket)
        return Fail{SocketSourceInvalidReadSize{}}
    case size:
      do IO<Result<&2, &1, SocketSourceError<Reason>, Owner<Reason>>>:
        result : Result<&2, &1, Connect.Error<Reason>, Connect.Owner<Reason>> <- Connect.create(Reason, socket, signal)
        adoptedSource(~Reason, size, result)

# Grant this borrowed lease to one response cursor only.
def borrow(-Reason: Data, owner: Owner<Reason>) -> Owner<Reason> & Response.Source<SocketSourceError<Reason>>:
  match owner:
    case Owner{resource, +source}: (Owner{resource, source}, source)

def disposeCallbacks(-Reason: Data, source: Response.Source<SocketSourceError<Reason>>) -> IO(Unit):
  match source:
    case Response.TransportSource{reader, release}:
      do IO<Unit>:
        C.dispose(Unit, Response.ReadResult<SocketSourceError<Reason>>, reader)
        C.dispose(Response.Release, Result<&2, &2, SocketSourceError<Reason>, Unit>, release)
    case Response.Source{reader, release}:
      do IO<Unit>:
        C.dispose(Unit, Result<&2, &2, SocketSourceError<Reason>, Maybe<&2, List<&2, U32>>>, reader)
        C.dispose(Response.Release, Result<&2, &2, SocketSourceError<Reason>, Unit>, release)

# Retire the cursor and finish all callback users first. Disposal also closes
# an unused lease, then frees the callback factories and serial resource.
def dispose(-Reason: Data, owner: Owner<Reason>) -> IO(Result<&2, &2, SocketSourceError<Reason>, Unit>):
  match owner:
    case Owner{resource, source}:
      do IO<Result<&2, &2, SocketSourceError<Reason>, Unit>>:
        value : Maybe<&1, Lease<Reason>> <- Resource.retire(Maybe<&1, Lease<Reason>>, resource)
        result : Result<&2, &2, SocketSourceError<Reason>, Unit> <- closeOwned(Reason, value)
        disposeCallbacks(Reason, source)
        return result

# Dedicated HTTP/1.1 exchanges share one response parser across plain and TLS
# connections. Request uploads run concurrently with response reads and are
# joined on release; connection establishment and URL preparation stay separate.
type StartError<-Reason: Data> is Data:
  InvalidReadSize{}
  TLSStartFailure{error: TLS.Error<Reason>}
  SocketFailure{error: Connect.Error<Reason>}
  WriteFailure{error: Connect.Error<Reason>, cleanup: Maybe<&2, Connect.InterruptError>}
  SourceFailure{error: SocketSourceError<Reason>}

type ReadError<-Reason: Data> is Data:
  ResponseFailure{error: Response.ReadError<SocketSourceError<Reason>>}
  DisposalFailure{error: SocketSourceError<Reason>}
  ResponseWithDisposal{error: Response.ReadError<SocketSourceError<Reason>>, disposal: SocketSourceError<Reason>}

type Exchange<-Reason: Data> is Type:
  Open{owner: Owner<Reason>, cursor: Response.Cursor<SocketSourceError<Reason>>}
  Closed{}

type Next<-Reason: Data> is Type:
  Next{exchange: Exchange<Reason>, result: Result<&2, &2, ReadError<Reason>, Maybe<&2, Response.StreamEvent>>}

def opened(-Reason: Data, method: String, limits: Response.Limits, pair: Owner<Reason> & Response.Source<SocketSourceError<Reason>>) -> Exchange<Reason>:
  match pair:
    case (owner, source): Open{owner, Response.createReader(SocketSourceError<Reason>, source, method, limits)}

def adopted(-Reason: Data, method: String, limits: Response.Limits, result: Result<&2, &1, SocketSourceError<Reason>, Owner<Reason>>) -> Result<&2, &1, StartError<Reason>, Exchange<Reason>>:
  match result:
    case Fail{error}: Fail{SourceFailure{error}}
    case Done{owner}: Done{opened(Reason, method, limits, borrow(Reason, owner))}

def cleanupError(result: Result<&2, &2, Connect.InterruptError, Unit>) -> Maybe<&2, Connect.InterruptError>:
  match result:
    case Done{_}: None{}
    case Fail{error}: Some{error}

def uploading(~Reason: Data, method: String, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>, pair: Connect.Owner<Reason> & Result<&2, &1, Connect.Error<Reason>, Connect.UploadOwner<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match pair:
    case (owner, Fail{error}):
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        cleanup : Result<&2, &2, Connect.InterruptError, Unit> <- Connect.close(Reason, owner)
        return Fail{WriteFailure{error, cleanupError(cleanup)}}
    case (owner, Done{upload}):
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        source : Owner<Reason> <- adoptLease(~Reason, maximum, keep, Lease{owner, Some{upload}})
        return Done{opened(Reason, method, limits, borrow(Reason, source))}

def connectedSocketExchange(~Reason: Data, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>, result: Result<&2, &1, Connect.Error<Reason>, Connect.Owner<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match request result:
    case _ Fail{error}: IO.pure(Result<&2, &1, StartError<Reason>, Exchange<Reason>>, Fail{SocketFailure{error}})
    case Request.BufferedRequestPrepared{Request.Head{method, head}, body} Done{owner}:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        result : Connect.Owner<Reason> & Result<&2, &1, Connect.Error<Reason>, Connect.UploadOwner<Reason>> <- Connect.startUpload(Reason, owner, head, Request.wireBody(body))
        uploading(~Reason, method, maximum, limits, keep, result)

# Takes ownership on every path. The read-size guard precedes any request IO.
# Writes share the connection-wide AbortSignal observation with response reads.
def startSocketExchangeKept(~Reason: Data, socket: Socket, signal: Abort.AbortSignal<Reason>, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match maximum:
    case 0:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        Socket.close(socket)
        return Fail{InvalidReadSize{}}
    case size:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        result : Result<&2, &1, Connect.Error<Reason>, Connect.Owner<Reason>> <- Connect.create(Reason, socket, signal)
        connectedSocketExchange(~Reason, request, size, limits, keep, result)

def startSocketExchange(~Reason: Data, socket: Socket, signal: Abort.AbortSignal<Reason>, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  startSocketExchangeKept(~Reason, socket, signal, request, maximum, limits, None{})

def sendTLSBody(-Reason: Data, writer: TLS.Writer<Reason>, body: List<&2, U32>, headResult: Result<&2, &2, TLS.Error<Reason>, Unit>) -> IO(Result<&2, &2, TLS.Error<Reason>, Unit>):
  match headResult:
    case Fail{error}: IO.pure(Result<&2, &2, TLS.Error<Reason>, Unit>, Fail{error})
    case Done{_}: TLS.send(Reason, writer, body)

def sendTLSRequest(-Reason: Data, +writer: TLS.Writer<Reason>, head: List<&2, U32>, body: List<&2, U32>) -> IO(Result<&2, &2, TLS.Error<Reason>, Unit>):
  do IO<Result<&2, &2, TLS.Error<Reason>, Unit>>:
    sent : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.send(Reason, writer, head)
    sendTLSBody(Reason, writer, body, sent)

def uploadTLS(~Reason: Data, method: String, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>, head: List<&2, U32>, body: List<&2, U32>, pair: TLS.Connection<Reason> & TLS.Writer<Reason>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match pair:
    case (connection, +writer):
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        upload : Chan(Result<&2, &2, TLS.Error<Reason>, Unit>) <- IO.fork(Result<&2, &2, TLS.Error<Reason>, Unit>, sendTLSRequest(Reason, writer, head, body))
        owner : Owner<Reason> <- adoptLease(~Reason, maximum, keep, Secure{connection, upload, writer, False{}})
        return Done{opened(Reason, method, limits, borrow(Reason, owner))}

def authenticatedTLS(~Reason: Data, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>, result: Result<&2, &1, TLS.Error<Reason>, TLS.Connection<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match request result:
    case _ Fail{error}: IO.pure(Result<&2, &1, StartError<Reason>, Exchange<Reason>>, Fail{TLSStartFailure{error}})
    case Request.BufferedRequestPrepared{Request.Head{method, head}, body} Done{connection}:
      uploadTLS(~Reason, method, maximum, limits, keep, head, Request.wireBody(body), TLS.borrowWriter(Reason, connection))

# Consumes a started TLS connection on every path and authenticates it before
# sending HTTP bytes. Both transports share the response parser and body API.
def startTLSExchangeKept(~Reason: Data, connection: TLS.Connection<Reason>, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match maximum:
    case 0:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        cleanup : Result<&2, &2, TLS.Error<Reason>, Unit> <- TLS.dispose(Reason, connection)
        return Fail{InvalidReadSize{}}
    case size:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        result : Result<&2, &1, TLS.Error<Reason>, TLS.Connection<Reason>> <- TLS.awaitHandshake(Reason, connection)
        authenticatedTLS(~Reason, request, size, limits, keep, result)

def startTLSExchange(~Reason: Data, connection: TLS.Connection<Reason>, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  startTLSExchangeKept(~Reason, connection, request, maximum, limits, None{})

def outcome(-Reason: Data, primary: Result<&2, &2, Response.ReadError<SocketSourceError<Reason>>, Unit>, disposal: Result<&2, &2, SocketSourceError<Reason>, Unit>) -> Result<&2, &2, ReadError<Reason>, Unit>:
  match primary disposal:
    case Done{_} Done{_}: Done{Unit{}}
    case Fail{error} Done{_}: Fail{ResponseFailure{error}}
    case Done{_} Fail{error}: Fail{DisposalFailure{error}}
    case Fail{error} Fail{disposal}: Fail{ResponseWithDisposal{error, disposal}}

def ended(-Reason: Data, result: Result<&2, &2, ReadError<Reason>, Unit>) -> Next<Reason>:
  match result:
    case Done{_}: Next{Closed{}, Done{None{}}}
    case Fail{error}: Next{Closed{}, Fail{error}}

def finish(-Reason: Data, owner: Owner<Reason>, result: Result<&2, &2, Response.ReadError<SocketSourceError<Reason>>, Unit>) -> IO(Next<Reason>):
  do IO<Next<Reason>>:
    disposed : Result<&2, &2, SocketSourceError<Reason>, Unit> <- dispose(Reason, owner)
    return ended(Reason, outcome(Reason, result, disposed))

def readSocketExchange(-Reason: Data, owner: Owner<Reason>, result: Response.ResponseReaderNext<SocketSourceError<Reason>>) -> IO(Next<Reason>):
  match result:
    case Response.ResponseReaderNext{_, Fail{error}}: finish(Reason, owner, Fail{error})
    case Response.ResponseReaderNext{_, Done{None{}}}: finish(Reason, owner, Done{Unit{}})
    case Response.ResponseReaderNext{cursor, Done{Some{event}}}: IO.pure(Next<Reason>, Next{Open{owner, cursor}, Done{Some{event}}})

# EOF/errors retire callback factories as well as the socket. Early consumers
# must close explicitly; merely dropping an affine Bend value is not disposal.
def nextSocketExchange(-Reason: Data, exchange: Exchange<Reason>) -> IO(Next<Reason>):
  match exchange:
    case Closed{}: IO.pure(Next<Reason>, Next{Closed{}, Done{None{}}})
    case Open{owner, cursor}:
      do IO<Next<Reason>>:
        result : Response.ResponseReaderNext<SocketSourceError<Reason>> <- Response.readerNext(SocketSourceError<Reason>, cursor)
        readSocketExchange(Reason, owner, result)

def closed(-Reason: Data, owner: Owner<Reason>, result: Response.CloseResult<SocketSourceError<Reason>>) -> IO(Result<&2, &2, ReadError<Reason>, Unit>):
  match result:
    case Response.CloseResult{_, primary}:
      do IO<Result<&2, &2, ReadError<Reason>, Unit>>:
        disposal : Result<&2, &2, SocketSourceError<Reason>, Unit> <- dispose(Reason, owner)
        return outcome(Reason, primary, disposal)

def closeSocketExchange(-Reason: Data, exchange: Exchange<Reason>) -> IO(Result<&2, &2, ReadError<Reason>, Unit>):
  match exchange:
    case Closed{}: IO.pure(Result<&2, &2, ReadError<Reason>, Unit>, Done{Unit{}})
    case Open{owner, cursor}:
      do IO<Result<&2, &2, ReadError<Reason>, Unit>>:
        result : Response.CloseResult<SocketSourceError<Reason>> <- Response.closeReader(SocketSourceError<Reason>, cursor)
        closed(Reason, owner, result)

# Numeric cleartext transport. Address selection, TLS and URL preparation are
# caller responsibilities; request authority is independent of its chosen IP.
type Error<-Reason: Data> is Data:
  ConnectionFailure{error: Connect.Error<Reason>}
  ExchangeFailure{error: StartError<Reason>}

def started(-Reason: Data, result: Result<&2, &1, StartError<Reason>, Exchange<Reason>>) -> Result<&2, &1, Error<Reason>, Exchange<Reason>>:
  match result:
    case Fail{error}: Fail{ExchangeFailure{error}}
    case Done{exchange}: Done{exchange}

def connected(~Reason: Data, signal: Abort.AbortSignal<Reason>, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, result: Result<&2, &1, Connect.Error<Reason>, Socket>) -> IO(Result<&2, &1, Error<Reason>, Exchange<Reason>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &1, Error<Reason>, Exchange<Reason>>, Fail{ConnectionFailure{error}})
    case Done{socket}:
      do IO<Result<&2, &1, Error<Reason>, Exchange<Reason>>>:
        result : Result<&2, &1, StartError<Reason>, Exchange<Reason>> <- startSocketExchange(~Reason, socket, signal, request, maximum, limits)
        return started(Reason, result)

# The same retained signal spans connect, upload and response reads. Socket
# adoption rechecks it, including abort between connect and watcher handoff.
# On success callers consume or close the exchange before disposing the signal.
def start(~Reason: Data, address: Connect.Address, port: U32, +signal: Abort.AbortSignal<Reason>, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits) -> IO(Result<&2, &1, Error<Reason>, Exchange<Reason>>):
  match maximum:
    case 0: IO.pure(Result<&2, &1, Error<Reason>, Exchange<Reason>>, Fail{ExchangeFailure{InvalidReadSize{}}})
    case size:
      do IO<Result<&2, &1, Error<Reason>, Exchange<Reason>>>:
        result : Result<&2, &1, Connect.Error<Reason>, Socket> <- Connect.connect(Reason, address, port, signal)
        connected(~Reason, signal, request, size, limits, result)

def unpack(-Reason: Data, result: Next<Reason>) -> Exchange<Reason> & Result<&2, &2, ReadError<Reason>, Maybe<&2, Response.StreamEvent>>:
  match result:
    case Next{exchange, result}: (exchange, result)

def read(-Reason: Data, exchange: Exchange<Reason>) -> IO(Exchange<Reason> & Result<&2, &2, ReadError<Reason>, Maybe<&2, Response.StreamEvent>>):
  do IO<Exchange<Reason> & Result<&2, &2, ReadError<Reason>, Maybe<&2, Response.StreamEvent>>>:
    result : Next<Reason> <- nextSocketExchange(Reason, exchange)
    return unpack(Reason, result)

def startExchangeResponse(~Reason: Data, exchange: Exchange<Reason>) -> IO(Result<&2, &1, Response.ResponseProgressError<ReadError<Reason>>, Response.Response<Exchange<Reason>>>):
  Response.startWith(~(ReadError<Reason>), ~(Exchange<Reason>), ~(read(Reason)), ~(closeSocketExchange(Reason)), exchange)

def next(~Reason: Data, body: Response.Body<Exchange<Reason>>) -> IO(Response.Next<ReadError<Reason>, Exchange<Reason>>):
  Response.nextWith(~(ReadError<Reason>), ~(Exchange<Reason>), ~(read(Reason)), ~(closeSocketExchange(Reason)), body)

def close(-Reason: Data, body: Response.Body<Exchange<Reason>>) -> IO(Response.Next<ReadError<Reason>, Exchange<Reason>>):
  Response.closeWith(ReadError<Reason>, Exchange<Reason>, closeSocketExchange(Reason), body)

def responseSource(~Reason: Data, ~E: Data, ~map: Response.ResponseProgressError<ReadError<Reason>> -> E, body: Response.Body<Exchange<Reason>>) -> IO(Response.Owner<Exchange<Reason>, E>):
  Response.create(~ReadError<Reason>, ~Exchange<Reason>, ~E, ~map, ~(read(Reason)), ~(closeSocketExchange(Reason)), body)

# Consume and retire the owned body under an explicit caller byte budget.
def bytes(~Reason: Data, limit: Nat, body: Response.Body<Exchange<Reason>>) -> IO(Result<&2, &2, Response.Error<ReadError<Reason>>, List<&2, U32>>):
  Response.bytesWith(~(ReadError<Reason>), ~(Exchange<Reason>), ~(read(Reason)), ~(closeSocketExchange(Reason)), limit, body)

def text(~Reason: Data, limit: Nat, body: Response.Body<Exchange<Reason>>) -> IO(Result<&2, &2, Response.TextError<ReadError<Reason>>, String>):
  Response.textWith(~(ReadError<Reason>), ~(Exchange<Reason>), ~(read(Reason)), ~(closeSocketExchange(Reason)), limit, body)

def json(~Reason: Data, limit: Nat, body: Response.Body<Exchange<Reason>>) -> IO(Result<&2, &2, Response.JSONError<ReadError<Reason>>, Value.Value>):
  Response.jsonWith(~(ReadError<Reason>), ~(Exchange<Reason>), ~(read(Reason)), ~(closeSocketExchange(Reason)), limit, body)

type ResolvedExchangeError<-Reason: Data> is Data:
  ResolvedExchangeConnectionFailure{error: Dispatch.ProgressError<Reason>}
  ResolvedExchangeFailure{error: StartError<Reason>}

type Report<-Reason: Data, -SourceError: Data> is Type:
  Rejected{error: Request.ExchangePlanError}
  Unresolved{resolution: Resolution(Reason, SourceError)}
  Attempted{resolution: Resolution(Reason, SourceError), attempts: List<&2, Dispatch.Entry<Reason>>, result: Result<&2, &1, ResolvedExchangeError<Reason>, Exchange<Reason>>}
  Reused{result: Result<&2, &1, ResolvedExchangeError<Reason>, Exchange<Reason>>}

type Options is Data:
  Options{priority: Pair.Priority, preference: Dispatch.Preference, attemptMilliseconds: U32, maximum: U32, limits: Response.Limits}

def startedResolvedExchange(-Reason: Data, result: Result<&2, &1, StartError<Reason>, Exchange<Reason>>) -> Result<&2, &1, ResolvedExchangeError<Reason>, Exchange<Reason>>:
  match result:
    case Fail{error}: Fail{ResolvedExchangeFailure{error}}
    case Done{exchange}: Done{exchange}

# The authorizer factory is borrowed. It receives the normalized URL host,
# never a resolver-selected address, and returns one verifier per connection.
type Security is Data:
  NoTLS{}
  WithTLS{authorize: C.Callback<Host.Host, TLSClient.Authorization>, options: TLS.Options}

type Protocol is Data:
  Cleartext{}
  Encrypted{host: Host.Host, authorize: C.Callback<Host.Host, TLSClient.Authorization>, options: TLS.Options}

def serverName(host: Host.Host) -> Maybe<&2, String>:
  match host:
    case Host.Domain{name}: Some{name}
    case _: None{}

def protocol(security: Security, transport: Request.Transport, host: Host.Host) -> Result<&2, &2, Request.ExchangePlanError, Protocol>:
  match security transport:
    case _ Request.Plaintext{}: Done{Cleartext{}}
    case NoTLS{} Request.TLS{}: Fail{Request.TLSRequired{}}
    case WithTLS{authorize, options} Request.TLS{}: Done{Encrypted{host, authorize, options}}

def openedTLS(~Reason: Data, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>, initial: Result<&2, &1, TLS.Error<Reason>, TLS.Connection<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match initial:
    case Fail{error}: IO.pure(Result<&2, &1, StartError<Reason>, Exchange<Reason>>, Fail{TLSStartFailure{error}})
    case Done{connection}: startTLSExchangeKept(~Reason, connection, request, maximum, limits, keep)

def adoptedTLS(~Reason: Data, +host: Host.Host, authorize: C.Callback<Host.Host, TLSClient.Authorization>, options: TLS.Options, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>, adoption: Result<&2, &1, Connect.Error<Reason>, Connect.Owner<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match adoption:
    case Fail{error}: IO.pure(Result<&2, &1, StartError<Reason>, Exchange<Reason>>, Fail{SocketFailure{error}})
    case Done{owner}:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        authorization : TLSClient.Authorization <- C.call(Host.Host, TLSClient.Authorization, authorize, host)
        initial : Result<&2, &1, TLS.Error<Reason>, TLS.Connection<Reason>> <- TLS.start(Reason, owner, serverName(host), authorization, options)
        openedTLS(~Reason, request, maximum, limits, keep, initial)

def startProtocol(~Reason: Data, selected: Protocol, socket: Socket, signal: Abort.AbortSignal<Reason>, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match selected:
    case Cleartext{}: startSocketExchangeKept(~Reason, socket, signal, request, maximum, limits, keep)
    case Encrypted{host, authorize, options}:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        adoption : Result<&2, &1, Connect.Error<Reason>, Connect.Owner<Reason>> <- Connect.create(Reason, socket, signal)
        adoptedTLS(~Reason, host, authorize, options, request, maximum, limits, keep, adoption)

# Socket adoption consumes the socket on all paths and rechecks the retained
# signal. Only then create the verifier, so time-dependent policy is fresh
# after DNS and connection attempts. The full connection log survives.
def connectedResolvedExchange(~Reason: Data, ~SourceError: Data, selected: Protocol, signal: Abort.AbortSignal<Reason>, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, keep: Maybe<&2, Keep<Reason>>, report: Dispatch.PlanReport<Resolution(Reason, SourceError), Reason, Socket>) -> IO(Report<Reason, SourceError>):
  match report:
    case Dispatch.Unresolved{resolution}: IO.pure(Report<Reason, SourceError>, Unresolved{resolution})
    case Dispatch.Attempted{resolution, Dispatch.Report{Fail{error}, attempts}}: IO.pure(Report<Reason, SourceError>, Attempted{resolution, attempts, Fail{ResolvedExchangeConnectionFailure{error}}})
    case Dispatch.Attempted{resolution, Dispatch.Report{Done{socket}, attempts}}:
      do IO<Report<Reason, SourceError>>:
        result : Result<&2, &1, StartError<Reason>, Exchange<Reason>> <- startProtocol(~Reason, selected, socket, signal, request, maximum, limits, keep)
        return Attempted{resolution, attempts, startedResolvedExchange(Reason, result)}

def planned(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~SourceError: Data, selected: Protocol, environment: Environment, resolver: Pair.Resolver, +signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<Hosts.Address>>>, options: Options, keep: Maybe<&2, Keep<Reason>>, plan: Request.Plan<Request.BufferedRequestPrepared>) -> IO(Report<Reason, SourceError>):
  match options plan:
    case _ Request.Rejected{error}: IO.pure(Report<Reason, SourceError>, Rejected{error})
    case Options{priority, preference, duration, _, limits} Request.Start{host, port, +request, +maximum}:
      do IO<Report<Reason, SourceError>>:
        report : Dispatch.PlanReport<Resolution(Reason, SourceError), Reason, Socket> <- openWith(~Environment, ~draw, ~Reason, ~SourceError, environment, resolver, signal, priority, preference, Dispatch.Options{port, duration}, host, hosts)
        connectedResolvedExchange(~Reason, ~SourceError, selected, signal, request, maximum, limits, keep, report)

# A caller retains resolver and signal ownership. On success it must consume
# or close the exchange before disposing the signal; upload/read tasks belong
# to that exchange. This is the cleartext path, not a TLS implementation.
def startWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~SourceError: Data, environment: Environment, resolver: Pair.Resolver, signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<Hosts.Address>>>, options: Options, request: Request.URLPrepared) -> IO(Report<Reason, SourceError>):
  match options request:
    case Options{priority, preference, duration, +maximum, limits} Request.URLPrepared{endpoint, prepared}:
      planned(~Environment, ~draw, ~Reason, ~SourceError, Cleartext{}, environment, resolver, signal, hosts, Options{priority, preference, duration, maximum, limits}, None{}, Request.prepareExchangePlan(Request.BufferedRequestPrepared, endpoint, prepared, maximum))

def startResolvedExchange(~Reason: Data, ~SourceError: Data, resolver: Pair.Resolver, signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<Hosts.Address>>>, options: Options, request: Request.URLPrepared) -> IO(Report<Reason, SourceError>):
  startWith(~Unit, ~Id.random, ~Reason, ~SourceError, Unit{}, resolver, signal, hosts, options, request)

# Security-aware routing retains the same resolution and connection-attempt
# report as cleartext. TLS rejection or zero read size happens before dialing.
def routedPlan(host: Host.Host, port: U32, request: Request.BufferedRequestPrepared, maximum: U32) -> Request.Plan<Request.BufferedRequestPrepared>:
  match maximum:
    case 0: Request.Rejected{Request.InvalidReadSize{}}
    case size: Request.Start{host, port, request, size}

def configuredRoute(~Reason: Data, ~SourceError: Data, resolver: Pair.Resolver, signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<Hosts.Address>>>, options: Options, keep: Maybe<&2, Keep<Reason>>, plan: Request.Plan<Request.BufferedRequestPrepared>, selected: Result<&2, &2, Request.ExchangePlanError, Protocol>) -> IO(Report<Reason, SourceError>):
  match selected:
    case Fail{error}: IO.pure(Report<Reason, SourceError>, Rejected{error})
    case Done{selected}: planned(~Unit, ~Id.random, ~Reason, ~SourceError, selected, Unit{}, resolver, signal, hosts, options, keep, plan)

def startResolvedWithSecurity(~Reason: Data, ~SourceError: Data, security: Security, resolver: Pair.Resolver, signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<Hosts.Address>>>, options: Options, request: Request.URLPrepared) -> IO(Report<Reason, SourceError>):
  match options request:
    case Options{priority, preference, duration, +maximum, limits} Request.URLPrepared{Request.Endpoint{transport, +host, port, _, _}, prepared}:
      configuredRoute(~Reason, ~SourceError, resolver, signal, hosts, Options{priority, preference, duration, maximum, limits}, None{}, routedPlan(host, port, prepared, maximum), protocol(security, transport, host))

# Pooled exchanges
# ----------------

def isTLS(transport: Request.Transport) -> Bool:
  match transport:
    case Request.TLS{}: True{}
    case _: False{}

def sameBool(left: Bool, right: Bool) -> Bool:
  match left right:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def originOf(transport: Request.Transport, host: Host.Host, port: U32) -> Origin: Origin{isTLS(transport), Host.serializeHost(host), port}

def sameOrigin(left: Origin, right: Origin) -> Bool:
  match left right:
    case Origin{a, host, port} Origin{b, other, number}: sameBool(a, b) && String.eq(host, other) && U32.is_eq(port, number)

type Place is Data:
  ExpiredIdle{}
  MatchingIdle{}
  OtherIdle{}

def placeOf(origin: Origin, wanted: Origin, expires: F64, now: F64) -> Place:
  Bool.pick(Place, Bool.not(F64.is_lt(now, expires)), ExpiredIdle{}, Bool.pick(Place, sameOrigin(origin, wanted), MatchingIdle{}, OtherIdle{}))

# The oldest live connection to the origin, the expired ones and the rest.
type Taken<-Reason: Data> is Type:
  Taken{remaining: List<&1, Idle<Reason>>, found: Maybe<&1, Idle<Reason>>, expired: List<&1, Idle<Reason>>}

def withFound(-Reason: Data, idle: Idle<Reason>, taken: Taken<Reason>) -> Taken<Reason>:
  match taken:
    case Taken{remaining, None{}, expired}: Taken{remaining, Some{idle}, expired}
    case Taken{remaining, Some{found}, expired}: Taken{idle <> remaining, Some{found}, expired}

def placed(-Reason: Data, place: Place, idle: Idle<Reason>, taken: Taken<Reason>) -> Taken<Reason>:
  match place taken:
    case ExpiredIdle{} Taken{remaining, found, expired}: Taken{remaining, found, idle <> expired}
    case MatchingIdle{} taken: withFound(Reason, idle, taken)
    case OtherIdle{} Taken{remaining, found, expired}: Taken{idle <> remaining, found, expired}

def placeIdle(-Reason: Data, idle: Idle<Reason>, +wanted: Origin, +now: F64, taken: Taken<Reason>) -> Taken<Reason>:
  match idle:
    case Idle{+origin, parked, controller, +expires}: placed(Reason, placeOf(origin, wanted, expires, now), Idle{origin, parked, controller, expires}, taken)

def partition(-Reason: Data, idle: List<&1, Idle<Reason>>, +wanted: Origin, +now: F64, taken: Taken<Reason>) -> Taken<Reason>:
  match idle:
    case Nil{}: taken
    case first <> rest: partition(Reason, rest, wanted, now, placeIdle(Reason, first, wanted, now, taken))

def splitTaken(-Reason: Data, taken: Taken<Reason>) -> List<&1, Idle<Reason>> & (Maybe<&1, Idle<Reason>> & List<&1, Idle<Reason>>):
  match taken:
    case Taken{remaining, found, expired}: (List.reverse(&1, Idle<Reason>, remaining), (found, expired))

def plainReadable(-Reason: Data, pair: Connect.Owner<Reason> & Bool) -> Parked<Reason> & Bool:
  match pair:
    case (connection, ready): (ParkedPlain{connection}, ready)

def secureReadable(-Reason: Data, control: TLS.Writer<Reason>, pair: TLS.Connection<Reason> & Bool) -> Parked<Reason> & Bool:
  match pair:
    case (connection, ready): (ParkedSecure{connection, control}, ready)

# undici validates an idle socket before reuse: pending data or a peer close
# means the server gave up on it, so it is closed instead.
def readableParked(-Reason: Data, parked: Parked<Reason>) -> IO(Parked<Reason> & Bool):
  match parked:
    case ParkedPlain{connection}:
      do IO<Parked<Reason> & Bool>:
        pair : Connect.Owner<Reason> & Bool <- Connect.readable(Reason, connection)
        return plainReadable(Reason, pair)
    case ParkedSecure{connection, control}:
      do IO<Parked<Reason> & Bool>:
        pair : TLS.Connection<Reason> & Bool <- TLS.readable(Reason, connection)
        return secureReadable(Reason, control, pair)

def validIdle(-Reason: Data, +origin: Origin, controller: Abort.AbortController<Reason>, +expires: F64, pair: Parked<Reason> & Bool) -> IO(Maybe<&1, Idle<Reason>>):
  match pair:
    case (parked, False{}): IO.pure(Maybe<&1, Idle<Reason>>, Some{Idle{origin, parked, controller, expires}})
    case (parked, True{}):
      do IO<Maybe<&1, Idle<Reason>>>:
        disposeIdle(Reason, Idle{origin, parked, controller, expires})
        return None{}

def validated(-Reason: Data, found: Maybe<&1, Idle<Reason>>) -> IO(Maybe<&1, Idle<Reason>>):
  match found:
    case None{}: IO.pure(Maybe<&1, Idle<Reason>>, None{})
    case Some{Idle{origin, parked, controller, expires}}:
      do IO<Maybe<&1, Idle<Reason>>>:
        pair : Parked<Reason> & Bool <- readableParked(Reason, parked)
        validIdle(Reason, origin, controller, expires, pair)

def takenIdle(-Reason: Data, pair: Maybe<&1, Idle<Reason>> & List<&1, Idle<Reason>>) -> IO(Maybe<&1, Idle<Reason>>):
  match pair:
    case (found, expired):
      do IO<Maybe<&1, Idle<Reason>>>:
        disposeAllIdle(Reason, expired)
        validated(Reason, found)

def takeIdle(-Reason: Data, pool: Pool<Reason>, +origin: Origin) -> IO(Maybe<&1, Idle<Reason>>):
  match pool:
    case Pool{idle, clock}:
      do IO<Maybe<&1, Idle<Reason>>>:
        +now : F64 <- Clock.now(clock)
        pair : Maybe<&1, Idle<Reason>> & List<&1, Idle<Reason>> <- R.modify(List<&1, Idle<Reason>>, Maybe<&1, Idle<Reason>> & List<&1, Idle<Reason>>, idle, list => splitTaken(Reason, partition(Reason, list, origin, now, Taken{Nil{}, None{}, Nil{}})))
        takenIdle(Reason, pair)

def preparedMethod(request: Request.BufferedRequestPrepared) -> String:
  match request:
    case Request.BufferedRequestPrepared{Request.Head{method, _}, _}: method

def startParked(~Reason: Data, parked: Parked<Reason>, request: Request.BufferedRequestPrepared, maximum: U32, limits: Response.Limits, keep: Keep<Reason>) -> IO(Result<&2, &1, StartError<Reason>, Exchange<Reason>>):
  match parked request:
    case ParkedPlain{connection} Request.BufferedRequestPrepared{Request.Head{method, head}, body}:
      do IO<Result<&2, &1, StartError<Reason>, Exchange<Reason>>>:
        result : Connect.Owner<Reason> & Result<&2, &1, Connect.Error<Reason>, Connect.UploadOwner<Reason>> <- Connect.startUpload(Reason, connection, head, Request.wireBody(body))
        uploading(~Reason, method, maximum, limits, Some{keep}, result)
    case ParkedSecure{connection, control} Request.BufferedRequestPrepared{Request.Head{method, head}, body}:
      uploadTLS(~Reason, method, maximum, limits, Some{keep}, head, Request.wireBody(body), (connection, control))

def reusedReport(-Reason: Data, -SourceError: Data, keep: Keep<Reason>, result: Result<&2, &1, StartError<Reason>, Exchange<Reason>>) -> IO(Report<Reason, SourceError>):
  match result:
    case Done{exchange}: IO.pure(Report<Reason, SourceError>, Reused{Done{exchange}})
    case Fail{error}:
      do IO<Report<Reason, SourceError>>:
        retireKeep(Reason, keep)
        return Reused{Fail{ResolvedExchangeFailure{error}}}

def keepFor(-Reason: Data, pool: Pool<Reason>, origin: Origin, +controller: Abort.AbortController<Reason>, signal: Abort.AbortSignal<Reason>, method: String) -> IO(Keep<Reason>):
  do IO<Keep<Reason>>:
    link : Abort.Link<Reason> <- Abort.link(Reason, signal, controller)
    reference : R.Ref<Maybe<&1, Abort.Link<Reason>>> <- R.new(Maybe<&1, Abort.Link<Reason>>, Some{link})
    return Keep{pool, origin, controller, reference, method}

def reuse(~Reason: Data, ~SourceError: Data, pool: Pool<Reason>, origin: Origin, parked: Parked<Reason>, controller: Abort.AbortController<Reason>, signal: Abort.AbortSignal<Reason>, options: Options, request: Request.URLPrepared) -> IO(Report<Reason, SourceError>):
  match options request:
    case Options{_, _, _, maximum, limits} Request.URLPrepared{_, +prepared}:
      do IO<Report<Reason, SourceError>>:
        +keep : Keep<Reason> <- keepFor(Reason, pool, origin, controller, signal, preparedMethod(prepared))
        result : Result<&2, &1, StartError<Reason>, Exchange<Reason>> <- startParked(~Reason, parked, prepared, maximum, limits, keep)
        reusedReport(Reason, SourceError, keep, result)

def settledReport(-Reason: Data, -SourceError: Data, keep: Keep<Reason>, report: Report<Reason, SourceError>) -> IO(Report<Reason, SourceError>):
  match report:
    case Attempted{resolution, attempts, Done{exchange}}: IO.pure(Report<Reason, SourceError>, Attempted{resolution, attempts, Done{exchange}})
    case other:
      do IO<Report<Reason, SourceError>>:
        retireKeep(Reason, keep)
        return other

def fresh(~Reason: Data, ~SourceError: Data, pool: Pool<Reason>, origin: Origin, security: Security, resolver: Pair.Resolver, signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<Hosts.Address>>>, options: Options, request: Request.URLPrepared) -> IO(Report<Reason, SourceError>):
  match options request:
    case Options{priority, preference, duration, +maximum, limits} Request.URLPrepared{Request.Endpoint{transport, +host, port, _, _}, +prepared}:
      do IO<Report<Reason, SourceError>>:
        +controller : Abort.AbortController<Reason> <- Abort.new(Reason)
        +keep : Keep<Reason> <- keepFor(Reason, pool, origin, controller, signal, preparedMethod(prepared))
        report : Report<Reason, SourceError> <- configuredRoute(~Reason, ~SourceError, resolver, Abort.signal(Reason, controller), hosts, Options{priority, preference, duration, maximum, limits}, Some{keep}, routedPlan(host, port, prepared, maximum), protocol(security, transport, host))
        settledReport(Reason, SourceError, keep, report)

def startFrom(~Reason: Data, ~SourceError: Data, pool: Pool<Reason>, origin: Origin, security: Security, resolver: Pair.Resolver, signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<Hosts.Address>>>, options: Options, request: Request.URLPrepared, idle: Maybe<&1, Idle<Reason>>) -> IO(Report<Reason, SourceError>):
  match idle:
    case None{}: fresh(~Reason, ~SourceError, pool, origin, security, resolver, signal, hosts, options, request)
    case Some{Idle{_, parked, controller, _}}: reuse(~Reason, ~SourceError, pool, origin, parked, controller, signal, options, request)

# undici's Agent: reuse the oldest idle connection to the origin unless it
# expired or the server closed it, otherwise open a new one. Either way the
# connection runs under its own controller; the request's signal is linked
# to it until the response is released, and a completed persistent response
# parks the connection again.
def startPooled(~Reason: Data, ~SourceError: Data, +pool: Pool<Reason>, security: Security, resolver: Pair.Resolver, signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<Hosts.Address>>>, options: Options, +request: Request.URLPrepared) -> IO(Report<Reason, SourceError>):
  match request:
    case Request.URLPrepared{Request.Endpoint{transport, +host, port, _, _}, _}:
      +origin = originOf(transport, host, port)
      do IO<Report<Reason, SourceError>>:
        idle : Maybe<&1, Idle<Reason>> <- takeIdle(Reason, pool, origin)
        startFrom(~Reason, ~SourceError, pool, origin, security, resolver, signal, hosts, options, request, idle)
