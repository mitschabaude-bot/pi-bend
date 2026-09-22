import Base
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
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
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
    case Endpoint.V4{_, port}: port
    case Endpoint.V6{_, port, _}: port

def nextPort(values: List<&2, Plan.Attempt<Endpoint.Endpoint>>) -> U32:
  match values:
    case Plan.Attempt{endpoint, _, _} <> _: endpointPort(endpoint)
    case Nil{}: 0

type DrawSource is Data:
  DrawSource{ids: IDs.Source, mode: String, child: Abort.AbortController<Deadline.Cause<String>>}

def abortChild(enabled: Bool, child: Abort.AbortController<Deadline.Cause<String>>) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Deadline.Cause<String>, child, Some{Deadline.ParentAbort{Abort.Supplied{"stop"}}})
        return Unit{}

def draw(value: DrawSource) -> IO(Result<&2, &2, Id.IdError, U32>):
  match value:
    case DrawSource{ids, mode, child}:
      do IO<Result<&2, &2, Id.IdError, U32>>:
        result : Result<&2, &2, Id.IdError, U32> <- IDs.draw(ids)
        abortChild(String.eq(mode, "abort-child"), child)
        return result

def run(+mode: String, ids: IDs.Source, +options: Options.OptionsOptions, kind: U32, pair: Selector.Owner<Plan.Attempt<Endpoint.Endpoint>> & Selector.ServerSourceSource<Plan.Attempt<Endpoint.Endpoint>>, scopePair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match pair, scopePair:
    case (owner, +source), (Deadline.Scope{+child, lifetime}, signal):
      do IO<Unit>:
        result : Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection> <- Lookup.exchangeTransportOptionsWith(~DrawSource, ~draw, String, DrawSource{ids, mode, child}, Exchange.Configured{source, options}, signal, queryOptions(Request.prepareRequest(options)), kind, Name.Name{(97 <> Nil{}) <> Nil{}}, Bool.pick(U32, String.eq(mode, "size"), 0, 7))
        IO.print(outcome(result))
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, Deadline.Scope{child, lifetime})
        IO.print(TCPTest.retained(reason))
        next : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- Selector.chooseServerSource(Plan.Attempt<Endpoint.Endpoint>, source)
        IO.print("next:" ++ U32.show(nextPort(next)))
        Selector.close(Plan.Attempt<Endpoint.Endpoint>, owner)

def ready(+mode: String, kind: U32, value: Result<&2, &2, Plan.Error, Prepare.TransportPrepared<Endpoint.Endpoint>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "invalid test plan")
    case Done{Prepare.TransportPrepared{+options, servers}}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        TCPTest.prepare(String.eq(mode, "pre"), False{}, parent)
        owner : Selector.Owner<Plan.Attempt<Endpoint.Endpoint>> <- Selector.create(Plan.Attempt<Endpoint.Endpoint>, servers)
        scope : Deadline.Scope<String> <- Deadline.create(String, Bool.pick(U32, String.eq(mode, "deadline"), 1200, 5000), Abort.signal(String, parent))
        run(mode, IDs.Source{mode, count, parent}, options, kind, Selector.borrow(Plan.Attempt<Endpoint.Endpoint>, Options.enabled(Options.Rotate{}, options), owner), Deadline.borrow(String, scope))
        draws : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)

def features(+mode: String) -> List<&2, Options.Feature>:
  tcp = Bool.pick(List<&2, Options.Feature>, String.eq(mode, "forced") || String.eq(mode, "forced-alias"), Options.UseTcp{} <> Nil{}, Nil{})
  rotate = Bool.pick(List<&2, Options.Feature>, String.eq(mode, "rotate") || String.eq(mode, "rotate-alias") || String.eq(mode, "abort-source") || String.eq(mode, "abort-child") || String.eq(mode, "error-first") || String.eq(mode, "pre"), Options.Rotate{} <> Nil{}, Nil{})
  edns = Bool.pick(List<&2, Options.Feature>, String.eq(mode, "edns"), Options.Edns{} <> Nil{}, Nil{})
  List.append(&2, Options.Feature, tcp, List.append(&2, Options.Feature, rotate, edns))

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> +family <> first <> second <> kind <> Nil{}:
      ready(mode, Scalar.decimal(kind, 0), Prepare.prepareTransport(Endpoint.Endpoint, Options.OptionsOptions{1, 1, Bool.pick(U32, String.eq(mode, "zero-attempts"), 0, 2), features(mode)}, UDPTest.destination(Scalar.decimal(family, 0), Scalar.decimal(first, 0)) <> UDPTest.destination(Scalar.decimal(family, 0), Scalar.decimal(second, 0)) <> Nil{}))
    case _: IO.die(Unit, 1, "expected mode family first second kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
