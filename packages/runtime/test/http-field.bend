import Base
import ../src/http-field.bend as Field
import ../src/http-header.bend as H
import ./utf8-runner.bend as Text

def shown(result: Result<&2, &2, Field.FieldError, Field.FieldLine>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{Field.EndOfHeaders{}}: "end"
    case Done{Field.Field{H.Header{name, value}}}: Text.showText(name) ++ ";" ++ Text.showText(value)

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(shown(Field.parse(Text.parseNumbers(head))))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
