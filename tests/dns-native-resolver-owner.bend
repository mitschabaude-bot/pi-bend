import Base
import ../packages/runtime/src/socket.bend as Connect
import ./dns-lookup-options.bend as Options
import ../packages/runtime/src/dns-message.bend as Query
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/resolver-config.bend as Settings
import ../packages/runtime/src/resolver-config.bend as Configuration
import ../packages/runtime/src/resolver-config.bend as Policy
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/socket.bend as Endpoint
import ./dns-udp-plan.bend as PlanTest
import ../packages/runtime/src/dns-transport.bend as Source
import ../packages/runtime/src/dns-transport.bend as Servers
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/random.bend as Index
import ./dns-tcp-servers.bend as ServersTest
import ./dns-server-rotation.bend as RotationTest
import ./dns-search-rotation.bend as RotationNetworkTest

def seed(value: U32) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Done{value})

def fail(unused: U32) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Fail{Index.SourceFailure{11, "unavailable"}})

def requestLabel(request: Query.QueryOptions) -> String:
  match request:
    case Query.QueryOptions{flags, None{}}: U32.show(flags) ++ ":plain"
    case Query.QueryOptions{flags, Some{_}}: U32.show(flags) ++ ":edns"

def endpoints(servers: List<&2, Servers.Server>) -> List<&2, Endpoint.Endpoint>:
  match servers:
    case Nil{}: Nil{}
    case Servers.Server{Connect.V4{ip}, port} <> rest: Endpoint.EndpointV4{ip, port} <> endpoints(rest)
    case Servers.Server{Connect.V6{ip, scope}, port} <> rest: Endpoint.EndpointV6{ip, port, scope} <> endpoints(rest)

def timed(entries: List<&2, Plan.Attempt<Endpoint.Endpoint>>) -> String:
  match entries:
    case Nil{}: ""
    case Plan.Attempt{Endpoint.EndpointV4{_, port}, position, duration} <> rest: PlanTest.show(Plan.Attempt{port, position, duration}) ++ timed(rest)
    case _ <> rest: "unexpected-v6" ++ timed(rest)

def selected(pair: Resolver.Owner & Resolver.Resolver) -> IO(Resolver.Owner):
  match pair:
    case (owner, Resolver.Resolver{config, source}):
      do IO<Resolver.Owner>:
        servers : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- Source.chooseServerSource(Plan.Attempt<Endpoint.Endpoint>, source)
        IO.print(timed(servers))
        IO.print(requestLabel(Configuration.requestOptions(Settings.search(Endpoint.Endpoint, config))))
        return owner

def validated(value: Result<&2, &2, Plan.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Settings.Config<Endpoint.Endpoint>):
  match value:
    case Fail{_}: IO.die(Settings.Config<Endpoint.Endpoint>, 1, "invalid fixture configuration")
    case Done{config}: IO.pure(Settings.Config<Endpoint.Endpoint>, config)

def config(ports: String, rotate: Bool, extended: Bool) -> IO(Settings.Config<Endpoint.Endpoint>):
  features = List.append(&2, Policy.Feature, Bool.pick(List<&2, Policy.Feature>, rotate, Policy.Rotate{} <> Nil{}, Nil{}), Bool.pick(List<&2, Policy.Feature>, extended, Policy.Edns{} <> Policy.TrustAd{} <> Nil{}, Nil{}))
  validated(Settings.prepareConfiguration(Endpoint.Endpoint, endpoints(ServersTest.serverInput("4", ports)), 5000, 7, Configuration.prepareSearch(Policy.ResolverOptions{1, 2, 2, features}, Nil{})))

def retained(value: Resolver.Replacement) -> IO(Resolver.Owner):
  match value:
    case Resolver.Updated{owner}:
      do IO<Resolver.Owner>:
        IO.print("updated")
        return owner
    case Resolver.Unchanged{_, owner}:
      do IO<Resolver.Owner>:
        IO.print("unchanged")
        return owner

def exercise(result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "initialization failed")
    case Done{owner}:
      do IO<Unit>:
        bad : Settings.Config<Endpoint.Endpoint> <- config("90,91", True{}, True{})
        good : Settings.Config<Endpoint.Endpoint> <- config("40,41", True{}, True{})
        disabled : Settings.Config<Endpoint.Endpoint> <- config("60,61", False{}, False{})
        first : Resolver.Owner <- selected(Resolver.borrow(owner))
        failure : Resolver.Replacement <- Resolver.replaceWith(~U32, ~fail, 0, first, bad)
        kept : Resolver.Owner <- retained(failure)
        second : Resolver.Owner <- selected(Resolver.borrow(kept))
        success : Resolver.Replacement <- Resolver.replaceWith(~U32, ~seed, 0, second, good)
        updated : Resolver.Owner <- retained(success)
        third : Resolver.Owner <- selected(Resolver.borrow(updated))
        fixed : Resolver.Replacement <- Resolver.replaceWith(~U32, ~fail, 0, third, disabled)
        final : Resolver.Owner <- retained(fixed)
        fourth : Resolver.Owner <- selected(Resolver.borrow(final))
        fifth : Resolver.Owner <- selected(Resolver.borrow(fourth))
        Resolver.close(fifth)

def main() -> IO(Unit):
  do IO<Unit>:
    initial : Settings.Config<Endpoint.Endpoint> <- config("10,11,12", True{}, False{})
    owner : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~seed, 1, initial)
    exercise(owner)
