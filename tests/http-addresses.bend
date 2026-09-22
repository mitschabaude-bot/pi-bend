import Base
import ../packages/runtime/src/http-exchange.bend as Addresses
import ../packages/runtime/src/connection-driver.bend as Candidates
import ../packages/runtime/src/http-exchange.bend as HTTP
import ../packages/runtime/src/http-exchange.bend as Route
import ../packages/runtime/src/url-host.bend as URLHost
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/dns-resolver.bend as HostResolver
import ../packages/runtime/src/hosts.bend as HostResolve
import ../packages/runtime/src/hosts.bend as HostFile
import ../packages/runtime/src/hosts.bend as Hosts
import ./hosts-file.bend as HostShow
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/resolver-config.bend as Settings
import ../packages/runtime/src/resolver-config.bend as Configuration
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/dns-resolver.bend as SearchIO
import ../packages/runtime/src/dns-resolver.bend as Pair
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-resolver.bend as Lookup
import ../packages/runtime/src/dns-resolver.bend as Answer
import ../packages/runtime/src/dns-transport.bend as Exchange
import ../packages/runtime/src/dns-transport.bend as Source
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/dns-message.bend as Id
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-udp-query.bend as UDPTest
import ./dns-owned-search.bend as Owned
import ./dns-address-pair.bend as PairTest
import ./dns-search-response.bend as ResponseTest

type Environment is Data:
  Environment{mode: String, count: Ref.Ref<U32>}

def identifier(fail: Bool, index: U32) -> Result<&2, &2, Id.IdError, U32>:
  match fail:
    case True{}: Fail{Id.SourceFailure{11, "entropy failed"}}
    case False{}: Done{index}

def draw(environment: Environment) -> IO(Result<&2, &2, Id.IdError, U32>):
  match environment:
    case Environment{mode, count}:
      do IO<Result<&2, &2, Id.IdError, U32>>:
        +index : U32 <- Ref.modify(U32, U32, count, +value => ((value + 1 : U32), value))
        return identifier(String.eq(mode, "error-second-candidate") && U32.is_eq(index, 2), index)

def reports(value: Pair.PairResultReports<Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>>) -> IO(Unit):
  match value:
    case Pair.PairResultReports{Pair.Classified{a, _}, Pair.Classified{b, _}}:
      do IO<Unit>:
        IO.print("4:" ++ Owned.outcome(a))
        IO.print("6:" ++ Owned.outcome(b))

def result(value: Result<&2, &2, Run.SearchRunError<SearchIO.Failure<String>>, Pair.PairResultReports<Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>>>) -> IO(Unit):
  match value:
    case Done{pair}:
      do IO<Unit>:
        IO.print("answer")
        reports(pair)
    case Fail{Run.Halted{SearchIO.QueryFailed{pair}}}:
      do IO<Unit>:
        IO.print("halt")
        reports(pair)
    case Fail{Run.Halted{SearchIO.SetupFailed{error}}}: IO.print("setup:" ++ PairTest.failed(error))
    case Fail{Run.NoAnswer{error}}: IO.print("dns:" ++ ResponseTest.error(error))

def report(value: SearchIO.PairSearchReport<String>) -> IO(Unit):
  match value:
    case SearchIO.PairSearchReport{value, reason}:
      do IO<Unit>:
        result(value)
        IO.print("deadline:" ++ PairTest.retained(reason))

def cursor(+mode: String) -> Search.SearchCursor:
  Search.start(Name.Name{(97 <> Nil{}) <> Nil{}}, 0, String.eq(mode, "absolute"), Name.Name{(120 <> Nil{}) <> Nil{}} <> Name.Name{(121 <> Nil{}) <> Nil{}} <> Nil{}, Search.Policy{1, True{}, True{}, False{}})

def textName(+mode: String) -> String:
  Bool.pick(String, String.eq(mode, "absolute"), "a.", Bool.pick(String, String.eq(mode, "invalid-name") || String.eq(mode, "local-invalid-name"), "a..x", "a"))

def database(+mode: String) -> Result<&2, &2, HostFile.Failure, List<&2, Hosts.Entry<HostFile.Address>>>:
  HostFile.parse(Bool.pick(String, String.eq(mode, "local"), "127.0.0.9 a\n::9 a\n127.0.0.9 a", Bool.pick(String, String.eq(mode, "local-invalid-name"), "::9 a..x", Bool.pick(String, String.eq(mode, "local-v4"), "127.0.0.9 a", Bool.pick(String, String.eq(mode, "local-v6"), "::9 a", Bool.pick(String, String.eq(mode, "source-error") || String.eq(mode, "numeric4") || String.eq(mode, "numeric6") || String.eq(mode, "numeric-mapped") || String.eq(mode, "empty-host") || String.eq(mode, "empty-domain") || String.eq(mode, "opaque-host"), "127.0.0.9 a\ninvalid later", ""))))))

def hostReport(value: HostResolve.Report<HostFile.Failure, HostResolver.PairHostsResolverDNS<String>>) -> IO(Unit):
  match value:
    case HostResolve.FromHosts{first, rest}: IO.print("local:" ++ HostShow.entries(first <> rest))
    case HostResolve.FailedSource{HostFile.Failure{line, _}}: IO.print("source:" ++ U32.show(U32.from_nat(line)))
    case HostResolve.FromNetwork{HostResolver.PairHostsResolverInvalidName{_}}: IO.print("invalid-name")
    case HostResolve.FromNetwork{HostResolver.PairHostsResolverCompleted{value}}: report(value)

def host(+mode: String) -> URLHost.Host:
  Bool.pick(URLHost.Host, String.eq(mode, "numeric4"), URLHost.IPv4{IPv4.Address{2130706433}}, Bool.pick(URLHost.Host, String.eq(mode, "numeric6"), URLHost.IPv6{IPv6.Address{0, 0, 0, 1}}, Bool.pick(URLHost.Host, String.eq(mode, "numeric-mapped"), URLHost.IPv6{IPv6.Address{0, 0, 65535, 2130706433}}, Bool.pick(URLHost.Host, String.eq(mode, "empty-host"), URLHost.Empty{}, Bool.pick(URLHost.Host, String.eq(mode, "empty-domain"), URLHost.Domain{""}, Bool.pick(URLHost.Host, String.eq(mode, "opaque-host"), URLHost.Opaque{"a"}, URLHost.Domain{textName(mode)}))))))

def routed(value: Result<&2, &2, Route.HostRouteError, Route.HostRouteResolution<HostResolve.Report<HostFile.Failure, HostResolver.PairHostsResolverDNS<String>>>>) -> IO(Unit):
  match value:
    case Fail{Route.InvalidHost{}}: IO.print("invalid-http-host")
    case Done{Route.NumericAddress{Connect.V4{IPv4.Address{address}}}}: IO.print("numeric4:" ++ U32.show(address))
    case Done{Route.NumericAddress{Connect.V6{IPv6.Address{a, b, c, d}, scope}}}: IO.print("numeric6:" ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ ":" ++ U32.show(scope))
    case Done{Route.Named{report}}: hostReport(report)

def showAddress(address: Connect.Address) -> String:
  match address:
    case Connect.V4{IPv4.Address{value}}: "4," ++ U32.show(value) ++ ";"
    case Connect.V6{IPv6.Address{a, b, c, d}, scope}: "6," ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ "," ++ U32.show(scope) ++ ";"

def showAddresses(addresses: List<&2, Connect.Address>) -> String:
  match addresses:
    case Nil{}: ""
    case first <> rest: showAddress(first) ++ showAddresses(rest)

def candidates(value: Candidates.Candidates) -> IO(Unit):
  match value:
    case Candidates.Ordered{first, rest}: IO.print("ordered:" ++ showAddresses(first <> rest))
    case Candidates.Paired{ipv4, ipv6}: IO.print("paired:" ++ showAddresses(ipv4) ++ "/" ++ showAddresses(ipv6))

def projected(value: Candidates.Plan<Result<&2, &2, Route.HostRouteError, Route.HostRouteResolution<HostResolve.Report<HostFile.Failure, HostResolver.PairHostsResolverDNS<String>>>>>) -> IO(Unit):
  match value:
    case Candidates.NoAddresses{original}:
      do IO<Unit>:
        routed(original)
        IO.print("no-addresses")
    case Candidates.Addresses{original, values}:
      do IO<Unit>:
        routed(original)
        candidates(values)

def once(+mode: String, count: Ref.Ref<U32>, resolver: Resolver.Resolver, parent: Abort.AbortSignal<String>, priority: Pair.Priority) -> IO(Unit):
  do IO<Unit>:
    value : Result<&2, &2, Route.HostRouteError, Route.HostRouteResolution<HostResolve.Report<HostFile.Failure, HostResolver.PairHostsResolverDNS<String>>>> <- HTTP.resolveWithHostResolver(~Environment, ~draw, ~String, ~HostFile.Failure, Environment{mode, count}, resolver, parent, priority, host(mode), database(mode))
    projected(Addresses.prepare(String, HostFile.Failure, value))

def repeat(enabled: Bool, mode: String, count: Ref.Ref<U32>, resolver: Resolver.Resolver, parent: Abort.AbortSignal<String>, priority: Pair.Priority) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: once(mode, count, resolver, parent, priority)

def run(+mode: String, +priority: Pair.Priority, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case (owner, Resolver.Resolver{+config, +source}):
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        once(mode, count, Resolver.Resolver{config, source}, Abort.signal(String, parent), priority)
        repeat(String.eq(mode, "repeat"), mode, count, Resolver.Resolver{config, source}, Abort.signal(String, parent), priority)
        total : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(total))
        next : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- Source.chooseServerSource(Plan.Attempt<Endpoint.Endpoint>, source)
        IO.print("next:" ++ U32.show(Owned.nextPort(next)))
        Resolver.close(owner)
        Abort.dispose(String, parent)

def seed(value: U32) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Done{value})

def created(mode: String, priority: Pair.Priority, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "owner initialization failed")
    case Done{owner}: run(mode, priority, Resolver.borrow(owner))

def prepared(mode: String, priority: Pair.Priority, value: Result<&2, &2, Plan.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "invalid fixture configuration")
    case Done{config}:
      do IO<Unit>:
        owner : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~seed, 0, config)
        created(mode, priority, owner)

def features(+mode: String) -> List<&2, Options.Feature>:
  Options.Rotate{} <> Bool.pick(List<&2, Options.Feature>, String.eq(mode, "forced") || String.eq(mode, "priority"), Options.UseTcp{} <> Nil{}, Bool.pick(List<&2, Options.Feature>, String.eq(mode, "edns"), Options.Edns{} <> Nil{}, Nil{}))

def configured(+mode: String, priority: Pair.Priority, servers: List<&2, Endpoint.Endpoint>) -> IO(Unit):
  prepared(mode, priority, Settings.prepareConfiguration(Endpoint.Endpoint, servers, Bool.pick(U32, String.eq(mode, "deadline"), 150, 5000), Bool.pick(U32, String.eq(mode, "zero"), 0, 7), Configuration.prepareSearch(Options.OptionsOptions{1, 1, 1, features(mode)}, "x" <> "y" <> Nil{})))

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> order <> +ipFamily <> first <> second <> Nil{}: configured(mode, Bool.pick(Pair.Priority, String.eq(order, "4"), Pair.IPv4First{}, Pair.IPv6First{}), UDPTest.destination(Scalar.decimal(ipFamily, 0), Scalar.decimal(first, 0)) <> UDPTest.destination(Scalar.decimal(ipFamily, 0), Scalar.decimal(second, 0)) <> Nil{})
    case _: IO.die(Unit, 1, "expected mode priority family first-port second-port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
