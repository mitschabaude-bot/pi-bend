import Base

def classifyLoop(+value: String, names: List<&2, String>, +index: U32, +found: U32) -> U32:
  match names:
    case Nil{}: found
    case name <> rest: classifyLoop(value, rest, (index + 1 : U32), Bool.pick(U32, String.eq(value, name), index, found))

def classify(value: String) -> U32:
  classifyLoop(value, "response.created" <> "response.output_item.added" <> "response.reasoning_summary_text.delta" <> "response.reasoning_text.delta" <> "response.reasoning_summary_part.done" <> "response.output_text.delta" <> "response.refusal.delta" <> "response.function_call_arguments.delta" <> "response.function_call_arguments.done" <> "response.custom_tool_call_input.delta" <> "response.custom_tool_call_input.done" <> "response.output_item.done" <> "response.completed" <> "response.incomplete" <> "response.failed" <> "error" <> Nil{}, 1, 0)

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
