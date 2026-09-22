import Base
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/resolver-config.bend as Settings
import ../packages/runtime/src/resolver-config.bend as Configuration
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/dns-resolver.bend as Lookup
import ../packages/runtime/src/dns-resolver.bend as Answer
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/dns-transport.bend as Selector
import ../packages/runtime/src/dns-transport.bend as Exchange
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/resolver-config.bend as Prepare
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/resolver-config.bend as Request
import ../packages/runtime/src/dns-message.bend as Query
import ../packages/runtime/src/dns-message.bend as Id
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ../packages/runtime/src/dns-resolver.bend as SearchIO
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-message.bend as Run
import ./dns-search-response.bend as ResponseTest
import ./dns-lookup-ids.bend as IDs
import ./dns-lookup-random.bend as LookupTest
import ./dns-tcp-query.bend as TCPTest
import ./dns-udp-query.bend as UDPTest

def outcome(result: Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>) -> String:
  match result:
    case Fail{Lookup.Aborted{why}}: "abort:" ++ TCPTest.cause(why)
    case Fail{Lookup.Identifier{Id.SourceFailure{code, _}}}: "entropy:" ++ U32.show(code)
    case Fail{Lookup.Transport{_}}: "transport"
    case other: LookupTest.outcome(other)

def queryOptions(value: Request.Prepared) -> Query.QueryOptions:
  match value:
    case Request.Prepared{_, options}: options

def endpointPort(value: Endpoint.Endpoint) -> U32:
  match value:
    case Endpoint.EndpointV4{_, port}: port
    case Endpoint.EndpointV6{_, port, _}: port

def nextPort(values: List<&2, Plan.Attempt<Endpoint.Endpoint>>) -> U32:
  match values:
    case Plan.Attempt{endpoint, _, _} <> _: endpointPort(endpoint)
    case Nil{}: 0

def report(value: SearchIO.AddressSearchReport<String>) -> IO(Unit):
  match value:
    case SearchIO.AddressSearchReport{Done{selection}, reason}:
      do IO<Unit>:
        IO.print(outcome(Done{selection}))
        IO.print(TCPTest.retained(reason))
    case SearchIO.AddressSearchReport{Fail{Run.Halted{error}}, reason}:
      do IO<Unit>:
        IO.print(outcome(Fail{error}))
        IO.print(TCPTest.retained(reason))
    case SearchIO.AddressSearchReport{Fail{Run.NoAnswer{error}}, reason}:
      do IO<Unit>:
        IO.print("dns:" ++ ResponseTest.error(error))
        IO.print(TCPTest.retained(reason))

def seed(value: U32) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Done{value})

def once(ids: IDs.Source, resolver: Resolver.Resolver, parent: Abort.AbortSignal<String>, kind: U32) -> IO(Unit):
  do IO<Unit>:
    result : SearchIO.AddressSearchReport<String> <- Resolver.lookupWith(~IDs.Source, ~IDs.draw, ~String, ids, resolver, parent, kind, Name.Name{(97 <> Nil{}) <> Nil{}}, 0, False{})
    report(result)

def repeat(enabled: Bool, ids: IDs.Source, resolver: Resolver.Resolver, parent: Abort.AbortSignal<String>, kind: U32) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: once(ids, resolver, parent, kind)

def run(mode: String, +ids: IDs.Source, +kind: U32, +parent: Abort.AbortSignal<String>, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case (owner, Resolver.Resolver{+config, +source}):
      do IO<Unit>:
        once(ids, Resolver.Resolver{config, source}, parent, kind)
        repeat(String.eq(mode, "repeat"), ids, Resolver.Resolver{config, source}, parent, kind)
        next : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- Selector.chooseServerSource(Plan.Attempt<Endpoint.Endpoint>, source)
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
  rotate = Bool.pick(List<&2, Options.Feature>, String.eq(mode, "rotate") || String.eq(mode, "repeat"), Options.Rotate{} <> Nil{}, Nil{})
  edns = Bool.pick(List<&2, Options.Feature>, String.eq(mode, "edns"), Options.Edns{} <> Nil{}, Nil{})
  List.append(&2, Options.Feature, tcp, List.append(&2, Options.Feature, rotate, edns))

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> +family <> first <> second <> kind <> Nil{}:
      ready(mode, Scalar.decimal(kind, 0), Settings.prepareConfiguration(Endpoint.Endpoint, UDPTest.destination(Scalar.decimal(family, 0), Scalar.decimal(first, 0)) <> UDPTest.destination(Scalar.decimal(family, 0), Scalar.decimal(second, 0)) <> Nil{}, Bool.pick(U32, String.eq(mode, "deadline"), 1200, 7000), Bool.pick(U32, String.eq(mode, "size"), 0, 7), Configuration.prepareSearch(Options.OptionsOptions{1, 1, Bool.pick(U32, String.eq(mode, "zero-attempts"), 0, 1), features(mode)}, "x" <> "y" <> Nil{})))
    case _: IO.die(Unit, 1, "expected mode family first second kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
