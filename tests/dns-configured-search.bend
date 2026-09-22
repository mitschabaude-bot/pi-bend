import Base
import ../packages/runtime/src/resolver-config.bend as Configuration
import ../packages/runtime/src/resolver-config.bend as ResolverOptions
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/dns-transport.bend as Selector
import ../packages/runtime/src/dns-transport.bend as Servers
import ./dns-lookup-options.bend as Options
import ../packages/runtime/src/dns-resolver.bend as Network
import ../packages/runtime/src/dns-resolver.bend as Lookup
import ../packages/runtime/src/dns-resolver.bend as Answer
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-message.bend as Presentation
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-search.bend as SearchTest
import ./dns-search-response.bend as ResponseTest
import ./dns-lookup-ids.bend as IDs
import ./dns-tcp-query.bend as QueryTest
import ./dns-tcp-connection.bend as Test

def result(value: Result<&2, &2, Run.SearchRunError<Lookup.AddressLookupError<String>>, Answer.Selection>) -> IO(Unit):
  match value:
    case Fail{Run.NoAnswer{error}}: IO.print("dns:" ++ ResponseTest.error(error))
    case Fail{Run.Halted{error}}: IDs.sourceReport(Lookup.Report{Fail{error}, None{}})
    case Done{selection}: IDs.sourceReport(Lookup.Report{Done{selection}, None{}})

def report(value: Network.AddressSearchReport<String>) -> IO(Unit):
  match value:
    case Network.AddressSearchReport{answer, reason}:
      do IO<Unit>:
        result(answer)
        IO.print(QueryTest.retained(reason))

def domains(text: String) -> List<&2, String>:
  match text:
    case SNil{}: Nil{}
    case other: Split.split(other, '|')

def lookup(environment: IDs.Source, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<String>, kind: U32, maximum: U32, configuration: Result<&2, &2, List<&2, ResolverOptions.Diagnostic>, Configuration.Configuration>, name: Name.Name, dots: U32, absolute: Bool) -> IO(Network.AddressSearchReport<String>):
  match configuration:
    case Fail{_}: IO.die(Network.AddressSearchReport<String>, 2, "invalid resolver options")
    case Done{value}: Network.searchConfiguredWith(~IDs.Source, ~IDs.draw, ~String, environment, Selector.Fixed{Servers.Server{address, port} <> Nil{}}, milliseconds, parent, kind, maximum, value, name, dots, absolute)

def args(values: List<String>) -> IO(Unit):
  match values:
    case options <> +mode <> family <> port <> kind <> name <> dots <> absolute <> ndots <> suffixes <> extra <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        QueryTest.prepare(String.eq(mode, "pre"), False{}, parent)
        answer : Network.AddressSearchReport<String> <- lookup(IDs.Source{mode, count, parent}, Test.endpoint(family), Scalar.decimal(port, 0), Bool.pick(U32, String.eq(mode, "deadline"), 1000, 5000), Abort.signal(String, parent), Scalar.decimal(kind, 0), Bool.pick(U32, String.eq(mode, "zero"), 0, 7), Configuration.prepareStrictSearch(Config.words("ndots:" ++ ndots ++ Bool.pick(String, String.eq(options, "edns"), " edns0 trust-ad ", " ") ++ extra, Config.Words{"", Nil{}}), domains(suffixes)), SearchTest.parsed(Presentation.parsePresentation(name)), Scalar.decimal(dots, 0), String.eq(absolute, "1"))
        report(answer)
        draws : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)
    case _: IO.die(Unit, 1, "expected options mode family port kind name dots absolute ndots domains extra")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
