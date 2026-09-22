import Base
import ../packages/runtime/src/dns-resolver.bend as Pair
import ../packages/runtime/src/dns-resolver.bend as Setup
import ../packages/runtime/src/dns-message.bend as Queries
import ../packages/runtime/src/dns-resolver.bend as Lookup
import ../packages/runtime/src/dns-resolver.bend as Answer
import ../packages/runtime/src/dns-transport.bend as Exchange
import ../packages/runtime/src/dns-transport.bend as Source
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/socket.bend as Endpoint
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/dns-message.bend as Request
import ../packages/runtime/src/dns-message.bend as Edns
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/dns-message.bend as Id
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-udp-query.bend as UDPTest
import ./dns-owned-search.bend as Owned
import ./dns-lookup-ids.bend as IDs
import ./dns-tcp-query.bend as TCPTest

type Environment is Data:
  Environment{mode: String, count: Ref.Ref<U32>, controller: Abort.AbortController<Deadline.Cause<String>>}

def cancel(enabled: Bool, controller: Abort.AbortController<Deadline.Cause<String>>) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Deadline.Cause<String>, controller, Some{Deadline.ParentAbort{Abort.Supplied{"retained cancellation"}}})
        return Unit{}

def chosen(same: Bool, invalid: Bool, fail: Bool, index: U32) -> Result<&2, &2, Id.IdError, U32>:
  match same invalid fail:
    case _ _ True{}: Fail{Id.SourceFailure{(11 + index : U32), "entropy failed"}}
    case _ True{} False{}: Done{65536}
    case True{} False{} False{}: Done{42}
    case False{} False{} False{}: IDs.numbered(index)

def draw(environment: Environment) -> IO(Result<&2, &2, Id.IdError, U32>):
  match environment:
    case Environment{+mode, count, controller}:
      do IO<Result<&2, &2, Id.IdError, U32>>:
        +index : U32 <- Ref.modify(U32, U32, count, +value => ((value + 1 : U32), value))
        cancel((String.eq(mode, "abort-first") && U32.is_eq(index, 0)) || (String.eq(mode, "abort-second") && U32.is_eq(index, 1)), controller)
        return chosen(String.eq(mode, "same-ids"), (String.eq(mode, "invalid-first") && U32.is_eq(index, 0)) || (String.eq(mode, "invalid-second") && U32.is_eq(index, 1)), (String.eq(mode, "error-first") && U32.is_eq(index, 0)) || (String.eq(mode, "error-second") && U32.is_eq(index, 1)), index)

def family(value: Queries.Family) -> String:
  match value:
    case Queries.IPv4{}: "4"
    case Queries.IPv6{}: "6"

def cause(value: Abort.AbortReason<Deadline.Cause<String>>) -> String:
  match value:
    case Abort.Supplied{Deadline.Expired{}}: "expiry"
    case Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{message}}}: "parent:" ++ message
    case Abort.Supplied{Deadline.ParentAbort{Abort.DefaultAbort{}}}: "default"
    case Abort.DefaultAbort{}: "unexpected-default"

def retained(value: Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>>) -> String:
  match value:
    case None{}: "none"
    case Some{reason}: cause(reason)

def failed(value: Setup.PairSetupError<String>) -> String:
  match value:
    case Setup.PairSetupInvalidReadSize{}: "zero"
    case Setup.PairSetupNoServers{}: "servers"
    case Setup.PairSetupAborted{reason}: "abort:" ++ cause(reason)
    case Setup.PairSetupIdentifier{which, Id.SourceFailure{code, _}}: "entropy:" ++ family(which) ++ ":" ++ U32.show(code)
    case Setup.PairSetupIdentifier{which, _}: "entropy:" ++ family(which)
    case Setup.Encoding{Queries.Encoding{which, _}}: "encoding:" ++ family(which)

def report(value: Result<&2, &2, Setup.PairSetupError<String>, Pair.Reports<String>>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("setup:" ++ failed(error))
    case Done{Pair.Reports{a, b}}:
      do IO<Unit>:
        IO.print("4:" ++ Owned.outcome(a))
        IO.print("6:" ++ Owned.outcome(b))

def queryOptions(+mode: String) -> Request.QueryOptions:
  Request.QueryOptions{Bool.pick(U32, String.eq(mode, "bad-flags"), 65536, 256), Bool.pick(Maybe<&2, Edns.Query>, String.eq(mode, "edns"), Some{Edns.Query{1200, False{}, Nil{}}}, None{})}

def named(mode: String) -> Name.Name:
  Bool.pick(Name.Name, String.eq(mode, "bad-name"), Name.Name{Nil{} <> Nil{}}, Name.Name{(97 <> Nil{}) <> Nil{}})

def classResult(value: Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection>) -> IO(Unit):
  match value:
    case Fail{Lookup.UnsupportedClass{}}: IO.print("class")
    case _: IO.die(Unit, 1, "non-IN request accepted")

def performed(wrongClass: Bool, environment: Environment, source: Exchange.Source, signal: Abort.AbortSignal<Deadline.Cause<String>>, options: Request.QueryOptions, name: Name.Name, maximum: U32) -> IO(Unit):
  match wrongClass:
    case False{}:
      do IO<Unit>:
        result : Result<&2, &2, Setup.PairSetupError<String>, Pair.Reports<String>> <- Pair.exchangeWithAddressPair(~Environment, ~draw, String, environment, source, signal, options, name, maximum)
        report(result)
    case True{}:
      do IO<Unit>:
        result : Result<&2, &2, Lookup.AddressLookupError<String>, Answer.Selection> <- Lookup.exchangeRequestWith(~Environment, ~draw, String, environment, source, signal, Request.createQuery(options, 42, Message.Question{name, 1, 3}), maximum)
        classResult(result)


def scoped(+mode: String, count: Ref.Ref<U32>, source: Exchange.Source, scope: Deadline.Scope<String>) -> IO(Unit):
  match scope:
    case Deadline.Scope{+controller, lifetime}:
      do IO<Unit>:
        cancel(String.eq(mode, "pre"), controller)
        performed(String.eq(mode, "wrong-class"), Environment{mode, count, controller}, source, Abort.signal(Deadline.Cause<String>, controller), queryOptions(mode), named(mode), Bool.pick(U32, String.eq(mode, "zero"), 0, 7))
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, Deadline.Scope{controller, lifetime})
        IO.print("deadline:" ++ retained(reason))

def run(+mode: String, pair: Source.Owner<Plan.Attempt<Endpoint.Endpoint>> & Source.ServerSource<Plan.Attempt<Endpoint.Endpoint>>) -> IO(Unit):
  match pair:
    case (owner, +source):
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +count : Ref.Ref<U32> <- Ref.new(U32, 0)
        scope : Deadline.Scope<String> <- Deadline.create(String, Bool.pick(U32, String.eq(mode, "deadline"), 150, 5000), Abort.signal(String, parent))
        scoped(mode, count, Exchange.Configured{source, Options.ResolverOptions{1, 1, 1, Bool.pick(List<&2, Options.Feature>, String.eq(mode, "forced"), Options.UseTcp{} <> Nil{}, Nil{})}}, scope)
        total : U32 <- Ref.dispose(U32, count)
        IO.print("draws:" ++ U32.show(total))
        next : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- Source.chooseServerSource(Plan.Attempt<Endpoint.Endpoint>, source)
        IO.print("next:" ++ U32.show(Owned.nextPort(next)))
        Source.close(Plan.Attempt<Endpoint.Endpoint>, owner)
        Abort.dispose(String, parent)

def prepared(+mode: String, value: Result<&2, &2, Plan.Error, List<&2, Plan.Attempt<Endpoint.Endpoint>>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "bad fixture plan")
    case Done{entries}:
      do IO<Unit>:
        owner : Source.Owner<Plan.Attempt<Endpoint.Endpoint>> <- Source.create(Plan.Attempt<Endpoint.Endpoint>, Bool.pick(List<&2, Plan.Attempt<Endpoint.Endpoint>>, String.eq(mode, "no-servers"), Nil{}, entries))
        run(mode, Source.borrow(Plan.Attempt<Endpoint.Endpoint>, Bool.not(String.eq(mode, "fixed")), owner))

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> +ipFamily <> first <> second <> Nil{}: prepared(mode, Plan.prepare(Endpoint.Endpoint, 1, UDPTest.destination(Scalar.decimal(ipFamily, 0), Scalar.decimal(first, 0)) <> UDPTest.destination(Scalar.decimal(ipFamily, 0), Scalar.decimal(second, 0)) <> Nil{}))
    case _: IO.die(Unit, 1, "expected mode family first-port second-port")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
