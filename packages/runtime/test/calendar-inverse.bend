import Base
import ../src/calendar.bend as I
import ../src/calendar.bend as C
import ../src/u64.bend as W
import ./utf8-runner.bend as H

def shown(result: Result<&2, &2, I.Error, C.CivilTime>) -> String:
  match result:
    case Fail{I.OutOfRange{}}: "range"
    case Fail{I.ReconstructionMismatch{}}: "mismatch"
    case Done{C.CivilTime{year, month, day, hour, minute, second, millis}}:
      U32.show(year) ++ ":" ++ U32.show(month) ++ ":" ++ U32.show(day) ++ ":" ++ U32.show(hour) ++ ":" ++ U32.show(minute) ++ ":" ++ U32.show(second) ++ ":" ++ U32.show(millis)

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case high <> low <> Nil{}: IO.print(shown(I.fromEpochMilliseconds(W.U64{H.decimal(high, 0), H.decimal(low, 0)})))
    case _: IO.die(Unit, 1, "expected high and low epoch words")

def cases(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        run(String.split(first, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    cases(values)
