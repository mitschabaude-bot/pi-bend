import Base
import ../packages/coding-agent/src/core/tools/read.bend as Read
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as Wire
import ./tool-truncate.bend as TruncateTest

def repeated(+reversed: String, count: Nat, result: String) -> String:
  match count:
    case 0n: String.reverse(result)
    case 1n+rest: repeated(reversed, rest, reversed ++ result)

def report(value: Result<&2, &2, Read.Error, Read.TextResult>) -> String:
  match value:
    case Fail{error}: "error|" ++ Read.errorMessage(error)
    case Done{Read.TextResult{text, None{}}}: "ok|" ++ Wire.showText(text) ++ "|none"
    case Done{Read.TextResult{text, Some{Read.ReadToolDetails{truncation}}}}:
      "ok|" ++ Wire.showText(text) ++ "|" ++ TruncateTest.report(truncation)

def run(parts: List<&2, String>) -> String:
  match parts:
    case path <> offset <> limit <> repetitions <> content <> Nil{}:
      report(Read.readText(Read.ReadToolInput{TruncateTest.text(path), TruncateTest.option(offset), TruncateTest.option(limit)}, repeated(String.reverse(TruncateTest.text(content)), U32.to_nat(Wire.decimal(repetitions, 0)), "")))
    case _: "invalid"

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(run(Strings.split(value, ':')))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
