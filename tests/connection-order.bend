import Base
import ../packages/runtime/src/connection-driver.bend as Order
import ../packages/runtime/src/connection-driver.bend as Candidates
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/url.bend as IPv4
import ../packages/runtime/src/url.bend as IPv6
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Scalar

def address(words: List<&2, U32>) -> Result<&2, &2, Unit, Connect.Address>:
  match words:
    case 4 <> value <> Nil{}: Done{Connect.V4{IPv4.Address{value}}}
    case 6 <> a <> b <> c <> d <> scope <> Nil{}: Done{Connect.V6{IPv6.Ipv6Address{a, b, c, d}, scope}}
    case _: Fail{Unit{}}

def cons(value: Result<&2, &2, Unit, Connect.Address>, rest: Result<&2, &2, Unit, List<&2, Connect.Address>>) -> Result<&2, &2, Unit, List<&2, Connect.Address>>:
  match value rest:
    case Done{first} Done{tail}: Done{first <> tail}
    case _ _: Fail{Unit{}}

def parsed(parts: List<&2, String>) -> Result<&2, &2, Unit, List<&2, Connect.Address>>:
  match parts:
    case Nil{}: Done{Nil{}}
    case SNil{} <> Nil{}: Done{Nil{}}
    case first <> rest: cons(address(Scalar.parseNumbers(first)), parsed(rest))

def groups(addresses: List<&2, Connect.Address>, ipv4: List<&2, Connect.Address>, ipv6: List<&2, Connect.Address>) -> Candidates.Candidates:
  match addresses:
    case Nil{}: Candidates.Paired{List.reverse(&2, Connect.Address, ipv4), List.reverse(&2, Connect.Address, ipv6)}
    case Connect.V4{value} <> rest: groups(rest, Connect.V4{value} <> ipv4, ipv6)
    case Connect.V6{value, scope} <> rest: groups(rest, ipv4, Connect.V6{value, scope} <> ipv6)

def ordered(paired: Bool, preference: Order.Preference, addresses: List<&2, Connect.Address>) -> List<&2, Connect.Address>:
  match paired addresses:
    case False{} Nil{}: Nil{}
    case False{} first <> rest: Order.prepare(preference, Candidates.Ordered{first, rest})
    case True{} values: Order.prepare(preference, groups(values, Nil{}, Nil{}))

def shown(address: Connect.Address) -> String:
  match address:
    case Connect.V4{IPv4.Address{value}}: "4," ++ U32.show(value) ++ ";"
    case Connect.V6{IPv6.Ipv6Address{a, b, c, d}, scope}: "6," ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ "," ++ U32.show(scope) ++ ";"

def show(addresses: List<&2, Connect.Address>) -> String:
  match addresses:
    case Nil{}: ""
    case first <> rest: shown(first) ++ show(rest)

def run(preference: Order.Preference, paired: Bool, value: Result<&2, &2, Unit, List<&2, Connect.Address>>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "invalid fixture address")
    case Done{values}: IO.print(show(ordered(paired, preference, values)))

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case preference <> mode <> addresses <> rest:
      do IO<Unit>:
        run(Bool.pick(Order.Preference, String.eq(preference, "4"), Order.IPv4First{}, Order.IPv6First{}), String.eq(mode, "paired"), parsed(Split.split(addresses, ';')))
        args(rest)
    case _: IO.die(Unit, 1, "expected preference mode addresses groups")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
