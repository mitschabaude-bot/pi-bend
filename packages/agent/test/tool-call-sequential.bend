import Base
import ../../ai/test/model-types.bend as Model
import ../src/agent-loop.bend as Call
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
import ../../runtime/src/abort.bend as Abort

def Input() -> Data: Call.CallInput(Unit, String, String, String, Unit)
def Output() -> Data: Call.CallOutput(Unit, String, String, String, Unit)
def Outcome() -> Data: Result<&2, &2, String, Batch.Batch<H.Context(), Ai.ToolResultMessage<String>>>
def BeforeInput() -> Data: T.ToolHookInput<T.BeforeToolCallContext<Unit, String, String, String>>
def BeforeOutput() -> Data: Result<&2, &2, String, T.BeforeToolCallUpdate<H.Context()>>
def AfterInput() -> Data: T.ToolHookInput<T.AfterToolCallContext<Unit, String, String, String>>
def AfterOutput() -> Data: Result<&2, &2, String, Maybe<&2, T.AfterToolCallResult<String>>>
def Update() -> Data: T.AgentToolUpdateCallback(String)

type Recording is Data:
  Recording{events: R.Ref<List<&2, String>>, failAt: String, abortAfter: Bool, signal: R.Ref<Bool>}
type Execution is Data:
  Execution{calls: R.Ref<U32>, retained: R.Ref<Maybe<&2, Update()>>}

def key(event: H.EventValue()) -> String:
  match event:
    case T.ToolExecutionStart{id, _, _}: "start:" ++ id
    case T.ToolExecutionUpdate{id, _, _, _}: "update:" ++ id
    case T.ToolExecutionEnd{id, _, _, _}: "end:" ++ id
    case T.MessageStart{T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id, _, _, _, _, _, _}}}}: "message_start:" ++ id
    case T.MessageEnd{T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id, _, _, _, _, _, _}}}}: "message_end:" ++ id
    case _: "unexpected"

def emit(environment: Recording, event: H.EventValue()) -> IO(E.Emission<String>):
  match environment:
    case Recording{events, failAt, abortAfter, +signal}:
      do IO<E.Emission<String>>:
        +name : String = key(event)
        R.modify(List<&2, String>, Unit, events, values => (name <> values, Unit{}))
        previous : Bool <- R.read(Bool, signal)
        R.write(Bool, signal, previous || (abortAfter && String.eq(name, "end:call")))
        return E.EmissionReady{Bool.pick(Result<&2, &2, String, Unit>, String.eq(name, failAt), Fail{"delivery failed"}, Done{Unit{}})}

def execute(environment: Execution, input: H.ExecuteInput()) -> IO(H.ExecuteOutput()):
  match environment input:
    case Execution{calls, retained} T.ToolExecutionInput{id, arguments, Some{_}, Some{+update}}:
      do IO<H.ExecuteOutput()>:
        Test.assertion(String.eq(id, "call") && V.equal(arguments, H.field(V.Text{"changed by hook"})), "execution receives before-hook arguments without revalidation")
        R.modify(U32, Unit, calls, count => ((count + 1 : U32), Unit{}))
        R.write(Maybe<&2, Update()>, retained, Some{update})
        C.call(T.AgentToolResult<String>, Unit, update, T.AgentToolResult{Nil{}, "progress", None{}, None{}})
        return Done{T.AgentToolResult{Nil{}, "executed", None{}, None{}}}
    case _ _: IO.die(H.ExecuteOutput(), 1, "unexpected execution input")

def marked(context: H.Context()) -> Bool:
  match context:
    case T.AgentContext{T.CustomMessage{marker} <> Nil{}, _}: String.eq(marker, "before hook")
    case _: False{}

def before(block: Bool, input: BeforeInput()) -> IO(BeforeOutput()):
  match input:
    case T.ToolHookInput{T.BeforeToolCallContext{_, _, arguments, T.AgentContext{messages, tools}}, _}:
      do IO<BeforeOutput()>:
        Test.assertion(V.equal(arguments, H.field(V.Number{F.fromU32(42)})), "before hook receives successfully validated arguments")
        decision : Maybe<&2, T.BeforeToolCallResult> = Bool.pick(Maybe<&2, T.BeforeToolCallResult>, block, Some{T.BeforeToolCallResult{Some{True{}}, Some{"blocked"}, Some{True{}}}}, None{})
        return Done{T.BeforeToolCallUpdate{H.field(V.Text{"changed by hook"}), T.AgentContext{List.append(&2, T.AgentMessage<Unit, String, String>, messages, T.CustomMessage{"before hook"} <> Nil{}), tools}, decision}}

def after(counter: R.Ref<U32>, input: AfterInput()) -> IO(AfterOutput()):
  match input:
    case T.ToolHookInput{T.AfterToolCallContext{_, _, arguments, T.AgentToolResult{_, details, _, _}, False{}, context}, _}:
      do IO<AfterOutput()>:
        Test.assertion(marked(context) && V.equal(arguments, H.field(V.Text{"changed by hook"})) && String.eq(details, "executed"), "after hook sees updated arguments, context and executor result")
        R.modify(U32, Unit, counter, count => ((count + 1 : U32), Unit{}))
        return Done{Some{T.AfterToolCallResult{None{}, Some{"finalized"}, None{}, None{}, Some{True{}}}}}
    case _: IO.die(AfterOutput(), 1, "after hook must not run for immediate outcomes")

def aborted(signal: R.Ref<Bool>, unused: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Bool): R.read(Bool, signal)
def batchAborted(signal: R.Ref<Bool>, unused: Unit) -> IO(Bool): R.read(Bool, signal)
def render(error: String) -> String: error

def configuration(converter: C.Callback<H.Messages(), H.Converted()>, beforeHook: C.Callback<BeforeInput(), BeforeOutput()>, hook: C.Callback<AfterInput(), AfterOutput()>) -> H.Config():
  T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"custom"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{beforeHook}, Some{hook}}

def equal(left: List<&2, String>, right: List<&2, String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> xs b <> ys: String.eq(a, b) && equal(xs, ys)
    case _ _: False{}

def finalizedDetails(details: Maybe<&2, String>, isError: Bool) -> Bool:
  match details isError:
    case Some{details} False{}: String.eq(details, "finalized")
    case _ True{}: True{}
    case _ _: False{}

def messages(values: List<&2, Ai.ToolResultMessage<String>>, errors: List<&2, Bool>, ids: List<&2, String>) -> Bool:
  match values errors ids:
    case Nil{} Nil{} _: True{}
    case Ai.ToolResultMessage{id, _, _, details, _, +isError, _} <> rest expected <> remaining next <> tail:
      String.eq(id, next) && String.eq(Bool.show(isError), Bool.show(expected)) && finalizedDetails(details, isError) && messages(rest, remaining, tail)
    case _ _ _: False{}

def checkOutcome(actual: Outcome(), failed: Bool, hasMarker: Bool, errors: List<&2, Bool>, terminate: Bool) -> IO(Unit):
  match actual failed:
    case Fail{error} True{}: Test.assertion(String.eq(error, "delivery failed"), "delivery error propagates without conversion to tool error")
    case Done{Batch.Batch{context, values, actualTerminate}} False{}:
      do IO<Unit>:
        Test.assertion(String.eq(Bool.show(marked(context)), Bool.show(hasMarker)), "batch preserves before-hook context")
        Test.assertion(messages(values, errors, "call" <> "bad" <> "missing" <> Nil{}), "canonical batch result messages")
        Test.assertion(String.eq(Bool.show(actualTerminate), Bool.show(terminate)), "canonical batch final termination")
    case _ _: Test.assertion(False{}, "unexpected lifecycle batch outcome")

def late(callback: Maybe<&2, Update()>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit, Unit{})
    case Some{callback}: C.call(T.AgentToolResult<String>, Unit, callback, T.AgentToolResult{Nil{}, "late", None{}, None{}})

def scenario(+failAt: String, +initialAbort: Bool, abortAfter: Bool, blockBefore: Bool, expectedCalls: U32, expectedHooks: U32, expectedEvents: List<&2, String>, expectedErrors: List<&2, Bool>, terminate: Bool) -> IO(Unit):
  do IO<Unit>:
    +events : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +signal : R.Ref<Bool> <- R.new(Bool, initialAbort)
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +hooks : R.Ref<U32> <- R.new(U32, 0)
    +retained : R.Ref<Maybe<&2, Update()>> <- R.new(Maybe<&2, Update()>, None{})
    +executor : C.Callback<H.ExecuteInput(), H.ExecuteOutput()> <- C.create(~Execution, ~H.ExecuteInput(), ~H.ExecuteOutput(), ~execute, Execution{calls, retained})
    +validator : C.Callback<H.Input(), H.Checked()> <- C.create(~Unit, ~H.Input(), ~H.Checked(), ~H.validate, Unit{})
    +converter : C.Callback<H.Messages(), H.Converted()> <- C.create(~Unit, ~H.Messages(), ~H.Converted(), ~H.convert, Unit{})
    +beforeHook : C.Callback<BeforeInput(), BeforeOutput()> <- C.create(~Bool, ~BeforeInput(), ~BeforeOutput(), ~before, blockBefore)
    +hook : C.Callback<AfterInput(), AfterOutput()> <- C.create(~R.Ref<U32>, ~AfterInput(), ~AfterOutput(), ~after, hooks)
    +abort : C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool> <- C.create(~R.Ref<Bool>, ~Maybe<&2, Abort.AbortSignal<Unit>>, ~Bool, ~aborted, signal)
    +batchAbort : C.Callback<Unit, Bool> <- C.create(~R.Ref<Bool>, ~Unit, ~Bool, ~batchAborted, signal)
    +emitter : C.Callback<H.EventValue(), E.Emission<String>> <- C.create(~Recording, ~H.EventValue(), ~E.Emission<String>, ~emit, Recording{events, failAt, abortAfter, signal})
    +sink : C.Callback<H.EventValue(), Result<&2, &2, String, Unit>> <- Loop.createAwaitedEventSink(~Unit, ~String, ~String, ~T.AgentToolResult<String>, ~T.AgentToolResult<String>, ~String, emitter)
    +owners : Call.Owners(String, String) <- Call.newOwners(String, String)
    schema : V.Value = V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", H.field(V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"number"}} <> Nil{}}})} <> Record.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}
    context : H.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "", schema, None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    +zero : F.F64 = F.fromU32(0)
    assistant : Ai.AssistantMessage<V.Value, Unit> = Ai.AssistantMessage{Nil{}, "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.ToolUse{}, None{}, None{}, None{}, None{}, zero}
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +runner : C.Callback<Input(), Output()> <- Call.create(~Unit, ~String, ~String, ~String, ~Unit, ~render, Call.CallCapture{assistant, configuration(converter, beforeHook, hook), Some{Abort.signal(Unit, controller)}, validator, abort, emitter, sink, owners, "empty"})
    toolCalls : List<&2, Ai.ToolCall<V.Value>> = Ai.ToolCall{"call", "echo", H.field(V.Text{"42"}), None{}, None{}} <> Ai.ToolCall{"bad", "echo", H.field(V.Text{"bad"}), None{}, None{}} <> Ai.ToolCall{"missing", "absent", H.field(V.Text{"42"}), None{}, None{}} <> Nil{}
    result : Outcome() <- Batch.executeSequential(H.Context(), Ai.ToolCall<V.Value>, Ai.ToolResultMessage<String>, String, context, toolCalls, runner, batchAbort)
    # Upstream runs the before hook before checking abort; its returned
    # context survives even when the signal was already aborted.
    checkOutcome(result, Bool.not(String.is_empty(failAt)), True{}, expectedErrors, terminate)
    saved : Maybe<&2, Update()> <- R.read(Maybe<&2, Update()>, retained)
    late(saved)
    recorded : List<&2, String> <- R.read(List<&2, String>, events)
    Test.assertion(equal(List.reverse(&2, String, recorded), expectedEvents), "canonical lifecycle event ordering; retained updates are inactive")
    actualCalls : U32 <- R.read(U32, calls)
    actualHooks : U32 <- R.read(U32, hooks)
    Test.assertion(U32.is_eq(actualCalls, expectedCalls) && U32.is_eq(actualHooks, expectedHooks), "lifecycle execution and hook counts")
    C.dispose(Input(), Output(), runner)
    C.dispose(H.ExecuteInput(), H.ExecuteOutput(), executor)
    saved : Maybe<&2, Update()> <- R.dispose(Maybe<&2, Update()>, retained)
    Call.disposeOwners(String, String, owners)
    C.dispose(H.Input(), H.Checked(), validator)
    C.dispose(H.Messages(), H.Converted(), converter)
    C.dispose(BeforeInput(), BeforeOutput(), beforeHook)
    C.dispose(AfterInput(), AfterOutput(), hook)
    C.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, abort)
    C.dispose(Unit, Bool, batchAbort)
    C.dispose(H.EventValue(), Result<&2, &2, String, Unit>, sink)
    C.dispose(H.EventValue(), E.Emission<String>, emitter)
    dropped : List<&2, String> <- R.dispose(List<&2, String>, events)
    dropped : Bool <- R.dispose(Bool, signal)
    dropped : U32 <- R.dispose(U32, calls)
    dropped : U32 <- R.dispose(U32, hooks)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    scenario("", False{}, False{}, False{}, 1, 1, "start:call" <> "update:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "start:bad" <> "end:bad" <> "message_start:bad" <> "message_end:bad" <> "start:missing" <> "end:missing" <> "message_start:missing" <> "message_end:missing" <> Nil{}, False{} <> True{} <> True{} <> Nil{}, False{})
    scenario("", False{}, True{}, False{}, 1, 1, "start:call" <> "update:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> Nil{}, False{} <> Nil{}, True{})
    scenario("", True{}, False{}, False{}, 0, 0, "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> Nil{}, True{} <> Nil{}, False{})
    scenario("start:call", False{}, False{}, False{}, 0, 0, "start:call" <> Nil{}, Nil{}, False{})
    scenario("update:call", False{}, False{}, False{}, 1, 0, "start:call" <> "update:call" <> Nil{}, Nil{}, False{})
    scenario("end:call", False{}, False{}, False{}, 1, 1, "start:call" <> "update:call" <> "end:call" <> Nil{}, Nil{}, False{})
    scenario("message_start:call", False{}, False{}, False{}, 1, 1, "start:call" <> "update:call" <> "end:call" <> "message_start:call" <> Nil{}, Nil{}, False{})
    scenario("message_end:call", False{}, False{}, False{}, 1, 1, "start:call" <> "update:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> Nil{}, Nil{}, False{})
    scenario("", False{}, True{}, True{}, 0, 0, "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> Nil{}, True{} <> Nil{}, True{})
    scenario("", False{}, False{}, True{}, 0, 0, "start:call" <> "end:call" <> "message_start:call" <> "message_end:call" <> "start:bad" <> "end:bad" <> "message_start:bad" <> "message_end:bad" <> "start:missing" <> "end:missing" <> "message_start:missing" <> "message_end:missing" <> Nil{}, True{} <> True{} <> True{} <> Nil{}, False{})
    IO.print("PASS 10 canonical sequential tool lifecycle scenarios")
