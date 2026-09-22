import Base
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts.bend as File
import ../packages/runtime/src/hosts.bend as Family
import ../packages/runtime/src/hosts.bend as Resolve
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./hosts-file.bend as Show

def family(text: String) -> Family.Family:
  match text:
    case "4": Family.IPv4Only{}
    case "6": Family.IPv6Only{}
    case _: Family.Any{}

def familyText(value: Family.Family) -> String:
  match value:
    case Family.Any{}: "any"
    case Family.IPv4Only{}: "4"
    case Family.IPv6Only{}: "6"

def networkResult(fail: Bool) -> Result<&2, &2, U32, String>:
  match fail:
    case True{}: Fail{73}
    case False{}: Done{"retained-network-report"}

def network(fail: Bool, value: Family.Family, name: String) -> IO(Result<&2, &2, U32, String>):
  do IO<Result<&2, &2, U32, String>>:
    IO.print("query:" ++ familyText(value) ++ ":" ++ Scalar.showText(name))
    return networkResult(fail)

def report(value: Resolve.Report<File.Failure, Result<&2, &2, U32, String>>) -> String:
  match value:
    case Resolve.FailedSource{File.Failure{line, cause}}: "error:" ++ U32.show(U32.from_nat(line)) ++ ":" ++ Show.error(cause)
    case Resolve.FromHosts{first, rest}: "hosts:" ++ Show.entries(first <> rest)
    case Resolve.FromNetwork{Fail{code}}: "network-error:" ++ U32.show(code)
    case Resolve.FromNetwork{Done{text}}: "network:" ++ text

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case requested <> failure <> name <> text <> rest:
      do IO<Unit>:
        result : Resolve.Report<File.Failure, Result<&2, &2, U32, String>> <- Resolve.resolveWith(~Bool, ~File.Failure, ~Result<&2, &2, U32, String>, ~network, String.eq(failure, "fail"), family(requested), Scalar.fromScalars(Scalar.parseNumbers(name)), File.parse(Scalar.fromScalars(Scalar.parseNumbers(text))))
        IO.print(report(result))
        args(rest)
    case _: IO.die(Unit, 1, "expected family/failure/query/text groups")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
