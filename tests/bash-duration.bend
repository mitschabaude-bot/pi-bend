import Base
import ../packages/coding-agent/src/core/tools/renderers/bash.bend as Bash
import ../packages/runtime/src/f64.bend as F

def check(+ms: U32,want: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),String.eq(Bash.duration(F.fromU32(ms)),want),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"wrong bash duration at " ++ U32.show(ms) ++ "ms"))(Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    check(59540,"59.5s")
    check(59960,"60.0s")
    check(60000,"1m 0s")
    check(119960,"1m 59s")
    check(3600000,"1h 0m 0s")
