import Base
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/test/utf8-runner.bend as Scalar

def address(value: File.Address) -> String:
  match value:
    case File.V4{IPv4.Address{value}}: "4:" ++ U32.show(value)
    case File.V6{IPv6.Address{a, b, c, d}}: "6:" ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def aliases(values: List<&2, String>) -> String:
  match values:
    case Nil{}: ""
    case text <> rest: Scalar.showText(text) ++ "|" ++ aliases(rest)

def entries(values: List<&2, Hosts.Entry<File.Address>>) -> String:
  match values:
    case Nil{}: ""
    case Hosts.Entry{ip, name, otherNames} <> rest: address(ip) ++ "/" ++ Scalar.showText(name) ++ "/" ++ aliases(otherNames) ++ ";" ++ entries(rest)

def error(value: File.Error) -> String:
  match value:
    case File.InvalidAddress{token}: "address:" ++ Scalar.showText(token)
    case File.MissingName{}: "name"
    case File.InvalidControl{code}: "control:" ++ U32.show(code)

def report(name: String, result: Result<&2, &2, File.Failure, List<&2, Hosts.Entry<File.Address>>>) -> String:
  match result:
    case Fail{File.Failure{line, cause}}: "error:" ++ U32.show(U32.from_nat(line)) ++ ":" ++ error(cause)
    case Done{values}: "ok:" ++ entries(Hosts.lookup(File.Address, name, values))

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case name <> text <> rest:
      do IO<Unit>:
        IO.print(report(Scalar.fromScalars(Scalar.parseNumbers(name)), File.parse(Scalar.fromScalars(Scalar.parseNumbers(text)))))
        args(rest)
    case _: IO.die(Unit, 1, "expected query/text scalar pairs")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
