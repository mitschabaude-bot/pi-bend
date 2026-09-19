import Base
import ../src/utils/provider-retry-sleep.bend as S
import ../src/utils/provider-retry.bend as R
import ../../runtime/src/abort.bend as A
import ../../runtime/src/f64.bend as F

def expect(result: Result<&2, &2, Unit, Unit>, aborted: Bool) -> IO(Unit):
  match result aborted:
    case Done{_} False{}: IO.pure(Unit, Unit{})
    case Fail{_} True{}: IO.pure(Unit, Unit{})
    case _ _: IO.die(Unit, 1, "wrong provider sleep result")

def main() -> IO(Unit):
  do IO<Unit>:
    bare : Result<&2, &2, Unit, Unit> <- S.sleep(String, R.SleepInput{F.fromU32(0), None{}})
    expect(bare, False{})
    +controller : A.AbortController<String> <- A.new(String)
    normal : Result<&2, &2, Unit, Unit> <- S.sleep(String, R.SleepInput{F.nan(), Some{A.signal(String, controller)}})
    expect(normal, False{})
    changed : Bool <- A.abort(String, controller, None{})
    aborted : Result<&2, &2, Unit, Unit> <- S.sleep(String, R.SleepInput{F.fromU32(60000), Some{A.signal(String, controller)}})
    expect(aborted, True{})
    A.dispose(String, controller)
    IO.print("PASS provider sleep")
