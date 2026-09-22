import Base
import ../src/http-message.bend as Status
import ../src/http-message.bend as Line
import ./utf8-runner.bend as Text

def shown(value: Result<&2, &2, Status.SyntaxError, Status.StatusLine>) -> String:
  match value:
    case Fail{_}: "error"
    case Done{Status.StatusLine{major, minor, code, reason}}:
      U32.show(major) ++ "." ++ U32.show(minor) ++ ":" ++ U32.show(code) ++ ":" ++ String.join(Text.showNumbers(reason), ",")

def fetched(value: Result<&2, &2, Status.SyntaxError, Status.StatusLine>) -> String:
  match value:
    case Fail{_}: "error"
    case Done{+line}: Text.showText(Status.statusText(line))

def stream(chunks: List<&2, String>, result: Status.StatusReadResult) -> String:
  match chunks result:
    case _ Status.StatusFailed{_}: "error"
    case _ Status.StatusComplete{value, rest}: shown(Done{value}) ++ ";" ++ String.join(Text.showNumbers(rest), ",")
    case Nil{} Status.StatusMore{_}: "incomplete"
    case head <> tail Status.StatusMore{reader}: stream(tail, Status.readStatus(reader, Text.parseNumbers(head)))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "f" <> bytes <> Nil{}: IO.print(fetched(Status.parseStatus(Text.parseNumbers(bytes))))
    case "p" <> bytes <> Nil{}: IO.print(shown(Status.parseStatus(Text.parseNumbers(bytes))))
    case "s" <> chunks: IO.print(stream(chunks, Status.StatusMore{Line.newLine(1024n)}))
    case _: IO.die(Unit, 1, "invalid status fixture")

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
