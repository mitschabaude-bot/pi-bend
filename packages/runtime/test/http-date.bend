import Base
import ../src/http-message.bend as D
import ../../ai/src/utils/provider-retry.bend as P
import ../src/f64.bend as F
import ../src/u64.bend as W
import ../src/callback.bend as Callback
import ../src/http-message.bend as S
import ../src/calendar.bend as C
import ./utf8-runner.bend as H

def words(value: W.U64) -> String:
  match value:
    case W.U64{high, low}: U32.show(high) ++ ":" ++ U32.show(low)

def show(result: Result<&2, &2, D.Error, D.Instant>) -> String:
  match result:
    case Done{D.Ordinary{epoch}}: "ordinary:" ++ words(epoch)
    case Done{D.LeapSecond{epoch}}: "leap:" ++ words(epoch)
    case Fail{D.InvalidSyntax{}}: "syntax"
    case Fail{D.YearFailure{_}}: "year"
    case Fail{D.CalendarFailure{_}}: "calendar"
    case Fail{D.WeekdayMismatch{}}: "weekday"
    case Fail{D.InvalidLeapPosition{}}: "leap-position"

def numeric(text: String, reference: Result<&2, &2, C.CalendarError, W.U64>) -> String:
  match reference:
    case Fail{_}: "reference"
    case Done{epoch}: words(F.toBits(P.parseDateAt(epoch, text)))

def parsed(+reference: C.CivilTime, +text: String) -> String:
  show(D.parseAt(reference, text)) ++ "#" ++ numeric(text, C.toEpochMilliseconds(reference))

def run(parts: List<&2, String>) -> String:
  match parts:
    case year <> month <> day <> hour <> minute <> second <> date <> Nil{}:
      parsed(C.CivilTime{H.decimal(year, 0), H.decimal(month, 0), H.decimal(day, 0), H.decimal(hour, 0), H.decimal(minute, 0), H.decimal(second, 0), 0}, date)
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
    +callback : Callback.Callback<String, F64> <- P.dateParser()
    value : F64 <- Callback.call(String, F64, callback, "Sun, 06 Nov 1994 08:49:37 GMT")
    IO.print("callback:" ++ words(F.toBits(value)))
    values : List<String> <- IO.args()
    cases(values)
    Callback.dispose(String, F64, callback)
