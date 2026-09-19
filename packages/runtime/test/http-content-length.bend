import Base
import ../src/http-content-length.bend as Length
import ../src/http-header.bend as H
import ../src/u64.bend as W
import ./utf8-runner.bend as Text

def shown(result: Result<&2, &2, Length.LengthError, Maybe<&2, W.U64>>) -> String:
  match result:
    case Fail{Length.LengthOverflow{}}: "overflow"
    case Fail{Length.DuplicateLength{}}: "duplicate"
    case Fail{_}: "invalid"
    case Done{None{}}: "none"
    case Done{Some{W.U64{high, low}}}: U32.show(high) ++ "," ++ U32.show(low)

def entry(parts: List<&2, String>) -> H.Header:
  match parts:
    case name <> value <> Nil{}: H.Header{Text.fromScalars(Text.parseNumbers(name)), Text.fromScalars(Text.parseNumbers(value))}
    case _: H.Header{"unused", ""}

def fields(parts: List<&2, String>) -> List<&2, H.Header>:
  match parts:
    case Nil{}: Nil{}
    case head <> rest: entry(String.split(head, ':')) <> fields(rest)

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "p" <> value <> Nil{}: IO.print(shown(Length.optional(Length.parse(Text.fromScalars(Text.parseNumbers(value))))))
    case "f" <> rest: IO.print(shown(Length.fromFields(fields(rest))))
    case _: IO.die(Unit, 1, "invalid length fixture")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        run(String.split(head, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
