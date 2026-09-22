import Base
import ../src/http-message.bend as Y
import ../src/http-message.bend as S
import ../src/calendar.bend as C
import ./utf8-runner.bend as H

def show(result: Result<&2, &2, Y.DateYearError, U32>) -> String:
  match result:
    case Done{year}: U32.show(year)
    case Fail{Y.InvalidShortYear{}}: "short-year"
    case Fail{Y.InvalidReference{_}}: "reference"
    case Fail{Y.OutsideCalendar{}}: "range"

def parsed(reference: C.CivilTime, fields: Maybe<&2, S.DateFields>) -> String:
  match fields:
    case None{}: "syntax"
    case Some{date}: show(Y.resolve(reference, date))

def run(parts: List<&2, String>) -> String:
  match parts:
    case year <> month <> day <> hour <> minute <> second <> date <> Nil{}:
      parsed(C.CivilTime{H.decimal(year, 0), H.decimal(month, 0), H.decimal(day, 0), H.decimal(hour, 0), H.decimal(minute, 0), H.decimal(second, 0), 0}, S.parseDateSyntax(date))
    case _: "arguments"

def cases(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print(run(String.split(first, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    cases(values)
