import Base
import ../packages/runtime/src/numeric-host.bend as Host
import ../packages/runtime/src/hosts.bend as Family
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/test/utf8-runner.bend as Scalar

def family(value: U32) -> Family.Family:
  match value:
    case 4: Family.IPv4Only{}
    case 6: Family.IPv6Only{}
    case _: Family.Any{}

def zone(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: "zone:" ++ Scalar.showText(text)

def show(value: Result<&2, &2, Host.Error, Host.Input>) -> String:
  match value:
    case Fail{Host.InvalidAddress{text}}: "invalid:" ++ Scalar.showText(text)
    case Fail{Host.FamilyMismatch{}}: "family"
    case Done{Host.V4{IPv4.Address{address}}}: "4:" ++ U32.show(address)
    case Done{Host.V6{IPv6.Address{a, b, c, d}, scope}}: "6:" ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ ":" ++ zone(scope)

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case requested <> text <> rest:
      do IO<Unit>:
        IO.print(show(Host.prepare(family(Scalar.decimal(requested, 0)), Scalar.fromScalars(Scalar.parseNumbers(text)))))
        args(rest)
    case _: IO.die(Unit, 1, "expected family and scalar-encoded input pairs")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
