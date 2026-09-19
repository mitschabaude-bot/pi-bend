import Base
import ../src/url-ipv6.bend as IPv6

def show(result: Result<&2, &2, IPv6.AddressError, IPv6.Address>) -> String:
  match result:
    case Fail{_}: "invalid"
    case Done{address}: IPv6.serialize(address)

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        IO.print(show(IPv6.parse(text)))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
