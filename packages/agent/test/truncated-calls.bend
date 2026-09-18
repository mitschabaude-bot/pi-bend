import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ./message-events.bend as Test

def Details() -> Data: Record.Record<Unit>
def EventValue() -> Data: T.AgentEvent<Unit, String, Unit, Details(), String, Unit, T.AgentToolResult<Details()>>
def BatchResult() -> Data: Result<&2, &2, String, Loop.ExecutedToolCallBatch<Details()>>
type State is Data:
  State{log: R.Ref<List<&2, String>>, failAt: String}

def tag(event: EventValue()) -> String:
  match event:
    case T.ToolExecutionStart{id, _, _}: "start:" ++ id
    case T.ToolExecutionEnd{id, _, _, _}: "end:" ++ id
    case T.MessageStart{T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id, _, _, _, _, _, _}}}}: "message_start:" ++ id
    case T.MessageEnd{T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id, _, _, _, _, _, _}}}}: "message_end:" ++ id
    case _: "unexpected"

def sink(state: State, event: EventValue()) -> IO(Result<&2, &2, String, Unit>):
  match state:
    case State{log, failAt}:
      do IO<Result<&2, &2, String, Unit>>:
        +name : String = tag(event)
        R.modify(List<&2, String>, Unit, log, values => (name <> values, Unit{}))
        return Bool.pick(Result<&2, &2, String, Unit>, String.eq(name, failAt), Fail{name}, Done{Unit{}})

def validMessage(value: Ai.ToolResultMessage<Details()>, expected: String) -> Bool:
  match value:
    case Ai.ToolResultMessage{id, name, Ai.TextImageText{Ai.TextContent{text, _}} <> Nil{}, Some{Record.Record{Nil{}}}, None{}, True{}, _}:
      String.eq(id, expected) && String.eq(name, "echo") && String.eq(text, "Tool call \"echo\" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments.")
    case _: False{}

def check(result: BatchResult(), expectedError: String) -> IO(Unit):
  match result:
    case Fail{error}: Test.assertion(String.eq(error, expectedError), "truncated-call listener failure must propagate")
    case Done{Loop.ExecutedToolCallBatch{a <> b <> Nil{}, False{}}}: Test.assertion(String.is_empty(expectedError) && validMessage(a, "a") && validMessage(b, "b"), "truncated calls must return ordered error messages without terminating")
    case _: Test.assertion(False{}, "truncated result batch shape")

def run(+failAt: String, expectedTrace: String) -> IO(Unit):
  do IO<Unit>:
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +emit : C.Callback<EventValue(), Result<&2, &2, String, Unit>> <- C.create(~State, ~EventValue(), ~Result<&2, &2, String, Unit>, ~sink, State{log, failAt})
    result : BatchResult() <- Loop.failToolCallsFromTruncatedMessage(Unit, String, Unit, String, Unit, String, Unit, Loop.TruncatedToolCallRun{emit}, Ai.ToolCall{"a", "echo", "incomplete", None{}, None{}} <> Ai.ToolCall{"b", "echo", "incomplete", None{}, None{}} <> Nil{})
    check(result, failAt)
    trace : List<&2, String> <- R.read(List<&2, String>, log)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, trace), "|"), expectedTrace), "truncated-call events must be awaited in order and stop on failure")
    C.dispose(EventValue(), Result<&2, &2, String, Unit>, emit)
    discarded : List<&2, String> <- R.dispose(List<&2, String>, log)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    run("", "start:a|end:a|message_start:a|message_end:a|start:b|end:b|message_start:b|message_end:b")
    run("start:a", "start:a")
    run("end:a", "start:a|end:a")
    run("message_start:a", "start:a|end:a|message_start:a")
    run("message_end:a", "start:a|end:a|message_start:a|message_end:a")
    run("start:b", "start:a|end:a|message_start:a|message_end:a|start:b")
    IO.print("PASS native truncated-call batches, error artifacts and ordered failure propagation")
