import Base
import ../src/punycode.bend as Punycode
import ../src/punycode.bend as Core
import ./utf8-runner.bend as Text
import ../src/string.bend as Split

def numbers(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: numbers(rest, reversed)
    case part <> rest: numbers(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def show(result: Result<&2, &2, Core.Error, String>) -> String:
  match result:
    case Fail{Core.Overflow{}}: "overflow"
    case Fail{_}: "invalid"
    case Done{text}: "+" ++ Text.showText(text)

def run(parts: List<&2, String>) -> String:
  match parts:
    case "e" <> input <> Nil{}: show(Punycode.encode(numbers(Split.split(input, ','), "")))
    case "d" <> input <> Nil{}: show(Punycode.decode(numbers(Split.split(input, ','), "")))
    case _: "invalid-case"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
