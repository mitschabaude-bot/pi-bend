import Base
import ../packages/runtime/src/dns-hosts-resolver.bend as HostResolver
import ../packages/runtime/src/hosts-resolve.bend as HostResolve
import ../packages/runtime/src/hosts-file.bend as HostFile
import ../packages/runtime/src/hosts.bend as Hosts
import ./hosts-file.bend as HostShow
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/resolver-configuration.bend as Settings
import ../packages/runtime/src/resolver-search.bend as Configuration
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/dns-address-lookup.bend as Lookup
import ../packages/runtime/src/dns-address-answer.bend as Answer
import ../packages/runtime/src/dns-name.bend as Name
import ../packages/runtime/src/dns-server-source.bend as Selector
import ../packages/runtime/src/dns-exchange-source.bend as Exchange
import ../packages/runtime/src/dns-udp-plan.bend as Plan
import ../packages/runtime/src/resolver-transport.bend as Prepare
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/resolver-request.bend as Request
import ../packages/runtime/src/dns-query.bend as Query
import ../packages/runtime/src/dns-id.bend as Id
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ../packages/runtime/src/dns-address-search.bend as SearchIO
import ../packages/runtime/src/dns-search.bend as Search
import ../packages/runtime/src/dns-search-run.bend as Run
import ./dns-search-response.bend as ResponseTest
import ./dns-lookup-ids.bend as IDs
import ./dns-lookup-random.bend as LookupTest
import ./dns-tcp-query.bend as TCPTest
import ./dns-udp-query.bend as UDPTest

def outcome(result: Result<&2, &2, Lookup.Error<String>, Answer.Selection>) -> String:
  match result:
    case Fail{Lookup.Aborted{why}}: "abort:" ++ TCPTest.cause(why)
    case Fail{Lookup.Identifier{Id.SourceFailure{code, _}}}: "entropy:" ++ U32.show(code)
    case Fail{Lookup.Transport{_}}: "transport"
    case other: LookupTest.outcome(other)

def queryOptions(value: Request.Prepared) -> Query.Options:
  match value:
    case Request.Prepared{_, options}: options

def endpointPort(value: Endpoint.Endpoint) -> U32:
  match value:
    case Endpoint.V4{_, port}: port
    case Endpoint.V6{_, port, _}: port

def nextPort(values: List<&2, Plan.Attempt<Endpoint.Endpoint>>) -> U32:
  match values:
    case Plan.Attempt{endpoint, _, _} <> _: endpointPort(endpoint)
    case Nil{}: 0

def report(value: SearchIO.Report<String>) -> IO(Unit):
  match value:
    case SearchIO.Report{Done{selection}, reason}:
      do IO<Unit>:
        IO.print(outcome(Done{selection}))
        IO.print(TCPTest.retained(reason))
    case SearchIO.Report{Fail{Run.Halted{error}}, reason}:
      do IO<Unit>:
        IO.print(outcome(Fail{error}))
        IO.print(TCPTest.retained(reason))
    case SearchIO.Report{Fail{Run.NoAnswer{error}}, reason}:
      do IO<Unit>:
        IO.print("dns:" ++ ResponseTest.error(error))
        IO.print(TCPTest.retained(reason))

def seed(value: U32) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Done{value})

def chosenFamily(kind: U32) -> HostResolver.Family:
  match kind:
    case 1: HostResolver.IPv4{}
    case _: HostResolver.IPv6{}

def textName(mode: String) -> String:
  match mode:
    case "absolute": "a."
    case "dotted": "a.z"
    case "invalid-name": "a..x"
    case "local-invalid-name": "a..x"
    case _: "a"

def database(mode: String, kind: U32) -> Result<&2, &2, HostFile.Failure, List<&2, Hosts.Entry<HostFile.Address>>>:
  match mode:
    case "local": HostFile.parse("127.0.0.9 a\n::9 a")
    case "local-invalid-name": HostFile.parse("127.0.0.9 a..x\n::9 a..x")
    case "source-error": HostFile.parse("127.0.0.9 a\ninvalid later")
    case "wrong-family": HostFile.parse(Bool.pick(String, U32.is_eq(kind, 1), "::9 a", "127.0.0.9 a"))
    case _: Done{Nil{}}

def hostReport(value: HostResolve.Report<HostFile.Failure, HostResolver.DNS<String>>) -> IO(Unit):
  match value:
    case HostResolve.FromHosts{first, rest}:
      do IO<Unit>:
        IO.print("local:" ++ HostShow.entries(first <> rest))
        IO.print("none")
    case HostResolve.FailedSource{HostFile.Failure{line, _}}:
      do IO<Unit>:
        IO.print("source:" ++ U32.show(U32.from_nat(line)))
        IO.print("none")
    case HostResolve.FromNetwork{HostResolver.InvalidName{_}}:
      do IO<Unit>:
        IO.print("invalid-name")
        IO.print("none")
    case HostResolve.FromNetwork{HostResolver.Completed{value}}: report(value)

def once(+mode: String, ids: IDs.Source, resolver: Resolver.Resolver, parent: Abort.AbortSignal<String>, +kind: U32) -> IO(Unit):
  do IO<Unit>:
    result : HostResolve.Report<HostFile.Failure, HostResolver.DNS<String>> <- HostResolver.lookupWith(~IDs.Source, ~IDs.draw, ~String, ~HostFile.Failure, ids, resolver, parent, chosenFamily(kind), textName(mode), database(mode, kind))
    hostReport(result)

def repeat(enabled: Bool, ids: IDs.Source, resolver: Resolver.Resolver, parent: Abort.AbortSignal<String>, kind: U32) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: once("repeat", ids, resolver, parent, kind)

def run(+mode: String, +ids: IDs.Source, +kind: U32, +parent: Abort.AbortSignal<String>, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case (owner, Resolver.Resolver{+config, +source}):
      do IO<Unit>:
        once(mode, ids, Resolver.Resolver{config, source}, parent, kind)
        repeat(String.eq(mode, "repeat"), ids, Resolver.Resolver{config, source}, parent, kind)
        next : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- Selector.choose(Plan.Attempt<Endpoint.Endpoint>, source)
        IO.print("next:" ++ U32.show(nextPort(next)))
        Resolver.close(owner)

def created(mode: String, ids: IDs.Source, kind: U32, parent: Abort.AbortSignal<String>, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "owner initialization failed")
    case Done{owner}: run(mode, ids, kind, parent, Resolver.borrow(owner))

def ready(+mode: String, kind: U32, value: Result<&2, &2, Plan.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "invalid test config")
    case Done{config}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        TCPTest.prepare(String.eq(mode, "pre"), False{}, parent)
        owner : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~seed, 0, config)
        created(mode, IDs.Source{mode, count, parent}, kind, Abort.signal(String, parent), owner)
        draws : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)

def features(+mode: String) -> List<&2, Options.Feature>:
  tcp = Bool.pick(List<&2, Options.Feature>, String.eq(mode, "forced") || String.eq(mode, "forced-eof"), Options.UseTcp{} <> Nil{}, Nil{})
  rotate = Bool.pick(List<&2, Options.Feature>, String.eq(mode, "rotate") || String.eq(mode, "repeat") || String.eq(mode, "local") || String.eq(mode, "local-invalid-name") || String.eq(mode, "source-error") || String.eq(mode, "invalid-name"), Options.Rotate{} <> Nil{}, Nil{})
  edns = Bool.pick(List<&2, Options.Feature>, String.eq(mode, "edns"), Options.Edns{} <> Nil{}, Nil{})
  List.append(&2, Options.Feature, tcp, List.append(&2, Options.Feature, rotate, edns))

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> +family <> first <> second <> kind <> Nil{}:
      ready(mode, Scalar.decimal(kind, 0), Settings.prepare(Endpoint.Endpoint, UDPTest.destination(Scalar.decimal(family, 0), Scalar.decimal(first, 0)) <> UDPTest.destination(Scalar.decimal(family, 0), Scalar.decimal(second, 0)) <> Nil{}, Bool.pick(U32, String.eq(mode, "deadline"), 1200, 7000), Bool.pick(U32, String.eq(mode, "size"), 0, 7), Configuration.prepare(Options.Options{1, 1, Bool.pick(U32, String.eq(mode, "zero-attempts"), 0, 1), features(mode)}, "x" <> "y" <> Nil{})))
    case _: IO.die(Unit, 1, "expected mode family first second kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
