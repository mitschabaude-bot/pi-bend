import Base
import ../src/http-date-syntax.bend as S

def format(value: S.Format) -> String:
  match value:
    case S.ImfFixdate{}: "imf"
    case S.Rfc850{}: "850"
    case S.Asctime{}: "asc"

def clock(value: S.ClockFields) -> String:
  match value:
    case S.ClockFields{h, m, s}: U32.show(h) ++ ":" ++ U32.show(m) ++ ":" ++ U32.show(s)

def shown(value: Maybe<&2, S.DateFields>) -> String:
  match value:
    case None{}: "unrecognized"
    case Some{S.DateFields{kind, w, y, m, d, t}}:
      format(kind) ++ ":" ++ U32.show(w) ++ ":" ++ U32.show(y) ++ ":" ++ U32.show(m) ++ ":" ++ U32.show(d) ++ ":" ++ clock(t)

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        IO.print(shown(S.parse(text)))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
