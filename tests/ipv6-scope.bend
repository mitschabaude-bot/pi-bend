import Base
import ../packages/runtime/src/resolver-scope.bend as Resolver
import ../packages/runtime/src/resolver-address.bend as Address
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/ipv6-scope.bend as Scope
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/test/utf8-runner.bend as Scalar

type Source is Data:
  Source{name: String, index: U32}

def lookupSource(source: Source, +scope: String) -> IO(Result<&2, &2, String, U32>):
  match source:
    case Source{name, index}:
      do IO<Result<&2, &2, String, U32>>:
        IO.print("lookup:" ++ scope)
        return Bool.pick(Result<&2, &2, String, U32>, String.eq(name, scope), Done{index}, Fail{"missing"})

def lookup(source: Source, scope: String) -> IO(Result<&2, &2, String, U32>):
  lookupSource(source, scope)

def diagnostic(failure: Maybe<&2, String>) -> String:
  match failure:
    case None{}: "none"
    case Some{message}: message

def report(result: Result<&2, &2, Scope.Error<String>, U32>) -> IO(Unit):
  match result:
    case Done{index}: IO.print("index:" ++ U32.show(index))
    case Fail{Scope.InvalidScope{scope, failure}}: IO.print("invalid:" ++ scope ++ ":" ++ diagnostic(failure))

def resolution(value: Resolver.Report<String>) -> IO(Unit):
  match value:
    case Resolver.Report{Connect.V4{_}, _}: IO.print("v4")
    case Resolver.Report{Connect.V6{_, scope}, None{}}: IO.print("resolved:" ++ U32.show(scope))
    case Resolver.Report{Connect.V6{_, scope}, Some{_}}: IO.print("defaulted:" ++ U32.show(scope))

def runResolver(source: Source, address: Address.Address) -> IO(Unit):
  do IO<Unit>:
    value : Resolver.Report<String> <- Resolver.resolveWith(~String, ~Source, ~lookup, source, address)
    resolution(value)

def raw(result: Result<&2, &2, Address.Error, Address.Address>, source: Source) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "invalid fixture address")
    case Done{address}: runResolver(source, address)

def parsed(result: Result<&2, &2, IPv6.AddressError, IPv6.Address>, +scope: String, +source: Source) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "invalid fixture address")
    case Done{+address}:
      do IO<Unit>:
        result : Result<&2, &2, Scope.Error<String>, U32> <- Scope.resolveWith(~String, ~Source, ~lookup, source, address, scope)
        report(result)
        runResolver(source, Address.V6{address, Some{scope}})

def args(values: List<String>) -> IO(Unit):
  match values:
    case address <> scope <> name <> index <> Nil{}: parsed(IPv6.parse(address), scope, Source{name, Scalar.decimal(index, 0)})
    case address <> name <> index <> Nil{}: raw(Address.parse(address), Source{name, Scalar.decimal(index, 0)})
    case _: IO.die(Unit, 1, "expected address [scope] interface index")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
