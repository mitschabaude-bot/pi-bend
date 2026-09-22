import Base
import ../packages/runtime/src/resolver-config.bend as Address
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6

def zone(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: "some:" ++ text

def show(value: Result<&2, &2, Address.AddressError, Address.Address>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{Address.V4{IPv4.Address{word}}}: "4:" ++ U32.show(word)
    case Done{Address.V6{IPv6.Address{a,b,c,d}, scope}}: "6:" ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ ":" ++ zone(scope)

def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        IO.print(show(Address.parseAddress(text)))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
