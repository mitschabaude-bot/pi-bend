import Base
import ../packages/runtime/src/connection-driver.bend as Dispatch
import ../packages/runtime/src/http-exchange.bend as ConnectHTTP
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-message.bend as Guard
import ../packages/runtime/src/http-message.bend as Request
import ../packages/runtime/src/http-message.bend as Body
import ../packages/runtime/src/http-exchange.bend as Exchange
import ../packages/runtime/src/socket.bend as SocketIO
import ../packages/runtime/src/http-message.bend as Headers
import ../packages/runtime/src/http-message.bend as Header
import ../packages/runtime/src/url-record.bend as URL
import ../packages/runtime/src/url-scheme.bend as Scheme
import ./http-connect-exchange.bend as Read
import ../packages/runtime/src/connection-driver.bend as Driver
import ../packages/runtime/src/connection-driver.bend as Progress
import ../packages/runtime/src/connection-driver.bend as Order
import ../packages/runtime/src/http-exchange.bend as Route
import ../packages/runtime/src/hosts.bend as HostsResolve
import ../packages/runtime/src/hosts.bend as File
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/url-host.bend as Host
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/resolver-config.bend as Settings
import ../packages/runtime/src/resolver-config.bend as Search
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/dns-resolver.bend as Pair
import ../packages/runtime/src/dns-message.bend as Id
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./connection-driver.bend as Show

def draw(mode: U32) -> IO(Result<&2, &2, Id.IdError, U32>):
  match mode:
    case 4: Id.random(Unit{})
    case _: IO.die(Result<&2, &2, Id.IdError, U32>, 1, "unexpected DNS")

def preference(mode: U32, family: Bool) -> Order.Preference:
  match mode family:
    case 4 False{}: Order.IPv4First{}
    case _ _: Order.IPv6First{}

def host(mode: U32, family: Bool) -> Host.Host:
  match mode family:
    case 0 False{}: Host.IPv4{IPv4.Address{2130706433}}
    case 0 True{}: Host.IPv6{IPv6.Address{0, 0, 0, 1}}
    case _ _: Host.Domain{"unit"}

def database(mode: U32, family: Bool) -> Result<&2, &2, File.Failure, List<&2, Hosts.Entry<File.Address>>>:
  match mode family:
    case 0 _: File.parse("invalid file")
    case 2 _: File.parse("invalid file")
    case 4 _: File.parse("")
    case _ False{}: File.parse("127.0.0.1 unit\n::1 unit\n127.0.0.1 unit")
    case _ True{}: File.parse("::1 unit\n127.0.0.1 unit\n::1 unit")

def resolution(value: ConnectHTTP.Resolution(String, File.Failure)) -> IO(Unit):
  match value:
    case Done{Route.NumericAddress{_}}: IO.print("numeric")
    case Done{Route.Named{HostsResolve.FromHosts{_, _}}}: IO.print("hosts")
    case Done{Route.Named{HostsResolve.FailedSource{_}}}: IO.print("source-error")
    case Fail{Route.InvalidHost{}}: IO.print("invalid-host")
    case Done{Route.Named{HostsResolve.FromNetwork{_}}}: IO.print("dns")
    case _: IO.die(Unit, 1, "unexpected resolution")

def consumed(flow: U32, controller: Abort.AbortController<String>, outcome: Result<&2, &1, HTTP.ResolvedExchangeError<String>, Exchange.Exchange<String>>) -> IO(Unit):
  match outcome:
    case Fail{HTTP.ResolvedExchangeConnectionFailure{error}}: IO.print("connection:" ++ Show.finalName(error))
    case Fail{HTTP.ResolvedExchangeExchangeFailure{Exchange.SocketFailure{SocketIO.SocketAborted{Abort.Supplied{reason}}}}}: IO.print("handoff:" ++ reason)
    case Fail{_}: IO.die(Unit, 1, "unexpected exchange start error")
    case Done{exchange}:
      do IO<Unit>:
        Read.success(Bool.pick(String, U32.is_eq(flow, 1), "read", "success"), controller, exchange)
        IO.print("response:ok")

def checked(flow: U32, controller: Abort.AbortController<String>, value: HTTP.Report<String, File.Failure>) -> IO(Unit):
  match value:
    case HTTP.Rejected{Guard.TLSRequired{}}: IO.print("guard:tls")
    case HTTP.Rejected{Guard.InvalidReadSize{}}: IO.print("guard:zero")
    case HTTP.Unresolved{original}:
      do IO<Unit>:
        resolution(original)
        IO.print("unresolved")
    case HTTP.Attempted{original, entries, outcome}:
      do IO<Unit>:
        resolution(original)
        Show.history(entries)
        consumed(flow, controller, outcome)

def prepared(value: Result<&2, &2, Request.URLRequestError, Request.URLPrepared>) -> IO(Request.URLPrepared):
  match value:
    case Done{encoded}: IO.pure(Request.URLPrepared, encoded)
    case Fail{_}: IO.die(Request.URLPrepared, 1, "URL request preparation")

def options(+mode: U32, family: Bool) -> HTTP.Options:
  HTTP.Options{Pair.IPv4First{}, preference(mode, family), 30, Bool.pick(U32, U32.is_eq(mode, 5), 0, 7), Read.limits()}

def preabort(enabled: Bool, controller: Abort.AbortController<String>) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        return Unit{}

def run(+mode: U32, +family: Bool, port: U32, +flow: U32, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case (owner, resolver):
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        encoded : Request.URLPrepared <- prepared(Request.prepareURL(URL.URL{Bool.pick(Scheme.Scheme, U32.is_eq(mode, 3), Scheme.Https{}, Scheme.Http{}), "", "", Some{host(mode, family)}, Some{port}, URL.Hierarchical{"resolved" <> Nil{}}, Some{"x=1"}, None{}}, "POST", Headers.appendField(Headers.new(), Header.Header{"host", "wrong.invalid"}), Body.Text{"hello"}))
        preabort(U32.is_eq(flow, 2), parent)
        value : HTTP.Report<String, File.Failure> <- HTTP.startWith(~U32, ~draw, ~String, ~File.Failure, mode, resolver, Abort.signal(String, parent), database(mode, family), options(mode, family), encoded)
        checked(flow, parent, value)
        Resolver.close(owner)
        Abort.dispose(String, parent)

def seed(value: U32) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Done{value})

def created(mode: U32, family: Bool, port: U32, flow: U32, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "resolver initialization")
    case Done{owner}: run(mode, family, port, flow, Resolver.borrow(owner))

def configuredResult(mode: U32, family: Bool, port: U32, flow: U32, result: Result<&2, &2, Plan.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "configuration")
    case Done{config}:
      do IO<Unit>:
        owner : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~seed, 0, config)
        created(mode, family, port, flow, owner)

def configured(mode: U32, family: Bool, port: U32, dnsPort: U32, flow: U32) -> IO(Unit):
  configuredResult(mode, family, port, flow, Settings.prepareConfiguration(Endpoint.Endpoint, Endpoint.EndpointV4{IPv4.Address{2130706433}, dnsPort} <> Nil{}, 1000, 512, Search.prepareSearch(Options.OptionsOptions{1, 1, 1, Nil{}}, Nil{})))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> family <> port <> dnsPort <> flow <> Nil{}: configured(Scalar.decimal(mode, 0), String.eq(family, "6"), Scalar.decimal(port, 0), Scalar.decimal(dnsPort, 0), Scalar.decimal(flow, 0))
    case _: IO.die(Unit, 1, "expected mode family port dns-port flow")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
