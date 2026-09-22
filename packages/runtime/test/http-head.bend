import Base
import ../src/http-message.bend as Head
import ../src/http-message.bend as H
import ../src/http-message.bend as Headers
import ../src/http-message.bend as Line
import ./http-status.bend as Status
import ./utf8-runner.bend as Text

def numbers(values: List<&2, U32>) -> String: String.join(Text.showNumbers(values), ",")

def fields(values: List<&2, H.Header>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case H.Header{name, value} <> rest: (Text.showText(name) ++ ":" ++ Text.showText(value)) <> fields(rest)

def strings(values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: Text.showText(value) <> strings(rest)

def shown(+head: Head.ResponseHead, rest: List<&2, U32>) -> String:
  match head:
    case Head.ResponseHead{+status, +raw}:
      +headers = Head.headersHead(Head.ResponseHead{status, raw})
      Status.shown(Done{status}) ++ "#" ++ String.join(fields(raw), "|") ++ "#" ++ String.join(fields(Headers.entries(headers)), "|") ++ "#" ++ String.join(strings(Headers.getSetCookie(headers)), "|") ++ "#" ++ numbers(rest)

def error(value: Head.ReadError) -> String:
  match value:
    case Head.HeadTooLong{}: "head-limit"
    case Head.TooManyFields{}: "field-limit"
    case Head.IncompleteHead{}: "incomplete"
    case Head.HeadFramingError{Line.LineTooLong{}}: "line-limit"
    case Head.HeadFramingError{_}: "framing"
    case Head.StatusError{_}: "status"
    case Head.HeadFieldError{_}: "field"

def stream(chunks: List<&2, String>, result: Head.HeadReadResult) -> String:
  match chunks result:
    case _ Head.HeadFailed{value}: error(value)
    case _ Head.HeadComplete{head, rest}: shown(head, rest)
    case Nil{} Head.HeadMore{_}: "incomplete"
    case head <> rest Head.HeadMore{reader}: stream(rest, Head.readHead(reader, Text.parseNumbers(head)))

def number(text: String) -> Nat: U32.to_nat(Text.decimal(text, 0))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case lineLimit <> headLimit <> fieldLimit <> chunks:
      IO.print(stream(chunks, Head.HeadMore{Head.newHead(number(lineLimit), number(headLimit), number(fieldLimit))}))
    case _: IO.die(Unit, 1, "invalid head fixture")

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
