import Base
import ../src/agent-loop.bend as W
import ../src/agent-loop.bend as Entry
import ../src/stream-fn.bend as Defaults
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as S
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ./main-loop.bend as H
import ./validated-tool-execution.bend as Validation
import ./agent-loop-tools.bend as Tools
import ./agent-loop-turns.bend as Turns
import ./message-events.bend as Test
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch

def BeforeInput() -> Data: T.ToolHookInput<T.BeforeToolCallContext<Unit, String, String, String>>
def BeforeOutput() -> Data: Result<&2, &2, String, T.BeforeToolCallUpdate<Validation.Context()>>
type Capture is Data:
  Capture{mode: U32, executions: H.Log(), hooks: H.Log()}
type Provider is Data:
  Provider{mode: U32, calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}

def continues(+mode: U32) -> Bool: U32.is_eq(mode, 2) || U32.is_eq(mode, 3)
def valueFor(mode: U32, id: String) -> String:
  Bool.pick(String, continues(mode), Bool.pick(String, String.eq(id, "tool-1"), "first", "second"), "hello")
def terminate(mode: U32, id: String) -> Maybe<&2, Bool>:
  match mode:
    case 0: Some{True{}}
    case 3: Some{String.eq(id, "tool-1")}
    case _: None{}

def execute(environment: Capture, input: Validation.ExecuteInput()) -> IO(Validation.ExecuteOutput()):
  match environment input:
    case Capture{+mode, recording, _} T.ToolExecutionInput{+id, args, _, _}:
      do IO<Validation.ExecuteOutput()>:
        +value : String = valueFor(mode, id)
        Test.assertion(V.equal(args, Validation.field(V.Text{value})), "executor receives original validated arguments")
        H.log(recording, value)
        return Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"echoed: " ++ value, None{}}} <> Nil{}, value, None{}, terminate(mode, id)}}

def blockDecision(mode: U32, id: String) -> Maybe<&2, T.BeforeToolCallResult>:
  match mode:
    case 1: Some{T.BeforeToolCallResult{Some{True{}}, Some{"Blocked by policy"}, Some{True{}}}}
    case 2: Bool.pick(Maybe<&2, T.BeforeToolCallResult>, String.eq(id, "tool-1"), Some{T.BeforeToolCallResult{Some{True{}}, Some{"Blocked first"}, Some{True{}}}}, None{})
    case _: None{}

def before(environment: Capture, input: BeforeInput()) -> IO(BeforeOutput()):
  match environment input:
    case Capture{+mode, _, recording} T.ToolHookInput{T.BeforeToolCallContext{_, Ai.ToolCall{+id, _, _, _, _}, +args, context}, _}:
      do IO<BeforeOutput()>:
        Test.assertion(V.equal(args, Validation.field(V.Text{valueFor(mode, id)})), "before hook receives validated original arguments")
        H.log(recording, "before:" ++ id)
        return Done{T.BeforeToolCallUpdate{args, context, blockDecision(mode, id)}}

def after(recording: H.Log(), input: Tools.HookInput()) -> IO(Tools.HookOutput()):
  do IO<Tools.HookOutput()>:
    H.log(recording, "after")
    return Done{Some{T.AfterToolCallResult{None{}, None{}, None{}, None{}, Some{True{}}}}}

def toolCall(+mode: U32, +id: String) -> Ai.AssistantContent<V.Value>:
  Ai.AssistantToolCall{Ai.ToolCall{id, "echo", Validation.field(V.Text{valueFor(mode, id)}), None{}, None{}}}
def calls(+mode: U32) -> List<&2, Ai.AssistantContent<V.Value>>:
  Bool.pick(List<&2, Ai.AssistantContent<V.Value>>, continues(mode), toolCall(mode, "tool-1") <> toolCall(mode, "tool-2") <> Nil{}, toolCall(mode, "tool-1") <> Nil{})
def response(mode: U32, index: U32) -> Ai.AssistantMessageEvent<V.Value, Unit>:
  match index:
    case 0: Ai.StreamDone{Ai.DoneToolUse{}, H.assistant(calls(mode), Ai.ToolUse{})}
    case _: Ai.StreamDone{Ai.DoneStop{}, H.assistant(H.text("done"), Ai.Stop{})}

def provider(environment: Provider, unused: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match environment:
    case Provider{+mode, counter, streams}:
      do IO<H.ProviderOutput()>:
        +index : U32 <- H.bump(counter)
        Test.assertion(U32.is_lt(index, Bool.pick(U32, continues(mode), 2, 1)), "termination controls provider request count")
        +stream : H.StreamValue() <- S.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        S.push(Ai.AssistantMessageEvent<V.Value, Unit>, H.Assistant(), stream, response(mode, index))
        return Done{T.borrowedStream(Unit, String, stream)}

def checkBlocked(messages: Validation.Messages(), expected: String) -> Bool:
  match messages:
    case T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{"tool-1", "echo", Ai.TextImageText{Ai.TextContent{text, _}} <> Nil{}, _, _, True{}, _}}} <> _: String.eq(text, expected)
    case _ <> rest: checkBlocked(rest, expected)
    case Nil{}: False{}

def blocked(mode: U32, messages: Validation.Messages()) -> Bool:
  match mode:
    case 1: checkBlocked(messages, "Blocked by policy")
    case 2: checkBlocked(messages, "Blocked first")
    case _: True{}

def checkOutcome(+mode: U32, result: H.Outcome()) -> IO(Unit):
  match result:
    case Fail{_}: Test.assertion(False{}, "termination loop succeeds")
    case Done{+messages}: Test.assertion(blocked(mode, messages) && String.eq(Turns.roles(messages), Bool.pick(String, continues(mode), "system|user|assistant|toolResult|toolResult|assistant|", "system|user|assistant|toolResult|")), "original history roles and blocked error text")

def occurrences(values: List<&2, String>, +needle: String) -> U32:
  match values:
    case Nil{}: 0
    case value <> rest: (Bool.pick(U32, String.eq(value, needle), 1, 0) + occurrences(rest, needle) : U32)

def executionCounts(mode: U32, +values: List<&2, String>) -> Bool:
  match mode:
    case 1: Nat.is_eq(List.length(&2, String, values), 0n)
    case 2: Nat.is_eq(List.length(&2, String, values), 1n) && U32.is_eq(occurrences(values, "second"), 1)
    case 3: Nat.is_eq(List.length(&2, String, values), 2n) && U32.is_eq(occurrences(values, "first"), 1) && U32.is_eq(occurrences(values, "second"), 1)
    case _: Nat.is_eq(List.length(&2, String, values), 1n) && U32.is_eq(occurrences(values, "hello"), 1)

def expectedHooks(mode: U32) -> String:
  match mode:
    case 1: "before:tool-1"
    case 2: "before:tool-1|before:tool-2"
    case 4: "after"
    case _: ""

def scenario(+mode: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +executions : H.Log() <- R.new(List<&2, String>, Nil{})
    +hooks : H.Log() <- R.new(List<&2, String>, Nil{})
    +counter : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +executor : C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()> <- C.create(~Capture, ~Validation.ExecuteInput(), ~Validation.ExecuteOutput(), ~execute, Capture{mode, executions, hooks})
    +beforeCallback : C.Callback<BeforeInput(), BeforeOutput()> <- C.create(~Capture, ~BeforeInput(), ~BeforeOutput(), ~before, Capture{mode, executions, hooks})
    +afterCallback : C.Callback<Tools.HookInput(), Tools.HookOutput()> <- C.create(~H.Log(), ~Tools.HookInput(), ~Tools.HookOutput(), ~after, hooks)
    +providerCallback : H.ProviderFunction() <- C.create(~Provider, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, Provider{mode, counter, streams})
    +converter : C.Callback<Validation.Messages(), Validation.Converted()> <- C.create(~Unit, ~Validation.Messages(), ~Validation.Converted(), ~Tools.convert, Unit{})
    +validator : C.Callback<Validation.Input(), Validation.Checked()> <- C.create(~Unit, ~Validation.Input(), ~Validation.Checked(), ~Validation.validate, Unit{})
    +aborted : C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool> <- C.create(~Unit, ~Maybe<&2, Abort.AbortSignal<Unit>>, ~Bool, ~H.abort, Unit{})
    config : Validation.Config() = T.AgentLoopConfig{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String), Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, Bool.pick(Maybe<&2, T.ToolExecutionMode>, continues(mode), Some{T.Parallel{}}, None{}), Bool.pick(Maybe<&2, C.Callback<BeforeInput(), BeforeOutput()>>, U32.is_eq(mode, 1) || U32.is_eq(mode, 2), Some{beforeCallback}, None{}), Bool.pick(Maybe<&2, C.Callback<Tools.HookInput(), Tools.HookOutput()>>, U32.is_eq(mode, 4), Some{afterCallback}, None{})}
    context : Validation.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "Echo tool", Tools.schema(), None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    +run : H.StreamRun() <- W.agentLoop(~Unit, ~String, ~String, ~String, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, Turns.user(Bool.pick(String, continues(mode), "echo both", "echo something")) <> Nil{}, context, config, W.Options{None{}, validator, aborted, "empty", Defaults.Explicit{providerCallback}})
    +iterator : S.Iterator<Validation.EventValue(), H.Outcome()> <- W.iterator(Unit, String, String, String, run)
    events : List<&2, String> <- Turns.collect(iterator, Nil{}, None{})
    Test.assertion(U32.is_eq(occurrences(events, "turn_end"), Bool.pick(U32, continues(mode), 2, 1)), "original turn-end count")
    outcome : H.Outcome() <- W.streamOutcome(Unit, String, String, String, run)
    checkOutcome(mode, outcome)
    S.disposeIterator(Validation.EventValue(), H.Outcome(), iterator)
    W.disposeStreamRun(Unit, String, String, String, run)
    count : U32 <- R.dispose(U32, counter)
    Test.assertion(U32.is_eq(count, Bool.pick(U32, continues(mode), 2, 1)), "original provider call count")
    values : List<&2, String> <- R.dispose(List<&2, String>, executions)
    Test.assertion(executionCounts(mode, values), "blocked calls never execute; expected arguments execute once")
    hookValues : List<&2, String> <- R.dispose(List<&2, String>, hooks)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, hookValues), "|"), expectedHooks(mode)), "expected before/after hooks")
    C.dispose(Validation.ExecuteInput(), Validation.ExecuteOutput(), executor)
    C.dispose(BeforeInput(), BeforeOutput(), beforeCallback)
    C.dispose(Tools.HookInput(), Tools.HookOutput(), afterCallback)
    C.dispose(H.ProviderInput(), H.ProviderOutput(), providerCallback)
    C.dispose(Validation.Messages(), Validation.Converted(), converter)
    C.dispose(Validation.Input(), Validation.Checked(), validator)
    C.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, aborted)
    owned : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(owned)
    IO.print("PASS " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(0, "should stop after a tool batch when every tool result sets terminate=true")
    scenario(1, "should stop after a blocked tool call when beforeToolCall sets terminate=true")
    scenario(2, "should continue after a mixed batch with one terminating blocked call")
    scenario(3, "should continue after parallel tool calls when not all tool results terminate")
    scenario(4, "should allow afterToolCall to mark a tool batch as terminating")
