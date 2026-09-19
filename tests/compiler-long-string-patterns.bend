import Base

# BEND-016: long string cases lower into deeply nested per-bit tests.
def classify(value: String) -> U32:
  match value:
    case "response.created": 1
    case "response.output_item.added": 2
    case "response.reasoning_summary_text.delta": 3
    case "response.reasoning_text.delta": 4
    case "response.reasoning_summary_part.done": 5
    case "response.output_text.delta": 6
    case "response.refusal.delta": 7
    case "response.function_call_arguments.delta": 8
    case "response.function_call_arguments.done": 9
    case "response.custom_tool_call_input.delta": 10
    case "response.custom_tool_call_input.done": 11
    case "response.output_item.done": 12
    case "response.completed": 13
    case "response.incomplete": 14
    case "response.failed": 15
    case "error": 16
    case _: 0

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(U32.show(classify(head)))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
