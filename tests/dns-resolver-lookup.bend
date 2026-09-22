import Base
import ../packages/runtime/src/resolver-config.bend as Configuration
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/resolver-config.bend as ParsedOptions
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/dns-resolver.bend as Network
import ../packages/runtime/src/random.bend as Index
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-lookup-ids.bend as IDs
import ./dns-tcp-servers.bend as ServersTest
import ./dns-address-search.bend as Output
import ./dns-resolver-owner.bend as OwnerTest

def run(+mode: String, +kind: U32, +environment: IDs.Source, +parent: Abort.AbortSignal<String>, pair: Resolver.TcpResolverOwner & Resolver.TcpResolver) -> IO(Unit):
  match pair:
    case (owner, +resolver):
      do IO<Unit>:
        first : Network.AddressSearchReport<String> <- Resolver.lookupWithTcpResolver(~IDs.Source, ~IDs.draw, ~String, environment, resolver, parent, kind, Name.Name{(97 <> Nil{}) <> Nil{}}, 0, String.eq(mode, "absolute"))
        Output.report(first)
        second : Network.AddressSearchReport<String> <- Resolver.lookupWithTcpResolver(~IDs.Source, ~IDs.draw, ~String, environment, resolver, parent, kind, Name.Name{(98 <> Nil{}) <> Nil{}}, 0, String.eq(mode, "absolute"))
        Output.report(second)
        Resolver.closeTcpResolver(owner)

def created(mode: String, kind: U32, environment: IDs.Source, parent: Abort.AbortSignal<String>, result: Result<&2, &1, Index.Error, Resolver.TcpResolverOwner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "initialization failed")
    case Done{owner}: run(mode, kind, environment, parent, Resolver.borrowTcpResolver(owner))

def domains(firstInvalid: Bool, laterInvalid: Bool) -> List<&2, String>:
  match firstInvalid laterInvalid:
    case True{} _: "..bad" <> "y" <> Nil{}
    case False{} True{}: "x" <> "..bad" <> "y" <> Nil{}
    case False{} False{}: "x" <> "y" <> Nil{}

def configuration(result: Result<&2, &2, List<&2, ParsedOptions.Diagnostic>, Configuration.Configuration>) -> IO(Configuration.Configuration):
  match result:
    case Fail{_}: IO.die(Configuration.Configuration, 2, "invalid options")
    case Done{value}: IO.pure(Configuration.Configuration, value)

def args(values: List<String>) -> IO(Unit):
  match values:
    case options <> +mode <> family <> ports <> kind <> tuning <> Nil{}:
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        +counter : Ref.Ref<U32> <- Ref.new(U32, 0)
        settings : Configuration.Configuration <- configuration(Configuration.prepareStrictSearch(Config.words("ndots:2 " ++ Bool.pick(String, String.eq(mode, "fixed"), "", "rotate ") ++ Bool.pick(String, String.eq(options, "edns"), "edns0 trust-ad", "") ++ " " ++ tuning, Config.Words{"", Nil{}}), domains(String.eq(mode, "invalid-domain"), String.eq(mode, "invalid-later"))))
        owner : Result<&2, &1, Index.Error, Resolver.TcpResolverOwner> <- Resolver.createWithTcpResolver(~U32, ~OwnerTest.seed, 1, Resolver.fromSearch(ServersTest.serverInput(family, ports), Bool.pick(U32, String.eq(mode, "deadline"), 300, 5000), 7, settings))
        created(mode, Scalar.decimal(kind, 0), IDs.Source{"direct", counter, parent}, Abort.signal(String, parent), owner)
        draws : U32 <- Ref.dispose(U32, counter)
        IO.print("draws:" ++ U32.show(draws))
        Abort.dispose(String, parent)
    case _: IO.die(Unit, 1, "expected options mode family ports kind tuning")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
