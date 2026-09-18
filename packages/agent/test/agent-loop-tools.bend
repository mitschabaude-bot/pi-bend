import Base
import ../src/loop-stream.bend as W
import ../src/loop-entry.bend as Entry
import ../src/stream-fn.bend as Defaults
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as S
import ../../ai/test/model-types.bend as Model
import ../../ai/test/model-cost.bend as Cost
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as Bits
import ./main-loop.bend as H
import ./validated-tool-execution.bend as Validation
import ./message-events.bend as Test

def convert(unused: Unit, messages: Validation.Messages()) -> IO(Validation.Converted()):
  IO.pure(Validation.Converted(), Done{H.converted(messages)})

def HookInput() -> Data: T.ToolHookInput<T.AfterToolCallContext<V.Value, V.Value, Unit, String, String, V.Value, Unit, String>, Unit>
def HookOutput() -> Data: Result<&2, &2, String, Maybe<&2, T.AfterToolCallResult<String>>>

type Provider is Data:
  Provider{truncated: Bool, calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}

def equalNumber(a: F.F64, b: F.F64) -> Bool: Bits.equal(F.toBits(a), F.toBits(b))
def tenth(n: U32) -> F.F64: F.divide(F.fromU32(n), F.fromU32(10))
def usage(patched: Bool) -> Ai.Usage:
  match patched:
    case False{}: Ai.Usage{F.fromU32(1), F.fromU32(2), F.fromU32(3), F.fromU32(4), None{}, None{}, F.fromU32(10), Ai.UsageCost{tenth(1), tenth(2), tenth(3), tenth(4), F.fromU32(1)}}
    case True{}: Ai.Usage{F.fromU32(5), F.fromU32(6), F.fromU32(7), F.fromU32(8), None{}, None{}, F.fromU32(26), Ai.UsageCost{tenth(5), tenth(6), tenth(7), tenth(8), tenth(26)}}

def sameUsage(a: Ai.Usage, b: Ai.Usage) -> Bool:
  match a b:
    case Ai.Usage{a, b, c, d, None{}, None{}, total, cost} Ai.Usage{aa, bb, cc, dd, None{}, None{}, totalB, costB}:
      equalNumber(a, aa) && equalNumber(b, bb) && equalNumber(c, cc) && equalNumber(d, dd) && equalNumber(total, totalB) && Cost.sameCost(cost, costB)
    case _ _: False{}

def hasUsage(value: Maybe<&2, Ai.Usage>, patched: Bool) -> Bool:
  match value:
    case Some{value}: sameUsage(value, usage(patched))
    case None{}: False{}

def execute(recording: H.Log(), input: Validation.ExecuteInput()) -> IO(Validation.ExecuteOutput()):
  match input:
    case T.ToolExecutionInput{id, args, _, _}:
      do IO<Validation.ExecuteOutput()>:
        Test.assertion(String.eq(id, "tool-1") && V.equal(args, Validation.field(V.Text{"hello"})), "executor receives complete validated arguments")
        H.log(recording, "hello")
        return Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"echoed: hello", None{}}} <> Nil{}, "hello", Some{usage(False{})}, None{}}}

def after(recording: H.Log(), input: HookInput()) -> IO(HookOutput()):
  match input:
    case T.ToolHookInput{T.AfterToolCallContext{_, _, _, T.AgentToolResult{_, _, observed, _}, False{}, _}, _}:
      do IO<HookOutput()>:
        Test.assertion(hasUsage(observed, False{}), "afterToolCall observes original complete usage")
        H.log(recording, "after")
        return Done{Some{T.AfterToolCallResult{None{}, None{}, None{}, Some{usage(True{})}, None{}}}}
    case _: IO.die(HookOutput(), 1, "afterToolCall receives successful tool result")

def toolCall(truncated: Bool) -> Ai.ToolCall<V.Value>:
  Ai.ToolCall{"tool-1", "echo", Validation.field(V.Text{Bool.pick(String, truncated, "hel", "hello")}), None{}, None{}}

def response(+truncated: Bool, index: U32) -> Ai.AssistantMessageEvent<V.Value, Unit>:
  match index:
    case 0:
      Ai.StreamDone{Bool.pick(Ai.DoneReason, truncated, Ai.DoneLength{}, Ai.DoneToolUse{}), H.assistant(Ai.AssistantToolCall{toolCall(truncated)} <> Nil{}, Bool.pick(Ai.StopReason, truncated, Ai.Length{}, Ai.ToolUse{}))}
    case _: Ai.StreamDone{Ai.DoneStop{}, H.assistant(H.text("done"), Ai.Stop{})}

def validResult(+truncated: Bool, result: Ai.ToolResultMessage<String>) -> Bool:
  match result:
    case Ai.ToolResultMessage{id, name, Ai.TextImageText{Ai.TextContent{+text, _}} <> Nil{}, details, usageValue, error, _}:
      String.eq(id, "tool-1") && String.eq(name, "echo") && Bool.pick(Bool, error, truncated, Bool.not(truncated)) && Bool.pick(Bool, truncated, String.eq(text, "Tool call \"echo\" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments."), String.eq(text, "echoed: hello") && hasUsage(usageValue, True{}))
    case _: False{}

def resultInTranscript(+truncated: Bool, messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> Bool:
  match messages:
    case Nil{}: False{}
    case Ai.ToolResult{value} <> Ai.Assistant{_} <> _: False{}
    case Ai.ToolResult{value} <> Nil{}: validResult(truncated, value)
    case _ <> rest: resultInTranscript(truncated, rest)

def checkRequest(truncated: Bool, index: U32, messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> IO(Unit):
  match index:
    case 0: IO.pure(Unit, Unit{})
    case 1: Test.assertion(resultInTranscript(truncated, messages), "second provider request contains finalized tool result")
    case _: Test.assertion(False{}, "exactly two provider requests")

def provider(environment: Provider, input: H.ProviderInput()) -> IO(H.StreamValue()):
  match environment input:
    case Provider{+truncated, calls, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, _}:
      do IO<H.StreamValue()>:
        +index : U32 <- H.bump(calls)
        checkRequest(truncated, index, messages)
        +stream : H.StreamValue() <- S.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        S.push(Ai.AssistantMessageEvent<V.Value, Unit>, H.Assistant(), stream, response(truncated, index))
        return stream

def checkHistory(+truncated: Bool, messages: Validation.Messages()) -> IO(Unit):
  match messages:
    case T.LlmMessage{Ai.ToolResult{value}} <> T.LlmMessage{Ai.Assistant{message}} <> Nil{}:
      Test.assertion(validResult(truncated, value) && String.eq(H.assistantName(message), "assistant:done"), "persist patched usage/error result followed by final assistant")
    case _ <> rest: checkHistory(truncated, rest)
    case Nil{}: Test.assertion(False{}, "tool result and final assistant must be present")

def checkOutcome(truncated: Bool, outcome: H.Outcome()) -> IO(Unit):
  match outcome:
    case Done{messages}: checkHistory(truncated, messages)
    case Fail{_}: Test.assertion(False{}, "tool loop succeeds")

def checkEvent(+truncated: Bool, event: Validation.EventValue()) -> IO(U32):
  match event:
    case T.ToolExecutionStart{id, name, _}:
      do IO<U32>:
        Test.assertion(String.eq(id, "tool-1") && String.eq(name, "echo"), "tool execution start")
        return 1
    case T.ToolExecutionEnd{id, name, T.AgentToolResult{content, details, usageValue, _}, error}:
      do IO<U32>:
        Test.assertion(validResult(truncated, Ai.ToolResultMessage{id, name, content, Some{details}, usageValue, error, F.fromU32(0)}), "tool execution end preserves finalized usage or truncation error")
        return 10
    case _: IO.pure(U32, 0)

@unsafe def consume(+truncated: Bool, +iterator: S.Iterator<Validation.EventValue(), H.Outcome()>, count: U32, step: Maybe<&2, S.Iteration<Validation.EventValue()>>) -> IO(U32):
  match step:
    case None{}:
      do IO<U32>:
        next : S.Iteration<Validation.EventValue()> <- S.nextValue(Validation.EventValue(), H.Outcome(), iterator)
        consume(truncated, iterator, count, Some{next})
    case Some{S.End{}}: IO.pure(U32, count)
    case Some{S.Yield{event}}:
      do IO<U32>:
        increment : U32 <- checkEvent(truncated, event)
        consume(truncated, iterator, (count + increment : U32), None{})

def schema() -> V.Value:
  V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", Validation.field(V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"string"}} <> Nil{}}})} <> Record.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}

def scenario(+truncated: Bool, name: String) -> IO(Unit):
  do IO<Unit>:
    +recording : H.Log() <- R.new(List<&2, String>, Nil{})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +executor : C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()> <- C.create(~H.Log(), ~Validation.ExecuteInput(), ~Validation.ExecuteOutput(), ~execute, recording)
    +hook : C.Callback<HookInput(), HookOutput()> <- C.create(~H.Log(), ~HookInput(), ~HookOutput(), ~after, recording)
    +providerCallback : H.ProviderFunction() <- C.create(~Provider, ~H.ProviderInput(), ~H.StreamValue(), ~provider, Provider{truncated, calls, streams})
    +converter : C.Callback<Validation.Messages(), Validation.Converted()> <- C.create(~Unit, ~Validation.Messages(), ~Validation.Converted(), ~convert, Unit{})
    +validator : C.Callback<Validation.Input(), Validation.Checked()> <- C.create(~Unit, ~Validation.Input(), ~Validation.Checked(), ~Validation.validate, Unit{})
    +aborted : C.Callback<Maybe<&2, Unit>, Bool> <- C.create(~Unit, ~Maybe<&2, Unit>, ~Bool, ~H.abort, Unit{})
    config : Validation.Config() = T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Bool.pick(Maybe<&2, C.Callback<HookInput(), HookOutput()>>, truncated, None{}, Some{hook})}
    context : Validation.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "Echo tool", schema(), None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    +run : H.StreamRun() <- W.agentLoop(~V.Value, ~Unit, ~String, ~String, ~V.Value, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"echo something"}, F.fromU32(0)}}} <> Nil{}, context, config, W.Options{None{}, validator, aborted, "empty", Defaults.Explicit{providerCallback}})
    +iterator : S.Iterator<Validation.EventValue(), H.Outcome()> <- W.iterator(V.Value, Unit, String, String, V.Value, Unit, String, run)
    eventCount : U32 <- consume(truncated, iterator, 0, None{})
    Test.assertion(U32.is_eq(eventCount, 11), "one execution start and one execution end")
    outcome : H.Outcome() <- W.result(V.Value, Unit, String, String, V.Value, Unit, String, run)
    checkOutcome(truncated, outcome)
    S.disposeIterator(Validation.EventValue(), H.Outcome(), iterator)
    W.dispose(V.Value, Unit, String, String, V.Value, Unit, String, run)
    count : U32 <- R.dispose(U32, calls)
    Test.assertion(U32.is_eq(count, 2), "loop continues for final assistant after tool result")
    entries : List<&2, String> <- R.dispose(List<&2, String>, recording)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, entries), "|"), Bool.pick(String, truncated, "", "hello|after")), "executor and hook invocation counts; truncated arguments never execute")
    C.dispose(Validation.ExecuteInput(), Validation.ExecuteOutput(), executor)
    C.dispose(HookInput(), HookOutput(), hook)
    C.dispose(H.ProviderInput(), H.StreamValue(), providerCallback)
    C.dispose(Validation.Messages(), Validation.Converted(), converter)
    C.dispose(Validation.Input(), Validation.Checked(), validator)
    C.dispose(Maybe<&2, Unit>, Bool, aborted)
    owned : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(owned)
    IO.print("PASS " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{}, "should handle tool calls and results")
    scenario(True{}, "should not execute tool calls from a length-truncated assistant message")
