import Base
import ../src/http-message.bend as H
import ./utf8-runner.bend as T

def shown(result: Result<&2, &2, H.HeaderSyntaxError, H.Header>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{H.Header{name, value}}: "ok:" ++ T.showText(name) ++ ";" ++ T.showText(value)

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case name <> value <> Nil{}:
      IO.print(shown(H.normalize(T.fromScalars(T.parseNumbers(name)), T.fromScalars(T.parseNumbers(value)))))
    case _: IO.die(Unit, 1, "expected header name and value")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        run(String.split(text, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
