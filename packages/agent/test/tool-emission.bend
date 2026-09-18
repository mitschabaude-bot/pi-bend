import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as F
import ./message-events.bend as Test

def EventValue() -> Data: T.AgentEvent<Unit, String, Unit, String, String, Unit, T.AgentToolResult<String>>
def Outcome() -> Data: Result<&2, &2, String, Unit>
def Sink() -> Data: C.Callback<EventValue(), Outcome()>
type State is Data:
  State{log: R.Ref<List<&2, String>>, failAt: String}

def sink(state: State, event: EventValue()) -> IO(Outcome()):
  match state:
    case State{log, failAt}:
      do IO<Outcome()>:
        +tag : String = T.eventType(Unit, String, Unit, String, String, Unit, T.AgentToolResult<String>, event)
        R.modify(List<&2, String>, Unit, log, values => (tag <> values, Unit{}))
        return Bool.pick(Outcome(), String.eq(tag, failAt), Fail{tag}, Done{Unit{}})

def afterExecution(emitted: Outcome(), emit: Sink(), message: Ai.ToolResultMessage<String>) -> IO(Outcome()):
  match emitted:
    case Fail{error}: IO.pure(Outcome(), Fail{error})
    case Done{_}: Loop.emitToolResultMessage(Unit, String, Unit, String, String, Unit, T.AgentToolResult<String>, String, message, emit)

def check(result: Outcome(), expected: String) -> IO(Unit):
  match result:
    case Done{_}: Test.assertion(String.is_empty(expected), "emission failure was swallowed")
    case Fail{error}: Test.assertion(String.eq(error, expected), "wrong emission failure")

def run(+failAt: String, expectedTrace: String) -> IO(Unit):
  do IO<Unit>:
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +emit : Sink() <- C.create(~State, ~EventValue(), ~Outcome(), ~sink, State{log, failAt})
    finalized : Loop.FinalizedToolCallOutcome<String, String> = Loop.FinalizedToolCallOutcome{Ai.ToolCall{"id", "echo", "args", None{}, None{}}, T.AgentToolResult{Nil{}, "details", None{}, None{}}, False{}}
    result : Outcome() <- Loop.emitToolExecutionEnd(Unit, String, Unit, String, String, Unit, String, finalized, emit)
    outcome : Outcome() <- afterExecution(result, emit, Ai.ToolResultMessage{"id", "echo", Nil{}, Some{"details"}, None{}, False{}, F.fromU32(0)})
    check(outcome, failAt)
    trace : List<&2, String> <- R.read(List<&2, String>, log)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, trace), "|"), expectedTrace), "tool emission ordering/short-circuit changed")
    C.dispose(EventValue(), Outcome(), emit)
    discarded : List<&2, String> <- R.dispose(List<&2, String>, log)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    run("", "tool_execution_end|message_start|message_end")
    run("tool_execution_end", "tool_execution_end")
    run("message_start", "tool_execution_end|message_start")
    run("message_end", "tool_execution_end|message_start|message_end")
    IO.print("PASS awaited tool emission order and listener failure propagation")
