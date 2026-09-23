import Base
import ../src/agent-loop.bend as W
import ../src/agent-loop.bend as Entry
import ../src/stream-fn.bend as Defaults
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as S
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./main-loop.bend as H
import ./validated-tool-execution.bend as Validation
import ./agent-loop-tools.bend as Tools
import ./message-events.bend as Test
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch

def HookInput() -> Data: T.ToolHookInput<T.BeforeToolCallContext<Unit, String, String, String>>
def HookOutput() -> Data: Result<&2, &2, String, T.BeforeToolCallUpdate<Validation.Context()>>
type Capture is Data:
  Capture{prepare: Bool, log: H.Log()}
type Provider is Data:
  Provider{prepare: Bool, calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}

def edit() -> V.Value:
  V.ObjectValue{Record.Record{Record.Property{"oldText", V.Text{"before"}} <> Record.Property{"newText", V.Text{"after"}} <> Nil{}}}
def prepared() -> V.Value:
  V.ObjectValue{Record.Record{Record.Property{"edits", V.ArrayValue{edit() <> Nil{}}} <> Nil{}}}
def raw(prepare: Bool) -> V.Value: Bool.pick(V.Value, prepare, edit(), Validation.field(V.Text{"hello"}))
def toolName(prepare: Bool) -> String: Bool.pick(String, prepare, "edit", "echo")
def objectSchema(fields: Record.Record<V.Value>, required: List<&2, V.Value>) -> V.Value:
  V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", V.ObjectValue{fields}} <> Record.Property{"required", V.ArrayValue{required}} <> Nil{}}}
def textSchema() -> V.Value: V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"string"}} <> Nil{}}}
def editsSchema() -> V.Value:
  V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"array"}} <> Record.Property{"items", objectSchema(Record.Record{Record.Property{"oldText", textSchema()} <> Record.Property{"newText", textSchema()} <> Nil{}}, V.Text{"oldText"} <> V.Text{"newText"} <> Nil{})} <> Nil{}}}
def schema(prepare: Bool) -> V.Value:
  Bool.pick(V.Value, prepare, objectSchema(Record.Record{Record.Property{"edits", editsSchema()} <> Nil{}}, V.Text{"edits"} <> Nil{}), Tools.schema())

def appendEdit(existing: Maybe<&2, V.Value>, item: V.Value) -> List<&2, V.Value>:
  match existing:
    case Some{V.ArrayValue{values}}: List.append(&2, V.Value, values, item <> Nil{})
    case _: item <> Nil{}

def adaptFields(original: V.Value, oldText: Maybe<&2, V.Value>, newText: Maybe<&2, V.Value>, existing: Maybe<&2, V.Value>) -> V.Value:
  match oldText newText:
    case Some{V.Text{oldText}} Some{V.Text{newText}}:
      V.ObjectValue{Record.Record{Record.Property{"edits", V.ArrayValue{appendEdit(existing, V.ObjectValue{Record.Record{Record.Property{"oldText", V.Text{oldText}} <> Record.Property{"newText", V.Text{newText}} <> Nil{}}})}} <> Nil{}}}
    case _ _: original

def adapt(args: V.Value) -> V.Value:
  match args:
    case V.ObjectValue{+fields}: adaptFields(V.ObjectValue{fields}, Record.get(V.Value, fields, "oldText"), Record.get(V.Value, fields, "newText"), Record.get(V.Value, fields, "edits"))
    case other: other

def adapter(recording: H.Log(), args: V.Value) -> IO(Validation.Checked()):
  +args = args
  do IO<Validation.Checked()>:
    Test.assertion(V.equal(args, edit()), "prepareArguments receives original flat edit")
    H.log(recording, "prepare")
    return Done{adapt(args)}

def validate(capture: Capture, input: Validation.Input()) -> IO(Validation.Checked()):
  match capture:
    case Capture{prepare, recording}:
      do IO<Validation.Checked()>:
        H.log(recording, "validate")
        Validation.validate(Unit{}, input)

def before(recording: H.Log(), input: HookInput()) -> IO(HookOutput()):
  match input:
    case T.ToolHookInput{T.BeforeToolCallContext{_, Ai.ToolCall{_, _, original, _, _}, args, context}, _}:
      do IO<HookOutput()>:
        Test.assertion(V.equal(original, raw(False{})) && V.equal(args, raw(False{})), "hook sees original and validated string arguments")
        H.log(recording, "before")
        return Done{T.BeforeToolCallUpdate{Validation.field(V.Number{F.fromU32(123)}), context, None{}}}

def execute(capture: Capture, input: Validation.ExecuteInput()) -> IO(Validation.ExecuteOutput()):
  match capture input:
    case Capture{+prepare, recording} T.ToolExecutionInput{id, args, _, _}:
      do IO<Validation.ExecuteOutput()>:
        Test.assertion(String.eq(id, "tool-1") && V.equal(args, Bool.pick(V.Value, prepare, prepared(), Validation.field(V.Number{F.fromU32(123)}))), "executor receives exact prepared edits or numeric hook replacement")
        H.log(recording, "execute")
        return Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{Bool.pick(String, prepare, "edited 1", "echoed: 123"), None{}}} <> Nil{}, "result", None{}, None{}}}

def response(+prepare: Bool, index: U32) -> Ai.AssistantMessageEvent<V.Value, Unit>:
  match index:
    case 0: Ai.StreamDone{Ai.DoneToolUse{}, H.assistant(Ai.AssistantToolCall{Ai.ToolCall{"tool-1", toolName(prepare), raw(prepare), None{}, None{}}} <> Nil{}, Ai.ToolUse{})}
    case _: Ai.StreamDone{Ai.DoneStop{}, H.assistant(H.text("done"), Ai.Stop{})}

def provider(environment: Provider, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match environment:
    case Provider{prepare, calls, streams}:
      do IO<H.ProviderOutput()>:
        +index : U32 <- H.bump(calls)
        Test.assertion(U32.is_lt(index, 2), "two provider requests")
        +stream : H.StreamValue() <- S.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        S.push(Ai.AssistantMessageEvent<V.Value, Unit>, H.Assistant(), stream, response(prepare, index))
        return Done{T.borrowedStream(Unit, String, stream)}

def history(+prepare: Bool, messages: Validation.Messages()) -> Bool:
  match messages:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantToolCall{Ai.ToolCall{_, _, args, _, _}} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}} <> T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_, _, Ai.TextImageText{Ai.TextContent{text, _}} <> Nil{}, _, _, False{}, _}}} <> T.LlmMessage{Ai.Assistant{last}} <> Nil{}:
      V.equal(args, raw(prepare)) && String.eq(text, Bool.pick(String, prepare, "edited 1", "echoed: 123")) && String.eq(H.assistantName(last), "assistant:done")
    case _ <> rest: history(prepare, rest)
    case Nil{}: False{}

def checkOutcome(prepare: Bool, result: H.Outcome()) -> IO(Unit):
  match result:
    case Done{messages}: Test.assertion(history(prepare, messages), "raw assistant arguments stay immutable while tool receives prepared/replaced args")
    case Fail{_}: Test.assertion(False{}, "argument loop succeeds")

def scenario(+prepare: Bool, name: String) -> IO(Unit):
  do IO<Unit>:
    +recording : H.Log() <- R.new(List<&2, String>, Nil{})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +executor : C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()> <- C.create(~Capture, ~Validation.ExecuteInput(), ~Validation.ExecuteOutput(), ~execute, Capture{prepare, recording})
    +prepareCallback : C.Callback<V.Value, Validation.Checked()> <- C.create(~H.Log(), ~V.Value, ~Validation.Checked(), ~adapter, recording)
    +hook : C.Callback<HookInput(), HookOutput()> <- C.create(~H.Log(), ~HookInput(), ~HookOutput(), ~before, recording)
    +providerCallback : H.ProviderFunction() <- C.create(~Provider, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, Provider{prepare, calls, streams})
    +converter : C.Callback<Validation.Messages(), Validation.Converted()> <- C.create(~Unit, ~Validation.Messages(), ~Validation.Converted(), ~Tools.convert, Unit{})
    +validator : C.Callback<Validation.Input(), Validation.Checked()> <- C.create(~Capture, ~Validation.Input(), ~Validation.Checked(), ~validate, Capture{prepare, recording})
    +aborted : C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool> <- C.create(~Unit, ~Maybe<&2, Abort.AbortSignal<Unit>>, ~Bool, ~H.abort, Unit{})
    config : Validation.Config() = T.AgentLoopConfig{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String), Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Bool.pick(Maybe<&2, C.Callback<HookInput(), HookOutput()>>, prepare, None{}, Some{hook}), None{}}
    context : Validation.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{toolName(prepare), "Tool", schema(prepare), None{}, "Tool", Bool.pick(Maybe<&2, C.Callback<V.Value, Validation.Checked()>>, prepare, Some{prepareCallback}, None{}), executor, None{}, None{}} <> Nil{}}}
    +run : H.StreamRun() <- W.agentLoop(~Unit, ~String, ~String, ~String, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{Bool.pick(String, prepare, "edit something", "echo something")}, F.fromU32(0)}}} <> Nil{}, context, config, W.Options{None{}, validator, aborted, "empty", Defaults.Explicit{providerCallback}})
    +iterator : S.Iterator<Validation.EventValue(), H.Outcome()> <- W.iterator(Unit, String, String, String, run)
    events : List<&2, String> <- H.collectEvents(iterator, Nil{}, None{})
    outcome : H.Outcome() <- W.streamOutcome(Unit, String, String, String, run)
    checkOutcome(prepare, outcome)
    S.disposeIterator(Validation.EventValue(), H.Outcome(), iterator)
    W.disposeStreamRun(Unit, String, String, String, run)
    count : U32 <- R.dispose(U32, calls)
    Test.assertion(U32.is_eq(count, 2), "tool turn followed by final response")
    entries : List<&2, String> <- R.dispose(List<&2, String>, recording)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, entries), "|"), Bool.pick(String, prepare, "prepare|validate|execute", "validate|before|execute")), "exactly-once preparation/validation/hook/execution in source order")
    C.dispose(Validation.ExecuteInput(), Validation.ExecuteOutput(), executor)
    C.dispose(V.Value, Validation.Checked(), prepareCallback)
    C.dispose(HookInput(), HookOutput(), hook)
    C.dispose(H.ProviderInput(), H.ProviderOutput(), providerCallback)
    C.dispose(Validation.Messages(), Validation.Converted(), converter)
    C.dispose(Validation.Input(), Validation.Checked(), validator)
    C.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, aborted)
    owned : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(owned)
    IO.print("PASS " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{}, "should execute mutated beforeToolCall args without revalidation")
    scenario(True{}, "should prepare tool arguments for validation")
