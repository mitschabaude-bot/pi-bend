import Base
import ../packages/runtime/test/utf8-runner.bend as Text

# Intentional negative reproducer: the former showText path used this non-tail
# helper. Production authority parsing is not involved.
def grow(count: Nat, values: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: values
    case Succ{rest}: grow(rest, 37 <> values)

def observed(values: List<&2, String>) -> String:
  match values:
    case Nil{}: "empty"
    case _ <> _: "formatted"

def main() -> IO(Unit):
  IO.print(observed(Text.showNumbers(grow(65536n, Nil{}))))
