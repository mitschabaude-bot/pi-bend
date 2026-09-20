import Base
import ../packages/runtime/src/dns-address-search.bend as Network
import ../packages/runtime/src/dns-address-lookup.bend as Lookup
import ../packages/runtime/src/dns-address-answer.bend as Answer
import ../packages/runtime/src/dns-search-run.bend as Run
import ../packages/runtime/src/dns-search.bend as Search
import ../packages/runtime/src/dns-presentation.bend as Presentation
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-search.bend as SearchTest
import ./dns-search-response.bend as ResponseTest
import ./dns-lookup-ids.bend as IDs
import ./dns-tcp-query.bend as QueryTest
import ./dns-tcp-servers.bend as ServersTest
import ./dns-address-search.bend as SearchOutput

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> family <> port <> kind <> name <> dots <> absolute <> ndots <> domains <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        QueryTest.prepare(String.eq(mode, "pre"), False{}, parent)
        answer : Network.Report<String> <- Network.searchServersWith(~IDs.Source, ~IDs.draw, ~String, IDs.Source{mode, count, parent}, ServersTest.serverInput(family, port), Bool.pick(U32, String.eq(mode, "deadline"), 1000, 5000), Abort.signal(String, parent), Scalar.decimal(kind, 0), Bool.pick(U32, String.eq(mode, "zero"), 0, 7), Search.start(SearchTest.parsed(Presentation.parse(name)), Scalar.decimal(dots, 0), String.eq(absolute, "1"), SearchTest.domainInput(domains), Search.Policy{Scalar.decimal(ndots, 0), True{}, True{}, False{}}))
        SearchOutput.report(answer)
        draws : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)
    case _: IO.die(Unit, 1, "expected mode family port kind name dots absolute ndots domains")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
