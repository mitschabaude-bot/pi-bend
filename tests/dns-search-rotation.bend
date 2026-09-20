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

import ./dns-server-rotation.bend as RotationTest
import ../packages/runtime/src/dns-server-source.bend as Selector
import ../packages/runtime/src/dns-tcp-servers.bend as Servers

def serverPorts(values: List<&2, Servers.Server>, reversed: List<&2, U32>) -> List<&2, U32>:
  match values:
    case Nil{}: List.reverse(&2, U32, reversed)
    case Servers.Server{_, port} <> rest: serverPorts(rest, port <> reversed)

def run(+mode: String, +parent: Abort.AbortController<String>, counter: Ref.Ref<U32>, kind: U32, cursor: Search.Cursor, pair: Selector.Owner<Servers.Server> & Selector.Source<Servers.Server>) -> IO(Unit):
  match pair:
    case (owner, +source):
      do IO<Unit>:
        answer : Network.Report<String> <- Network.searchSourceWith(~IDs.Source, ~IDs.draw, ~String, IDs.Source{mode, counter, parent}, source, Bool.pick(U32, String.eq(mode, "deadline"), 1000, 5000), Abort.signal(String, parent), kind, Bool.pick(U32, String.eq(mode, "zero"), 0, 7), cursor)
        SearchOutput.report(answer)
        next : List<&2, Servers.Server> <- Selector.choose(Servers.Server, source)
        IO.print("next:" ++ RotationTest.csv(serverPorts(next, Nil{}), ""))
        Selector.close(Servers.Server, owner)

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> family <> port <> kind <> name <> dots <> absolute <> ndots <> domains <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        QueryTest.prepare(String.eq(mode, "pre"), False{}, parent)
        owner : Selector.Owner<Servers.Server> <- Selector.create(Servers.Server, ServersTest.serverInput(family, port))
        run(mode, parent, count, Scalar.decimal(kind, 0), Search.start(SearchTest.parsed(Presentation.parse(name)), Scalar.decimal(dots, 0), String.eq(absolute, "1"), SearchTest.domainInput(domains), Search.Policy{Scalar.decimal(ndots, 0), True{}, True{}, False{}}), Selector.borrow(Servers.Server, Bool.not(String.eq(mode, "disabled")), owner))
        draws : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)
    case _: IO.die(Unit, 1, "expected mode family port kind name dots absolute ndots domains")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
