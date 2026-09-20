import Base
import ./dns-lookup-options.bend as Options
import ../packages/runtime/src/dns-query.bend as Query
import ../packages/runtime/src/dns-tcp-resolver.bend as Resolver
import ../packages/runtime/src/dns-server-source.bend as Source
import ../packages/runtime/src/dns-tcp-servers.bend as Servers
import ../packages/runtime/src/dns-search.bend as Search
import ../packages/runtime/src/random-index.bend as Index
import ./dns-tcp-servers.bend as ServersTest
import ./dns-server-rotation.bend as RotationTest
import ./dns-search-rotation.bend as RotationNetworkTest

def seed(value: U32) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Done{value})

def fail(unused: U32) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Fail{Index.SourceFailure{11, "unavailable"}})

def requestLabel(request: Query.Options) -> String:
  match request:
    case Query.Options{flags, None{}}: U32.show(flags) ++ ":plain"
    case Query.Options{flags, Some{_}}: U32.show(flags) ++ ":edns"

def selected(pair: Resolver.Owner & Resolver.Resolver) -> IO(Resolver.Owner):
  match pair:
    case (owner, Resolver.Resolver{source, _, _, request, _, _}):
      do IO<Resolver.Owner>:
        servers : List<&2, Servers.Server> <- Source.choose(Servers.Server, source)
        IO.print(RotationTest.csv(RotationNetworkTest.serverPorts(servers, Nil{}), ""))
        IO.print(requestLabel(request))
        return owner

def config(ports: String, rotate: Bool, request: Query.Options) -> Resolver.Config:
  Resolver.Config{ServersTest.serverInput("4", ports), Nil{}, Search.Policy{1, True{}, True{}, False{}}, request, 5000, 7, rotate}

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
        first : Resolver.Owner <- selected(Resolver.borrow(owner))
        failure : Resolver.Replacement <- Resolver.replaceWith(~U32, ~fail, 0, first, config("90,91", True{}, Options.settings()))
        kept : Resolver.Owner <- retained(failure)
        second : Resolver.Owner <- selected(Resolver.borrow(kept))
        success : Resolver.Replacement <- Resolver.replaceWith(~U32, ~seed, 0, second, config("40,41", True{}, Options.settings()))
        updated : Resolver.Owner <- retained(success)
        third : Resolver.Owner <- selected(Resolver.borrow(updated))
        fixed : Resolver.Replacement <- Resolver.replaceWith(~U32, ~fail, 0, third, config("60,61", False{}, Query.defaults()))
        final : Resolver.Owner <- retained(fixed)
        fourth : Resolver.Owner <- selected(Resolver.borrow(final))
        fifth : Resolver.Owner <- selected(Resolver.borrow(fourth))
        Resolver.close(fifth)

def main() -> IO(Unit):
  do IO<Unit>:
    owner : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~seed, 1, config("10,11,12", True{}, Query.defaults()))
    exercise(owner)
