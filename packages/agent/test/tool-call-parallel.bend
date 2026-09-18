import Base
import ../../ai/test/model-types.bend as Model
import ../src/tool-call.bend as Call
import ../src/tool-batch-parallel.bend as Parallel
import ../src/tool-batch.bend as Batch
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../src/event-emission.bend as E
import ../../ai/src/types.bend as Ai
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./validated-tool-execution.bend as H
import ./message-events.bend as Test

import ./tool-call-sequential.bend as S

# Abort during preparation as well as at a blocked immediate outcome.
def emit(environment: S.Recording, event: H.EventValue()) -> IO(E.Emission<String>):
  match environment:
    case S.Recording{events, failAt, abortAfter, +signal}:
      do IO<E.Emission<String>>:
        +name : String = S.key(event)
        R.modify(List<&2, String>, Unit, events, values => (name <> values, Unit{}))
        previous : Bool <- R.read(Bool, signal)
        R.write(Bool, signal, previous || (abortAfter && (String.eq(name, "end:call") || String.eq(name, "end:bad"))))
        return E.Ready{Bool.pick(Result<&2, &2, String, Unit>, String.eq(name, failAt), Fail{"delivery failed"}, Done{Unit{}})}

def finishRun(started: Result<&2, &2, String, Parallel.Run<V.Value, V.Value, Unit, String, String, V.Value, Unit, String>>) -> IO(S.Outcome()):
  match started:
    case Fail{error}: IO.pure(S.Outcome(), Fail{error})
    case Done{+run}:
      do IO<S.Outcome()>:
        result : S.Outcome() <- Parallel.result(V.Value, V.Value, Unit, String, String, V.Value, Unit, String, run)
        Parallel.dispose(V.Value, V.Value, Unit, String, String, V.Value, Unit, String, run)
        return result

def contains(+name: String, events: List<&2, String>) -> Bool:
  match events:
    case Nil{}: False{}
    case event <> rest: String.eq(name, event) || contains(name, rest)

def scenario(+failAt: String, +initialAbort: Bool, abortAfter: Bool, blockBefore: Bool, expectedCalls: U32, expectedHooks: U32, +expectedEvents: List<&2, String>, expectedErrors: List<&2, Bool>, terminate: Bool) -> IO(Unit):
  do IO<Unit>:
    +events : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +signal : R.Ref<Bool> <- R.new(Bool, initialAbort)
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +hooks : R.Ref<U32> <- R.new(U32, 0)
    +retained : R.Ref<Maybe<&2, S.Update()>> <- R.new(Maybe<&2, S.Update()>, None{})
    +executor : C.Callback<H.ExecuteInput(), H.ExecuteOutput()> <- C.create(~S.Execution, ~H.ExecuteInput(), ~H.ExecuteOutput(), ~S.execute, S.Execution{calls, retained})
    +validator : C.Callback<H.Input(), H.Checked()> <- C.create(~Unit, ~H.Input(), ~H.Checked(), ~H.validate, Unit{})
    +converter : C.Callback<H.Messages(), H.Converted()> <- C.create(~Unit, ~H.Messages(), ~H.Converted(), ~H.convert, Unit{})
    +beforeHook : C.Callback<S.BeforeInput(), S.BeforeOutput()> <- C.create(~Bool, ~S.BeforeInput(), ~S.BeforeOutput(), ~S.before, blockBefore)
    +hook : C.Callback<S.AfterInput(), S.AfterOutput()> <- C.create(~R.Ref<U32>, ~S.AfterInput(), ~S.AfterOutput(), ~S.after, hooks)
    +abort : C.Callback<Maybe<&2, Unit>, Bool> <- C.create(~R.Ref<Bool>, ~Maybe<&2, Unit>, ~Bool, ~S.aborted, signal)
    +emitter : C.Callback<H.EventValue(), E.Emission<String>> <- C.create(~S.Recording, ~H.EventValue(), ~E.Emission<String>, ~emit, S.Recording{events, failAt, abortAfter, signal})
    +sink : C.Callback<H.EventValue(), Result<&2, &2, String, Unit>> <- Loop.createAwaitedEventSink(~V.Value, ~V.Value, ~Unit, ~String, ~String, ~T.AgentToolResult<String>, ~T.AgentToolResult<String>, ~String, emitter)
    +owners : Call.Owners(String, String) <- Call.newOwners(String, String)
    schema : V.Value = V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", H.field(V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"number"}} <> Nil{}}})} <> Record.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}
    context : H.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "", schema, None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    +zero : F.F64 = F.fromU32(0)
    assistant : Ai.AssistantMessage<V.Value, Unit> = Ai.AssistantMessage{Nil{}, "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.ToolUse{}, None{}, None{}, None{}, None{}, zero}
    capture : Call.Capture<V.Value, V.Value, Unit, String, String, V.Value, Unit, String, Unit, Unit, Unit> = Call.Capture{assistant, S.configuration(converter, beforeHook, hook), Some{Unit{}}, validator, abort, emitter, sink, owners, "empty"}
    toolCalls : List<&2, Ai.ToolCall<V.Value>> = Ai.ToolCall{"call", "echo", H.field(V.Text{"42"}), None{}, None{}} <> Ai.ToolCall{"bad", "echo", H.field(V.Text{"bad"}), None{}, None{}} <> Ai.ToolCall{"missing", "absent", H.field(V.Text{"42"}), None{}, None{}} <> Nil{}
    started : Result<&2, &2, String, Parallel.Run<V.Value, V.Value, Unit, String, String, V.Value, Unit, String>> <- Parallel.start(~V.Value, ~V.Value, ~Unit, ~String, ~String, ~V.Value, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~S.render, capture, context, toolCalls)
    result : S.Outcome() <- finishRun(started)
    # Upstream runs the before hook before checking abort; its returned
    # context survives even when the signal was already aborted.
    S.checkOutcome(result, contains(failAt, expectedEvents), True{}, expectedErrors, terminate)
    saved : Maybe<&2, S.Update()> <- R.read(Maybe<&2, S.Update()>, retained)
    S.late(saved)
    recorded : List<&2, String> <- R.read(List<&2, String>, events)
    Test.assertion(S.equal(List.reverse(&2, String, recorded), expectedEvents), "canonical lifecycle event ordering; retained updates are inactive")
    actualCalls : U32 <- R.read(U32, calls)
    actualHooks : U32 <- R.read(U32, hooks)
    Test.assertion(U32.is_eq(actualCalls, expectedCalls) && U32.is_eq(actualHooks, expectedHooks), "lifecycle execution and hook counts")
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
    scenario("", False{}, False{}, False{}, 1, 1, "start:call" <> "start:bad" <> "end:bad" <> "start:missing" <> "end:missing" <> "update:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "message_start:bad" <> "message_end:bad" <> "message_start:missing" <> "message_end:missing" <> Nil{}, False{} <> True{} <> True{} <> Nil{}, False{})
    scenario("", False{}, True{}, False{}, 0, 0, "start:call" <> "start:bad" <> "end:bad" <> "end:call" <> "message_start:call" <> "message_end:call" <> "message_start:bad" <> "message_end:bad" <> Nil{}, True{} <> True{} <> Nil{}, False{})
    scenario("", True{}, False{}, False{}, 0, 0, "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> Nil{}, True{} <> Nil{}, False{})
    scenario("start:call", False{}, False{}, False{}, 0, 0, "start:call" <> Nil{}, Nil{}, False{})
    scenario("start:bad", False{}, False{}, False{}, 0, 0, "start:call" <> "start:bad" <> Nil{}, Nil{}, False{})
    scenario("end:bad", False{}, False{}, False{}, 0, 0, "start:call" <> "start:bad" <> "end:bad" <> Nil{}, Nil{}, False{})
    scenario("update:call", False{}, False{}, False{}, 1, 0, "start:call" <> "start:bad" <> "end:bad" <> "start:missing" <> "end:missing" <> "update:call" <> Nil{}, Nil{}, False{})
    scenario("end:call", False{}, False{}, False{}, 1, 1, "start:call" <> "start:bad" <> "end:bad" <> "start:missing" <> "end:missing" <> "update:call" <> "end:call" <> Nil{}, Nil{}, False{})
    scenario("message_start:call", False{}, False{}, False{}, 1, 1, "start:call" <> "start:bad" <> "end:bad" <> "start:missing" <> "end:missing" <> "update:call" <> "end:call" <> "message_start:call" <> Nil{}, Nil{}, False{})
    scenario("message_end:call", False{}, False{}, False{}, 1, 1, "start:call" <> "start:bad" <> "end:bad" <> "start:missing" <> "end:missing" <> "update:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> Nil{}, Nil{}, False{})
    scenario("", False{}, True{}, True{}, 0, 0, "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> Nil{}, True{} <> Nil{}, True{})
    scenario("", False{}, False{}, True{}, 0, 0, "start:call" <> "end:call" <> "start:bad" <> "end:bad" <> "start:missing" <> "end:missing" <> "message_start:call" <> "message_end:call" <> "message_start:bad" <> "message_end:bad" <> "message_start:missing" <> "message_end:missing" <> Nil{}, True{} <> True{} <> True{} <> Nil{}, False{})
    IO.print("PASS 12 canonical parallel tool lifecycle scenarios")
