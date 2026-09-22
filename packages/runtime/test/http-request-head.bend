import Base
import ../src/http-message.bend as Request
import ../src/http-message.bend as H
import ./utf8-runner.bend as Text

def headers(parts: List<&2, String>) -> List<&2, H.Header>:
  match parts:
    case name <> value <> rest: H.Header{Text.fromScalars(Text.parseNumbers(name)), Text.fromScalars(Text.parseNumbers(value))} <> headers(rest)
    case _: Nil{}

def show(result: Result<&2, &2, Request.RequestHeadError, Request.Head>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{Request.Head{method, bytes}}: Text.showText(method) ++ ";" ++ String.join(Text.showNumbers(bytes), ",")

def run(parts: List<&2, String>) -> String:
  match parts:
    case method <> target <> fields: show(Request.encodeRequestHead(Text.fromScalars(Text.parseNumbers(method)), Text.fromScalars(Text.parseNumbers(target)), headers(fields)))
    case _: "invalid-fixture"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print(run(String.split(first, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
