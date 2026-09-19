import Base

# BEND-001 reduced compilation-cost reproducer: six ordinary string patterns.
# No pi imports, callbacks, generics or large test-vector literals.
def classify(value: String) -> U32:
  match value:
    case "completed": 1
    case "incomplete": 2
    case "failed": 3
    case "cancelled": 4
    case "in_progress": 5
    case "queued": 6
    case _: 0

def main() -> IO(Unit):
  IO.print(U32.show(classify("completed")))
