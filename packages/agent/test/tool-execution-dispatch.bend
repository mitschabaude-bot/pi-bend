import Base
import ../../ai/test/model-types.bend as Model
import ../src/agent-loop.bend as Call
import ../src/agent-loop.bend as Execution
import ../src/agent-loop.bend as Batch
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../src/agent-loop.bend as E
import ../../ai/src/types.bend as Ai
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./validated-tool-execution.bend as H
import ./message-events.bend as Test

import ./tool-call-sequential.bend as S

def content(empty: Bool) -> List<&2, Ai.AssistantContent<V.Value>>:
  match empty:
    case True{}: Ai.AssistantText{Ai.TextContent{"no tools", None{}}} <> Nil{}
    case False{}:
      Ai.AssistantText{Ai.TextContent{"before", None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"call", "echo", H.field(V.Text{"42"}), None{}, None{}}} <> Ai.AssistantText{Ai.TextContent{"between", None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"bad", "badtool", H.field(V.Text{"bad"}), None{}, None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"missing", "absent", H.field(V.Text{"42"}), None{}, None{}}} <> Nil{}

def configuration(mode: Maybe<&2, T.ToolExecutionMode>, converter: C.Callback<H.Messages(), H.Converted()>, beforeHook: C.Callback<S.BeforeInput(), S.BeforeOutput()>, hook: C.Callback<S.AfterInput(), S.AfterOutput()>) -> H.Config():
  T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"custom"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, mode, Some{beforeHook}, Some{hook}}

def expectedEvents(empty: Bool, sequential: Bool) -> List<&2, String>:
  match empty sequential:
    case True{} _: Nil{}
    case False{} True{}: "start:call" <> "update:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "start:bad" <> "end:bad" <> "message_start:bad" <> "message_end:bad" <> "start:missing" <> "end:missing" <> "message_start:missing" <> "message_end:missing" <> Nil{}
    case False{} False{}: "start:call" <> "start:bad" <> "end:bad" <> "start:missing" <> "end:missing" <> "update:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "message_start:bad" <> "message_end:bad" <> "message_start:missing" <> "message_end:missing" <> Nil{}

def throughFailure(+failure: String, events: List<&2, String>) -> List<&2, String>:
  match events:
    case Nil{}: Nil{}
    case +event <> rest: event <> Bool.pick(List<&2, String>, String.eq(event, failure), Nil{}, throughFailure(failure, rest))

def scenario(+failAt: String, configured: Maybe<&2, T.ToolExecutionMode>, toolMode: Maybe<&2, T.ToolExecutionMode>, lateMode: Maybe<&2, T.ToolExecutionMode>, +empty: Bool, sequential: Bool) -> IO(Unit):
  do IO<Unit>:
    +events : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +signal : R.Ref<Bool> <- R.new(Bool, False{})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +hooks : R.Ref<U32> <- R.new(U32, 0)
    +retained : R.Ref<Maybe<&2, S.Update()>> <- R.new(Maybe<&2, S.Update()>, None{})
    +executor : C.Callback<H.ExecuteInput(), H.ExecuteOutput()> <- C.create(~S.Execution, ~H.ExecuteInput(), ~H.ExecuteOutput(), ~S.execute, S.Execution{calls, retained})
    +validator : C.Callback<H.Input(), H.Checked()> <- C.create(~Unit, ~H.Input(), ~H.Checked(), ~H.validate, Unit{})
    +converter : C.Callback<H.Messages(), H.Converted()> <- C.create(~Unit, ~H.Messages(), ~H.Converted(), ~H.convert, Unit{})
    +beforeHook : C.Callback<S.BeforeInput(), S.BeforeOutput()> <- C.create(~Bool, ~S.BeforeInput(), ~S.BeforeOutput(), ~S.before, False{})
    +hook : C.Callback<S.AfterInput(), S.AfterOutput()> <- C.create(~R.Ref<U32>, ~S.AfterInput(), ~S.AfterOutput(), ~S.after, hooks)
    +abort : C.Callback<Maybe<&2, Unit>, Bool> <- C.create(~R.Ref<Bool>, ~Maybe<&2, Unit>, ~Bool, ~S.aborted, signal)
    +emitter : C.Callback<H.EventValue(), E.Emission<String>> <- C.create(~S.Recording, ~H.EventValue(), ~E.Emission<String>, ~S.emit, S.Recording{events, failAt, False{}, signal})
    +sink : C.Callback<H.EventValue(), Result<&2, &2, String, Unit>> <- Loop.createAwaitedEventSink(~V.Value, ~V.Value, ~Unit, ~String, ~String, ~T.AgentToolResult<String>, ~T.AgentToolResult<String>, ~String, emitter)
    +owners : Call.Owners(String, String) <- Call.newOwners(String, String)
    +schema : V.Value = V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", H.field(V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"number"}} <> Nil{}}})} <> Record.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}
    context : H.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "", schema, None{}, "Echo", None{}, executor, None{}, toolMode} <> T.AgentTool{"echo", "", schema, None{}, "Duplicate", None{}, executor, None{}, Some{T.Sequential{}}} <> T.AgentTool{"badtool", "", schema, None{}, "Bad", None{}, executor, None{}, lateMode} <> T.AgentTool{"unused", "", schema, None{}, "Unused", None{}, executor, None{}, Some{T.Sequential{}}} <> Nil{}}}
    +zero : F.F64 = F.fromU32(0)
    assistant : Ai.AssistantMessage<V.Value, Unit> = Ai.AssistantMessage{content(empty), "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.ToolUse{}, None{}, None{}, None{}, None{}, zero}
    capture : Call.CallCapture<V.Value, V.Value, Unit, String, String, V.Value, Unit, String, Unit, Unit, Unit> = Call.CallCapture{assistant, configuration(configured, converter, beforeHook, hook), Some{Unit{}}, validator, abort, emitter, sink, owners, "empty"}
    +execution : Execution.Execution<V.Value, V.Value, Unit, String, String, V.Value, Unit, String> <- Execution.executeToolCalls(~V.Value, ~V.Value, ~Unit, ~String, ~String, ~V.Value, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~S.render, capture, context)
    result : S.Outcome() <- Execution.resultExecution(V.Value, V.Value, Unit, String, String, V.Value, Unit, String, execution)
    Execution.disposeExecution(V.Value, V.Value, Unit, String, String, V.Value, Unit, String, execution)
    S.checkOutcome(result, Bool.not(String.is_empty(failAt)), Bool.not(empty), Bool.pick(List<&2, Bool>, empty, Nil{}, False{} <> True{} <> True{} <> Nil{}), False{})
    saved : Maybe<&2, S.Update()> <- R.read(Maybe<&2, S.Update()>, retained)
    S.late(saved)
    recorded : List<&2, String> <- R.read(List<&2, String>, events)
    Test.assertion(S.equal(List.reverse(&2, String, recorded), throughFailure(failAt, expectedEvents(empty, sequential))), "canonical lifecycle event ordering; retained updates are inactive")
    actualCalls : U32 <- R.read(U32, calls)
    actualHooks : U32 <- R.read(U32, hooks)
    Test.assertion(U32.is_eq(actualCalls, Bool.pick(U32, empty || String.eq(failAt, "start:call"), 0, 1)) && U32.is_eq(actualHooks, Bool.pick(U32, empty || String.eq(failAt, "start:call") || String.eq(failAt, "update:call"), 0, 1)), "lifecycle execution and hook counts")
    C.dispose(H.ExecuteInput(), H.ExecuteOutput(), executor)
    saved : Maybe<&2, S.Update()> <- R.dispose(Maybe<&2, S.Update()>, retained)
    Call.disposeOwners(String, String, owners)
    C.dispose(H.Input(), H.Checked(), validator)
    C.dispose(H.Messages(), H.Converted(), converter)
    C.dispose(S.BeforeInput(), S.BeforeOutput(), beforeHook)
    C.dispose(S.AfterInput(), S.AfterOutput(), hook)
    C.dispose(Maybe<&2, Unit>, Bool, abort)
    C.dispose(H.EventValue(), Result<&2, &2, String, Unit>, sink)
    C.dispose(H.EventValue(), E.Emission<String>, emitter)
    dropped : List<&2, String> <- R.dispose(List<&2, String>, events)
    dropped : Bool <- R.dispose(Bool, signal)
    dropped : U32 <- R.dispose(U32, calls)
    dropped : U32 <- R.dispose(U32, hooks)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    scenario("", None{}, None{}, None{}, False{}, False{})
    scenario("", None{}, None{}, Some{T.Sequential{}}, False{}, True{})
    scenario("", None{}, None{}, Some{T.Parallel{}}, False{}, False{})
    scenario("", None{}, Some{T.Sequential{}}, None{}, False{}, True{})
    scenario("", None{}, Some{T.Sequential{}}, Some{T.Sequential{}}, False{}, True{})
    scenario("", None{}, Some{T.Sequential{}}, Some{T.Parallel{}}, False{}, True{})
    scenario("", None{}, Some{T.Parallel{}}, None{}, False{}, False{})
    scenario("", None{}, Some{T.Parallel{}}, Some{T.Sequential{}}, False{}, True{})
    scenario("", None{}, Some{T.Parallel{}}, Some{T.Parallel{}}, False{}, False{})
    scenario("", Some{T.Sequential{}}, None{}, None{}, False{}, True{})
    scenario("", Some{T.Sequential{}}, None{}, Some{T.Sequential{}}, False{}, True{})
    scenario("", Some{T.Sequential{}}, None{}, Some{T.Parallel{}}, False{}, True{})
    scenario("", Some{T.Sequential{}}, Some{T.Sequential{}}, None{}, False{}, True{})
    scenario("", Some{T.Sequential{}}, Some{T.Sequential{}}, Some{T.Sequential{}}, False{}, True{})
    scenario("", Some{T.Sequential{}}, Some{T.Sequential{}}, Some{T.Parallel{}}, False{}, True{})
    scenario("", Some{T.Sequential{}}, Some{T.Parallel{}}, None{}, False{}, True{})
    scenario("", Some{T.Sequential{}}, Some{T.Parallel{}}, Some{T.Sequential{}}, False{}, True{})
    scenario("", Some{T.Sequential{}}, Some{T.Parallel{}}, Some{T.Parallel{}}, False{}, True{})
    scenario("", Some{T.Parallel{}}, None{}, None{}, False{}, False{})
    scenario("", Some{T.Parallel{}}, None{}, Some{T.Sequential{}}, False{}, True{})
    scenario("", Some{T.Parallel{}}, None{}, Some{T.Parallel{}}, False{}, False{})
    scenario("", Some{T.Parallel{}}, Some{T.Sequential{}}, None{}, False{}, True{})
    scenario("", Some{T.Parallel{}}, Some{T.Sequential{}}, Some{T.Sequential{}}, False{}, True{})
    scenario("", Some{T.Parallel{}}, Some{T.Sequential{}}, Some{T.Parallel{}}, False{}, True{})
    scenario("", Some{T.Parallel{}}, Some{T.Parallel{}}, None{}, False{}, False{})
    scenario("", Some{T.Parallel{}}, Some{T.Parallel{}}, Some{T.Sequential{}}, False{}, True{})
    scenario("", Some{T.Parallel{}}, Some{T.Parallel{}}, Some{T.Parallel{}}, False{}, False{})
    scenario("", None{}, None{}, None{}, True{}, False{})
    scenario("", Some{T.Sequential{}}, None{}, None{}, True{}, True{})
    scenario("", Some{T.Parallel{}}, None{}, None{}, True{}, False{})
    scenario("start:call", None{}, None{}, None{}, False{}, False{})
    scenario("update:call", None{}, None{}, None{}, False{}, False{})
    scenario("end:call", None{}, None{}, None{}, False{}, False{})
    scenario("message_start:call", None{}, None{}, None{}, False{}, False{})
    scenario("message_end:call", None{}, None{}, None{}, False{}, False{})
    scenario("start:call", Some{T.Sequential{}}, None{}, None{}, False{}, True{})
    scenario("update:call", Some{T.Sequential{}}, None{}, None{}, False{}, True{})
    scenario("end:call", Some{T.Sequential{}}, None{}, None{}, False{}, True{})
    scenario("message_start:call", Some{T.Sequential{}}, None{}, None{}, False{}, True{})
    scenario("message_end:call", Some{T.Sequential{}}, None{}, None{}, False{}, True{})
    scenario("start:call", Some{T.Parallel{}}, None{}, None{}, False{}, False{})
    scenario("update:call", Some{T.Parallel{}}, None{}, None{}, False{}, False{})
    scenario("end:call", Some{T.Parallel{}}, None{}, None{}, False{}, False{})
    scenario("message_start:call", Some{T.Parallel{}}, None{}, None{}, False{}, False{})
    scenario("message_end:call", Some{T.Parallel{}}, None{}, None{}, False{}, False{})
    IO.print("PASS 45 routed native tool batches: global/tool overrides, first-match lookup, unrelated tools, content filtering, empty batches and delivery failures")
