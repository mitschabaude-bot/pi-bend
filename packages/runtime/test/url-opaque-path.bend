import Base
import ../src/url-opaque-path.bend as Path
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

def decode(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: decode(rest, reversed)
    case part <> rest: decode(rest, SCon{Chr{Text.decimal(part, 0)}, reversed})

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "absent;"
    case Some{value}: "present;" ++ Text.showText(value)

def show(result: Path.Parsed) -> String:
  match result:
    case Path.Parsed{value, query, fragment}: Text.showText(value) ++ ";" ++ optional(query) ++ ";" ++ optional(fragment)

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(show(Path.parse(decode(Split.split(head, ','), ""))))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
