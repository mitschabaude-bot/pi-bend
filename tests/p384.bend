import Base
import ./p256.bend as Runner
import ../packages/runtime/src/ecdsa.bend as EC

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    Runner.arguments(EC.P384{},values)
