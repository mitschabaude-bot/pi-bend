import Base
import ../src/loop-stream.bend as W
import ../src/loop-entry.bend as Entry
import ../src/stream-fn.bend as Defaults
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as S
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ./main-loop.bend as H
import ./validated-tool-execution.bend as Validation
import ./agent-loop-tools.bend as Tools
import ./message-events.bend as Test

type QueueState is Data:
  QueueState{executed: List<&2, String>, delivered: Bool}
type Provider is Data:
  Provider{calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}
def QueueResult() -> Data: Result<&2, &2, String, Validation.Messages()>

def recordExecution(state: QueueState, value: String) -> QueueState & Unit:
  match state:
    case QueueState{previous, delivered}: (QueueState{value <> previous, delivered}, Unit{})

def execute(state: R.Ref<QueueState>, input: Validation.ExecuteInput()) -> IO(Validation.ExecuteOutput()):
  match input:
    case T.ToolExecutionInput{+id, args, _, _}:
      do IO<Validation.ExecuteOutput()>:
        +value : String = Bool.pick(String, String.eq(id, "tool-1"), "first", "second")
        Test.assertion(V.equal(args, Validation.field(V.Text{value})), "original tool arguments")
        R.modify(QueueState, Unit, state, current => recordExecution(current, value))
        return Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"ok:" ++ value, None{}}} <> Nil{}, value, None{}, None{}}}

def poll(state: QueueState) -> QueueState & Bool:
  match state:
    case QueueState{Nil{}, delivered}: (QueueState{Nil{}, delivered}, False{})
    case QueueState{values, True{}}: (QueueState{values, True{}}, False{})
    case QueueState{values, False{}}: (QueueState{values, True{}}, True{})

def steering(state: R.Ref<QueueState>, unused: Unit) -> IO(QueueResult()):
  do IO<QueueResult()>:
    deliver : Bool <- R.modify(QueueState, Bool, state, current => poll(current))
    return Done{Bool.pick(Validation.Messages(), deliver, T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"interrupt"}, F.fromU32(0)}}} <> Nil{}, Nil{})}

def call(id: String, value: String) -> Ai.AssistantContent<V.Value>:
  Ai.AssistantToolCall{Ai.ToolCall{id, "echo", Validation.field(V.Text{value}), None{}, None{}}}
def response(index: U32) -> Ai.AssistantMessageEvent<V.Value, Unit>:
  match index:
    case 0: Ai.StreamDone{Ai.DoneToolUse{}, H.assistant(call("tool-1", "first") <> call("tool-2", "second") <> Nil{}, Ai.ToolUse{})}
    case _: Ai.StreamDone{Ai.DoneStop{}, H.assistant(H.text("done"), Ai.Stop{})}

def transcriptIds(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case Ai.ToolResult{Ai.ToolResultMessage{id, _, _, _, _, _, _}} <> rest: id <> transcriptIds(rest)
    case _ <> rest: transcriptIds(rest)

def containsInterrupt(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> Bool:
  match messages:
    case Nil{}: False{}
    case Ai.User{Ai.UserMessage{Ai.UserText{"interrupt"}, _}} <> _: True{}
    case _ <> rest: containsInterrupt(rest)

def checkRequest(index: U32, +messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> IO(Unit):
  match index:
    case 0: Test.assertion(Bool.not(containsInterrupt(messages)), "no premature steering")
    case 1: Test.assertion(containsInterrupt(messages) && String.eq(String.join(transcriptIds(messages), ","), "tool-1,tool-2"), "second provider request includes both tool results and interrupt")
    case _: Test.assertion(False{}, "two provider requests")

def provider(environment: Provider, input: H.ProviderInput()) -> IO(H.StreamValue()):
  match environment input:
    case Provider{calls, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, _}:
      do IO<H.StreamValue()>:
        +index : U32 <- H.bump(calls)
        checkRequest(index, messages)
        +stream : H.StreamValue() <- S.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        S.push(Ai.AssistantMessageEvent<V.Value, Unit>, H.Assistant(), stream, response(index))
        return stream

def observe(event: Validation.EventValue()) -> IO(String):
  match event:
    case T.ToolExecutionEnd{id, name, _, error}:
      do IO<String>:
        Test.assertion(String.eq(name, "echo") && Bool.not(error), "both tool ends succeed")
        return "end:" ++ id
    case T.MessageStart{T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id, _, _, _, _, False{}, _}}}}: IO.pure(String, "tool:" ++ id)
    case T.MessageStart{T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, _}}}}: IO.pure(String, text)
    case _: IO.pure(String, "")

@unsafe def consume(+iterator: S.Iterator<Validation.EventValue(), H.Outcome()>, +reversed: List<&2, String>, step: Maybe<&2, S.Iteration<Validation.EventValue()>>) -> IO(List<&2, String>):
  match step:
    case None{}:
      do IO<List<&2, String>>:
        next : S.Iteration<Validation.EventValue()> <- S.nextValue(Validation.EventValue(), H.Outcome(), iterator)
        consume(iterator, reversed, Some{next})
    case Some{S.End{}}: IO.pure(List<&2, String>, List.reverse(&2, String, reversed))
    case Some{S.Yield{event}}:
      do IO<List<&2, String>>:
        +key : String <- observe(event)
        consume(iterator, Bool.pick(List<&2, String>, String.is_empty(key), reversed, key <> reversed), None{})

def checkOutcome(result: H.Outcome()) -> IO(Unit):
  match result:
    case Done{messages}: Test.assertion(String.eq(String.join(transcriptIds(H.converted(messages)), ","), "tool-1,tool-2"), "run result persists source order")
    case Fail{_}: Test.assertion(False{}, "steering loop succeeds")

def checkState(state: QueueState) -> IO(Unit):
  match state:
    case QueueState{values, delivered}: Test.assertion(delivered && String.eq(String.join(List.reverse(&2, String, values), ","), "first,second"), "both tools executed in order and steering delivered once")

def main() -> IO(Unit):
  do IO<Unit>:
    +queue : R.Ref<QueueState> <- R.new(QueueState, QueueState{Nil{}, False{}})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +executor : C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()> <- C.create(~R.Ref<QueueState>, ~Validation.ExecuteInput(), ~Validation.ExecuteOutput(), ~execute, queue)
    +providerCallback : H.ProviderFunction() <- C.create(~Provider, ~H.ProviderInput(), ~H.StreamValue(), ~provider, Provider{calls, streams})
    +converter : C.Callback<Validation.Messages(), Validation.Converted()> <- C.create(~Unit, ~Validation.Messages(), ~Validation.Converted(), ~Tools.convert, Unit{})
    +validator : C.Callback<Validation.Input(), Validation.Checked()> <- C.create(~Unit, ~Validation.Input(), ~Validation.Checked(), ~Validation.validate, Unit{})
    +aborted : C.Callback<Maybe<&2, Unit>, Bool> <- C.create(~Unit, ~Maybe<&2, Unit>, ~Bool, ~H.abort, Unit{})
    +queued : C.Callback<Unit, QueueResult()> <- C.create(~R.Ref<QueueState>, ~Unit, ~QueueResult(), ~steering, queue)
    config : Validation.Config() = T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, None{}, None{}, Some{queued}, None{}, Some{T.Sequential{}}, None{}, None{}}
    context : Validation.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "Echo tool", Tools.schema(), None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    +run : H.StreamRun() <- W.agentLoop(~V.Value, ~Unit, ~String, ~String, ~V.Value, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"start"}, F.fromU32(0)}}} <> Nil{}, context, config, W.Options{None{}, validator, aborted, "empty", Defaults.Explicit{providerCallback}})
    +iterator : S.Iterator<Validation.EventValue(), H.Outcome()> <- W.iterator(V.Value, Unit, String, String, V.Value, Unit, String, run)
    trace : List<&2, String> <- consume(iterator, Nil{}, None{})
    Test.assertion(String.eq(String.join(trace, "|"), "start|end:tool-1|tool:tool-1|end:tool-2|tool:tool-2|interrupt"), "queued input arrives after both successful tool result messages")
    outcome : H.Outcome() <- W.result(V.Value, Unit, String, String, V.Value, Unit, String, run)
    checkOutcome(outcome)
    S.disposeIterator(Validation.EventValue(), H.Outcome(), iterator)
    W.dispose(V.Value, Unit, String, String, V.Value, Unit, String, run)
    count : U32 <- R.dispose(U32, calls)
    Test.assertion(U32.is_eq(count, 2), "tool turn then final response")
    C.dispose(Unit, QueueResult(), queued)
    C.dispose(Validation.ExecuteInput(), Validation.ExecuteOutput(), executor)
    C.dispose(H.ProviderInput(), H.StreamValue(), providerCallback)
    C.dispose(Validation.Messages(), Validation.Converted(), converter)
    C.dispose(Validation.Input(), Validation.Checked(), validator)
    C.dispose(Maybe<&2, Unit>, Bool, aborted)
    owned : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(owned)
    finalState : QueueState <- R.dispose(QueueState, queue)
    checkState(finalState)
    IO.print("PASS should inject queued messages after all tool calls complete")
