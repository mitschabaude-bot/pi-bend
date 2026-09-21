import Base

# Ordinary string cases with a fallback that returns the original value.
# This retains the pattern reconstruction needed by provider error messages.
def classify(value: String) -> String:
  match value:
    case "completed": "1"
    case "incomplete": "2"
    case "failed": "3"
    case "cancelled": "4"
    case "in_progress": "5"
    case "queued": "6"
    case other: other

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(classify(head))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
