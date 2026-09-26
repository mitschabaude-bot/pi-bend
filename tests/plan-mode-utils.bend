import Base
import ../packages/coding-agent/examples/extensions/plan-mode/utils.bend as Plan
import ../packages/runtime/src/json.bend as Decode

# examples/extensions/plan-mode/utils.ts: prints each helper's result for the
# input lines on standard arguments (<function> <input>...) as JSON lines.
def items(values: List<&2, Plan.TodoItem>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case Plan.TodoItem{step, text, completed} <> rest: ("{\"step\":" ++ Nat.show(step) ++ ",\"text\":" ++ Decode.quote(text) ++ ",\"completed\":" ++ Bool.pick(String, completed, "true", "false") ++ "}") <> items(rest)

def numbers(values: List<&2, Nat>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: Nat.show(value) <> numbers(rest)

def todo(+step: Nat, +completed: String) -> Plan.TodoItem: Plan.TodoItem{step, "Step", String.eq(completed, "1")}

def parsedItem(fields: List<&2, String>) -> Plan.TodoItem:
  match fields:
    case step <> completed <> _: todo(Plan.digitsValue(step, 0n), completed)
    case _: todo(0n, "0")

# markCompletedSteps' items: "<step>:<completed 0|1>" pairs, comma separated.
def parsedItems(parts: List<&2, String>) -> List<&2, Plan.TodoItem>:
  match parts:
    case Nil{}: Nil{}
    case part <> rest: parsedItem(String.split(part, ':')) <> parsedItems(rest)

def completedFlags(values: List<&2, Plan.TodoItem>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case Plan.TodoItem{_, _, completed} <> rest: Bool.pick(String, completed, "true", "false") <> completedFlags(rest)

def marked(pair: List<&2, Plan.TodoItem> & Nat) -> String:
  match pair:
    case (values, count): "{\"count\":" ++ Nat.show(count) ++ ",\"completed\":[" ++ String.join(completedFlags(values), ",") ++ "]}"

def result(function: String, +input: String, extra: String) -> String:
  match function:
    case "isSafeCommand": Bool.pick(String, Plan.isSafeCommand(input), "true", "false")
    case "cleanStepText": Decode.quote(Plan.cleanStepText(input))
    case "extractTodoItems": "[" ++ String.join(items(Plan.extractTodoItems(input)), ",") ++ "]"
    case "extractDoneSteps": "[" ++ String.join(numbers(Plan.extractDoneSteps(input)), ",") ++ "]"
    case _: marked(Plan.markCompletedSteps(input, parsedItems(String.split(extra, ','))))

def run(args: List<String>) -> IO(Unit):
  match args:
    case function <> input <> extra <> Nil{}: IO.print(result(function, input, extra))
    case function <> input <> Nil{}: IO.print(result(function, input, ""))
    case _: IO.die(Unit, 1, "usage: plan-mode-utils <function> <input> [items]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
