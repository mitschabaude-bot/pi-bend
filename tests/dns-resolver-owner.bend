import Base
import ./dns-lookup-options.bend as Options
import ../packages/runtime/src/dns-message.bend as Query
import ../packages/runtime/src/dns-resolver.bend as Resolver
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

def selected(pair: Resolver.TcpResolverOwner & Resolver.TcpResolverResolver) -> IO(Resolver.TcpResolverOwner):
  match pair:
    case (owner, Resolver.TcpResolverResolver{source, _, _, request, _, _}):
      do IO<Resolver.TcpResolverOwner>:
        servers : List<&2, Servers.Server> <- Source.chooseServerSource(Servers.Server, source)
        IO.print(RotationTest.csv(RotationNetworkTest.serverPorts(servers, Nil{}), ""))
        IO.print(requestLabel(request))
        return owner

def config(ports: String, rotate: Bool, request: Query.QueryOptions) -> Resolver.Config:
  Resolver.Config{ServersTest.serverInput("4", ports), Nil{}, Search.Policy{1, True{}, True{}, False{}}, request, 5000, 7, rotate}

def retained(value: Resolver.TcpResolverReplacement) -> IO(Resolver.TcpResolverOwner):
  match value:
    case Resolver.TcpResolverUpdated{owner}:
      do IO<Resolver.TcpResolverOwner>:
        IO.print("updated")
        return owner
    case Resolver.TcpResolverUnchanged{_, owner}:
      do IO<Resolver.TcpResolverOwner>:
        IO.print("unchanged")
        return owner

def exercise(result: Result<&2, &1, Index.Error, Resolver.TcpResolverOwner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "initialization failed")
    case Done{owner}:
      do IO<Unit>:
        first : Resolver.TcpResolverOwner <- selected(Resolver.borrowTcpResolver(owner))
        failure : Resolver.TcpResolverReplacement <- Resolver.replaceWithTcpResolver(~U32, ~fail, 0, first, config("90,91", True{}, Options.settings()))
        kept : Resolver.TcpResolverOwner <- retained(failure)
        second : Resolver.TcpResolverOwner <- selected(Resolver.borrowTcpResolver(kept))
        success : Resolver.TcpResolverReplacement <- Resolver.replaceWithTcpResolver(~U32, ~seed, 0, second, config("40,41", True{}, Options.settings()))
        updated : Resolver.TcpResolverOwner <- retained(success)
        third : Resolver.TcpResolverOwner <- selected(Resolver.borrowTcpResolver(updated))
        fixed : Resolver.TcpResolverReplacement <- Resolver.replaceWithTcpResolver(~U32, ~fail, 0, third, config("60,61", False{}, Query.defaults()))
        final : Resolver.TcpResolverOwner <- retained(fixed)
        fourth : Resolver.TcpResolverOwner <- selected(Resolver.borrowTcpResolver(final))
        fifth : Resolver.TcpResolverOwner <- selected(Resolver.borrowTcpResolver(fourth))
        Resolver.closeTcpResolver(fifth)

def main() -> IO(Unit):
  do IO<Unit>:
    owner : Result<&2, &1, Index.Error, Resolver.TcpResolverOwner> <- Resolver.createWithTcpResolver(~U32, ~seed, 1, config("10,11,12", True{}, Query.defaults()))
    exercise(owner)
