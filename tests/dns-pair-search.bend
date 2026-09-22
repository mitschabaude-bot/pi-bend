import Base
import ../packages/runtime/src/dns-resolver.bend as SearchIO
import ../packages/runtime/src/dns-resolver.bend as Pair
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-resolver.bend as Lookup
import ../packages/runtime/src/dns-resolver.bend as Answer
import ../packages/runtime/src/dns-transport.bend as Exchange
import ../packages/runtime/src/dns-transport.bend as Source
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
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

def run(+mode: String, priority: Pair.Priority, pair: Source.Owner<Plan.Attempt<Endpoint.Endpoint>> & Source.ServerSourceSource<Plan.Attempt<Endpoint.Endpoint>>) -> IO(Unit):
  match pair:
    case (owner, +source):
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        value : SearchIO.PairSearchReport<String> <- SearchIO.searchWithPairSearch(~Environment, ~draw, ~String, Environment{mode, count}, Exchange.Configured{source, Options.OptionsOptions{1, 1, 1, Bool.pick(List<&2, Options.Feature>, String.eq(mode, "forced") || String.eq(mode, "priority"), Options.UseTcp{} <> Nil{}, Nil{})}}, Bool.pick(U32, String.eq(mode, "deadline"), 150, 5000), Abort.signal(String, parent), PairTest.queryOptions(mode), priority, Bool.pick(U32, String.eq(mode, "zero"), 0, 7), cursor(mode))
        report(value)
        total : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(total))
        next : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- Source.chooseServerSource(Plan.Attempt<Endpoint.Endpoint>, source)
        IO.print("next:" ++ U32.show(Owned.nextPort(next)))
        Source.close(Plan.Attempt<Endpoint.Endpoint>, owner)
        Abort.dispose(String, parent)

def prepared(+mode: String, priority: Pair.Priority, value: Result<&2, &2, Plan.Error, List<&2, Plan.Attempt<Endpoint.Endpoint>>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "bad fixture plan")
    case Done{entries}:
      do IO<Unit>:
        owner : Source.Owner<Plan.Attempt<Endpoint.Endpoint>> <- Source.create(Plan.Attempt<Endpoint.Endpoint>, Bool.pick(List<&2, Plan.Attempt<Endpoint.Endpoint>>, String.eq(mode, "no-servers"), Nil{}, entries))
        run(mode, priority, Source.borrow(Plan.Attempt<Endpoint.Endpoint>, True{}, owner))

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> order <> +ipFamily <> first <> second <> Nil{}: prepared(mode, Bool.pick(Pair.Priority, String.eq(order, "4"), Pair.IPv4First{}, Pair.IPv6First{}), Plan.prepare(Endpoint.Endpoint, 1, UDPTest.destination(Scalar.decimal(ipFamily, 0), Scalar.decimal(first, 0)) <> UDPTest.destination(Scalar.decimal(ipFamily, 0), Scalar.decimal(second, 0)) <> Nil{}))
    case _: IO.die(Unit, 1, "expected mode priority family first-port second-port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
