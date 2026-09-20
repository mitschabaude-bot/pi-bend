import Base
import ../packages/runtime/src/dns-tcp-resolver.bend as Resolver
import ../packages/runtime/src/dns-search.bend as Search
import ../packages/runtime/src/dns-name.bend as Name
import ../packages/runtime/src/dns-address-search.bend as Network
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-lookup-ids.bend as IDs
import ./dns-tcp-servers.bend as ServersTest
import ./dns-address-search.bend as Output
import ./dns-resolver-owner.bend as OwnerTest

def run(+mode: String, +kind: U32, +environment: IDs.Source, +parent: Abort.AbortSignal<String>, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case (owner, +resolver):
      do IO<Unit>:
        first : Network.Report<String> <- Resolver.lookupWith(~IDs.Source, ~IDs.draw, ~String, environment, resolver, parent, kind, Name.Name{(97 <> Nil{}) <> Nil{}}, 0, String.eq(mode, "absolute"))
        Output.report(first)
        second : Network.Report<String> <- Resolver.lookupWith(~IDs.Source, ~IDs.draw, ~String, environment, resolver, parent, kind, Name.Name{(98 <> Nil{}) <> Nil{}}, 0, String.eq(mode, "absolute"))
        Output.report(second)
        Resolver.close(owner)

def created(mode: String, kind: U32, environment: IDs.Source, parent: Abort.AbortSignal<String>, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "initialization failed")
    case Done{owner}: run(mode, kind, environment, parent, Resolver.borrow(owner))

def domains(firstInvalid: Bool, laterInvalid: Bool) -> List<&2, Search.Domain>:
  match firstInvalid laterInvalid:
    case True{} _: Search.Invalid{Name.InvalidLabel{}} <> Search.Valid{Name.Name{(121 <> Nil{}) <> Nil{}}} <> Nil{}
    case False{} True{}: Search.Valid{Name.Name{(120 <> Nil{}) <> Nil{}}} <> Search.Invalid{Name.InvalidLabel{}} <> Search.Valid{Name.Name{(121 <> Nil{}) <> Nil{}}} <> Nil{}
    case False{} False{}: Search.Valid{Name.Name{(120 <> Nil{}) <> Nil{}}} <> Search.Valid{Name.Name{(121 <> Nil{}) <> Nil{}}} <> Nil{}

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> family <> ports <> kind <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
        owner : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~OwnerTest.seed, 1, Resolver.Config{ServersTest.serverInput(family, ports), domains(String.eq(mode, "invalid-domain"), String.eq(mode, "invalid-later")), Search.Policy{2, True{}, True{}, False{}}, Bool.pick(U32, String.eq(mode, "deadline"), 300, 5000), 7, Bool.not(String.eq(mode, "fixed"))})
        created(mode, Scalar.decimal(kind, 0), IDs.Source{"direct", counter, parent}, Abort.signal(String, parent), owner)
        draws : U32 <- Ref.dispose(U32, counter)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)
    case _: IO.die(Unit, 1, "expected mode family ports kind")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
