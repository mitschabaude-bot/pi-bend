import Base
import ../src/http-status.bend as Status
import ../src/http-line.bend as Line
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

def stream(chunks: List<&2, String>, result: Status.ReadResult) -> String:
  match chunks result:
    case _ Status.Failed{_}: "error"
    case _ Status.Complete{value, rest}: shown(Done{value}) ++ ";" ++ String.join(Text.showNumbers(rest), ",")
    case Nil{} Status.More{_}: "incomplete"
    case head <> tail Status.More{reader}: stream(tail, Status.read(reader, Text.parseNumbers(head)))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "f" <> bytes <> Nil{}: IO.print(fetched(Status.parse(Text.parseNumbers(bytes))))
    case "p" <> bytes <> Nil{}: IO.print(shown(Status.parse(Text.parseNumbers(bytes))))
    case "s" <> chunks: IO.print(stream(chunks, Status.More{Line.new(1024n)}))
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
