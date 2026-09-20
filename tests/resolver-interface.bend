import Base
import ../packages/runtime/src/network-interface.bend as Interface
import ../packages/runtime/src/resolver-interface.bend as Resolver
import ../packages/runtime/src/resolver-scope.bend as Scope
import ../packages/runtime/src/ipv6-scope.bend as IPv6Scope
import ../packages/runtime/src/resolver-address.bend as Address
import ../packages/runtime/src/abortable-connect.bend as Connect

def diagnostic(value: Maybe<&2, IPv6Scope.Error<Interface.Error>>) -> String:
  match value:
    case None{}: "none"
    case Some{IPv6Scope.InvalidScope{_, None{}}}: "invalid"
    case Some{IPv6Scope.InvalidScope{_, Some{Interface.Error{code, _}}}}: "error:" ++ U32.show(code)

def report(value: Scope.Report<Interface.Error>) -> IO(Unit):
  match value:
    case Scope.Report{Connect.V4{_}, failure}: IO.print("v4:" ++ diagnostic(failure))
    case Scope.Report{Connect.V6{_, scope}, failure}: IO.print(U32.show(scope) ++ ":" ++ diagnostic(failure))

def parsed(value: Result<&2, &2, Address.Error, Address.Address>) -> IO(Unit):
  match value:
    case Fail{_}: IO.print("bad-address")
    case Done{address}:
      do IO<Unit>:
        value : Scope.Report<Interface.Error> <- Resolver.resolve(address)
        report(value)

def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        parsed(Address.parse(text))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(values)
