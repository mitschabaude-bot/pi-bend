import Base
import ../packages/runtime/src/numeric-scope.bend as Scope
import ../packages/runtime/src/numeric-interface.bend as Native
import ../packages/runtime/src/network-interface.bend as Interface
import ../packages/runtime/src/numeric-host.bend as Host
import ../packages/runtime/src/ipv6-scope.bend as Zone
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./numeric-host.bend as Input

type Source is Data:
  Source{name: String, index: U32}

def lookup(source: Source, name: String) -> IO(Result<&2, &2, String, U32>):
  match source:
    case Source{expected, index}:
      +sharedName = name
      do IO<Result<&2, &2, String, U32>>:
        IO.print("lookup:" ++ Scalar.showText(sharedName))
        return Bool.pick(Result<&2, &2, String, U32>, String.eq(expected, sharedName), Done{index}, Fail{"missing"})

def stringError(text: String) -> String: text

def nativeError(error: Interface.Error) -> String: "native"

def diagnostic(~E: Data, ~show: E -> String, value: Maybe<&2, E>) -> String:
  match value:
    case None{}: "none"
    case Some{error}: show(error)

def report(~E: Data, ~show: E -> String, result: Result<&2, &2, Scope.Error<E>, Connect.Address>) -> String:
  match result:
    case Fail{Scope.InvalidInput{Host.InvalidAddress{text}}}: "invalid:" ++ Scalar.showText(text)
    case Fail{Scope.InvalidInput{Host.FamilyMismatch{}}}: "family"
    case Fail{Scope.InvalidScope{Zone.InvalidScope{zone, failure}}}: "scope:" ++ Scalar.showText(zone) ++ ":" ++ diagnostic(~E, ~show, failure)
    case Done{Connect.V4{IPv4.Address{value}}}: "4:" ++ U32.show(value)
    case Done{Connect.V6{IPv6.Address{a, b, c, d}, index}}: "6:" ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ ":" ++ U32.show(index)

def run(native: Bool, family: U32, text: String, name: String, index: U32) -> IO(Unit):
  match native:
    case False{}:
      do IO<Unit>:
        result : Result<&2, &2, Scope.Error<String>, Connect.Address> <- Scope.prepareWith(~String, ~Source, ~lookup, Source{name, index}, Input.family(family), text)
        IO.print(report(~String, ~stringError, result))
    case True{}:
      do IO<Unit>:
        result : Result<&2, &2, Scope.Error<Interface.Error>, Connect.Address> <- Native.prepare(Input.family(family), text)
        IO.print(report(~Interface.Error, ~nativeError, result))

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case family <> text <> mode <> name <> index <> rest:
      do IO<Unit>:
        run(String.eq(mode, "native"), Scalar.decimal(family, 0), Scalar.fromScalars(Scalar.parseNumbers(text)), Scalar.fromScalars(Scalar.parseNumbers(name)), Scalar.decimal(index, 0))
        args(rest)
    case _: IO.die(Unit, 1, "expected family text mode interface index groups")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
