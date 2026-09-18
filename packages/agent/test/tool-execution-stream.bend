import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../src/event-emission.bend as E
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as S
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./message-events.bend as Test
import ./tool-execution.bend as Execute
import ./tool-finalization.bend as Finalize
import ./turn-update.bend as ConfigTest
import ./context.bend as H

def ResultValue() -> Data: T.AgentToolResult<String>
def EventValue() -> Data: Execute.EventValue()
def Emitted() -> Data: Result<&2, &2, String, Unit>
def StreamValue() -> Data: Loop.AgentEventStream(Unit, String, Unit, String, String, ResultValue(), ResultValue())
def Emitter() -> Data: C.Callback<EventValue(), E.Emission<String>>
def Sink() -> Data: C.Callback<EventValue(), Emitted()>

def execute(unused: Unit, input: Execute.Input()) -> IO(Execute.Output()):
  match input:
    case T.ToolExecutionInput{_, _, _, Some{callback}}:
      do IO<Execute.Output()>:
        Execute.update(callback, "progress")
        return Done{Execute.partial("done")}
    case _: IO.die(Execute.Output(), 1, "missing update callback")

def after(unused: Unit, input: Finalize.Input()) -> IO(Finalize.Output()):
  match input:
    case T.ToolHookInput{T.AfterToolCallContext{_, _, args, T.AgentToolResult{_, details, _, _}, False{}, _}, _}:
      do IO<Finalize.Output()>:
        Test.assertion(U32.is_eq(args, 123) && String.eq(details, "done"), "after hook lost actual execution result")
        return Done{Some{T.AfterToolCallResult{None{}, None{}, None{}, None{}, Some{True{}}}}}
    case _: IO.die(Finalize.Output(), 1, "after hook execution input differs")

def executed(value: Execute.Outcome()) -> IO(Loop.ExecutedToolCallOutcome<String>):
  match value:
    case Done{result}: IO.pure(Loop.ExecutedToolCallOutcome<String>, result)
    case Fail{_}: IO.die(Loop.ExecutedToolCallOutcome<String>, 1, "stream emitter unexpectedly failed")

def emitted(value: Emitted()) -> IO(Unit):
  match value:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: Test.assertion(False{}, "agent stream delivery failed")

def next(value: S.Iteration<EventValue()>, expected: String) -> IO(Unit):
  match value:
    case S.Yield{event}: Test.assertion(String.eq(T.eventType(Unit, String, Unit, String, String, ResultValue(), ResultValue(), event), expected), "composed tool pipeline event order")
    case S.End{}: Test.assertion(String.eq(expected, "end"), "composed pipeline ended early")

def drain(expected: List<&2, String>, +iterator: S.Iterator<EventValue(), H.Messages()>) -> IO(Unit):
  match expected:
    case Nil{}: IO.pure(Unit, Unit{})
    case tag <> rest:
      do IO<Unit>:
        event : S.Iteration<EventValue()> <- S.nextValue(EventValue(), H.Messages(), iterator)
        next(event, tag)
        drain(rest, iterator)

def finalMessages(values: H.Messages()) -> IO(Unit):
  match values:
    case T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id, name, _, Some{details}, _, False{}, _}}} <> Nil{}:
      Test.assertion(String.eq(id, "call") && String.eq(name, "echo") && String.eq(details, "done"), "agent stream final tool result differs")
    case _: Test.assertion(False{}, "agent stream final history shape")

def main() -> IO(Unit):
  do IO<Unit>:
    +stream : StreamValue() <- Loop.createAgentStream(~Unit, ~String, ~Unit, ~String, ~String, ~ResultValue(), ~ResultValue())
    +iterator : S.Iterator<EventValue(), H.Messages()> <- S.iterator(EventValue(), H.Messages(), stream)
    +emitter : Emitter() <- Loop.createAgentStreamEmitter(~Unit, ~String, ~Unit, ~String, ~String, ~ResultValue(), ~ResultValue(), ~String, stream)
    +sink : Sink() <- Loop.createAwaitedEventSink(~Unit, ~String, ~Unit, ~String, ~String, ~ResultValue(), ~ResultValue(), ~String, emitter)
    +executor : C.Callback<Execute.Input(), Execute.Output()> <- C.create(~Unit, ~Execute.Input(), ~Execute.Output(), ~execute, Unit{})
    +hook : Finalize.Hook() <- C.create(~Unit, ~Finalize.Input(), ~Finalize.Output(), ~after, Unit{})
    +converter : ConfigTest.Converter() <- C.create(~Unit, ~H.Messages(), ~ConfigTest.Output(), ~ConfigTest.forbidden, Unit{})
    +call : Ai.ToolCall<String> = Ai.ToolCall{"call", "echo", "raw", None{}, None{}}
    +updates : Loop.ToolUpdateRun<String, String> <- Loop.createToolUpdateRun(~Unit, ~String, ~Unit, ~String, ~String, ~String, call, emitter)
    +prepared : Loop.PreparedToolCall<Unit, U32, String, String, Unit, String> = Loop.PreparedToolCall{call, T.AgentTool{"echo", "", Unit{}, None{}, "", None{}, executor, None{}, None{}}, 123}
    started : Emitted() <- C.call(EventValue(), Emitted(), sink, T.ToolExecutionStart{"call", "echo", "raw"})
    emitted(started)
    outcome : Execute.Outcome() <- Loop.executePreparedToolCall(Unit, U32, String, String, Unit, String, prepared, Some{Unit{}}, updates, "empty details", error => error)
    result : Loop.ExecutedToolCallOutcome<String> <- executed(outcome)
    +zero : F.F64 = F.fromU32(0)
    assistant : Ai.AssistantMessage<String, Unit> = Test.assistant(Nil{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.ToolUse{})
    +finalized : Loop.FinalizedToolCallOutcome<String, String> <- Loop.finalizeExecutedToolCall(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, T.AgentContext{Nil{}, None{}}, assistant, prepared, result, Finalize.configuration(converter, Some{hook}), Some{Unit{}}, "empty details", error => error)
    Test.assertion(Loop.shouldTerminateToolBatch(String, String, finalized <> Nil{}), "after hook termination must affect batch policy")
    ended : Emitted() <- Loop.emitToolExecutionEnd(Unit, String, Unit, String, String, ResultValue(), String, finalized, sink)
    emitted(ended)
    +message : Ai.ToolResultMessage<String> <- Loop.createToolResultMessage(String, String, finalized)
    delivered : Emitted() <- Loop.emitToolResultMessage(Unit, String, Unit, String, String, ResultValue(), ResultValue(), String, message, sink)
    emitted(delivered)
    completed : Emitted() <- C.call(EventValue(), Emitted(), sink, T.AgentEnd{T.LlmMessage{Ai.ToolResult{message}} <> Nil{}})
    emitted(completed)
    values : H.Messages() <- S.resultValue(EventValue(), H.Messages(), stream)
    finalMessages(values)
    drain("tool_execution_start" <> "tool_execution_update" <> "tool_execution_end" <> "message_start" <> "message_end" <> "agent_end" <> "end" <> Nil{}, iterator)
    Loop.disposeToolUpdateRun(String, String, updates)
    C.dispose(Execute.Input(), Execute.Output(), executor)
    C.dispose(Finalize.Input(), Finalize.Output(), hook)
    C.dispose(H.Messages(), ConfigTest.Output(), converter)
    C.dispose(EventValue(), Emitted(), sink)
    C.dispose(EventValue(), E.Emission<String>, emitter)
    S.disposeIterator(EventValue(), H.Messages(), iterator)
    Loop.disposeAgentStream(Unit, String, Unit, String, String, ResultValue(), ResultValue(), stream)
    IO.print("PASS composed tool execution, progress, after-hook termination, result messages and canonical agent stream")
