import Base
import ../src/calendar.bend as C
import ../src/u64.bend as W
import ./utf8-runner.bend as H

def shown(result: Result<&2, &2, C.CalendarError, W.U64>) -> String:
  match result:
    case Done{W.U64{high, low}}: U32.show(high) ++ ":" ++ U32.show(low)
    case Fail{C.InvalidYear{}}: "year"
    case Fail{C.InvalidMonth{}}: "month"
    case Fail{C.InvalidDay{}}: "day"
    case Fail{C.InvalidTime{}}: "time"

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case year <> month <> day <> hour <> minute <> second <> millis <> Nil{}:
      IO.print(shown(C.toEpochMilliseconds(C.CivilTime{H.decimal(year, 0), H.decimal(month, 0), H.decimal(day, 0), H.decimal(hour, 0), H.decimal(minute, 0), H.decimal(second, 0), H.decimal(millis, 0)})))
    case _: IO.die(Unit, 1, "expected civil time fields")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        run(String.split(value, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
