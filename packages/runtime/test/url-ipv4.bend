import Base
import ../src/url-ipv4.bend as IPv4

def show(result: Result<&2, &2, IPv4.AddressError, IPv4.Address>) -> String:
  match result:
    case Fail{_}: "invalid"
    case Done{address}: IPv4.serialize(address)

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case +text <> rest:
      do IO<Unit>:
        IO.print(Bool.pick(String, IPv4.endsInNumber(text), "numeric;", "domain;") ++ show(IPv4.parse(text)))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
