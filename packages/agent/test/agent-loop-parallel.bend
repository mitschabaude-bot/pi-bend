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

type Gates is Data:
  Gates{firstStarted: Chan(Unit), releaseFirst: Chan(Unit), firstResolved: R.Ref<Bool>}
type Provider is Data:
  Provider{calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}

def received(value: Maybe<&1, Unit>) -> IO(Unit):
  match value:
    case Some{Unit{}}: IO.pure(Unit, Unit{})
    case None{}: Test.assertion(False{}, "gate closed before handoff")

def executeCall(gates: Gates, id: String) -> IO(Unit):
  match gates id:
    case Gates{started, release, resolved} "tool-1":
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        R.requireSent(sent)
        ready : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        received(ready)
        R.write(Bool, resolved, True{})
    case Gates{started, _, resolved} "tool-2":
      do IO<Unit>:
        ready : Maybe<&1, Unit> <- Chan.recv(Unit, started)
        received(ready)
        finished : Bool <- R.read(Bool, resolved)
        Test.assertion(Bool.not(finished), "second tool executes while first remains suspended")
    case _ _: Test.assertion(False{}, "unexpected tool id")

def execute(gates: Gates, input: Validation.ExecuteInput()) -> IO(Validation.ExecuteOutput()):
  match input:
    case T.ToolExecutionInput{+id, args, _, _}:
      do IO<Validation.ExecuteOutput()>:
        +value : String = Bool.pick(String, String.eq(id, "tool-1"), "first", "second")
        Test.assertion(V.equal(args, Validation.field(V.Text{value})), "original tool arguments")
        executeCall(gates, id)
        return Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"echoed: " ++ value, None{}}} <> Nil{}, value, None{}, None{}}}

def call(id: String, value: String) -> Ai.AssistantContent<V.Value>:
  Ai.AssistantToolCall{Ai.ToolCall{id, "echo", Validation.field(V.Text{value}), None{}, None{}}}
def response(index: U32) -> Ai.AssistantMessageEvent<V.Value, Unit>:
  match index:
    case 0: Ai.StreamDone{Ai.DoneToolUse{}, H.assistant(call("tool-1", "first") <> call("tool-2", "second") <> Nil{}, Ai.ToolUse{})}
    case _: Ai.StreamDone{Ai.DoneStop{}, H.assistant(H.text("done"), Ai.Stop{})}

def resultIds(messages: List<&2, Ai.ToolResultMessage<String>>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case Ai.ToolResultMessage{id, _, _, _, _, _, _} <> rest: id <> resultIds(rest)

def transcriptIds(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case Ai.ToolResult{Ai.ToolResultMessage{id, _, _, _, _, _, _}} <> rest: id <> transcriptIds(rest)
    case _ <> rest: transcriptIds(rest)

def checkRequest(index: U32, messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> IO(Unit):
  match index:
    case 0: IO.pure(Unit, Unit{})
    case 1: Test.assertion(String.eq(String.join(transcriptIds(messages), ","), "tool-1,tool-2"), "next provider request retains source order")
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

def releaseAfterSecond(gates: Gates, id: String) -> IO(Unit):
  match gates id:
    case Gates{_, release, resolved} "tool-2":
      do IO<Unit>:
        finished : Bool <- R.read(Bool, resolved)
        Test.assertion(Bool.not(finished), "second execution-end arrives before first resolves")
        sent : Bool <- Chan.send(Unit, release, Unit{})
        R.requireSent(sent)
    case _ _: IO.pure(Unit, Unit{})

def turnKey(values: List<&2, Ai.ToolResultMessage<String>>) -> String:
  match values:
    case Nil{}: ""
    case values: "turn:" ++ String.join(resultIds(values), ",")

def observe(gates: Gates, event: Validation.EventValue()) -> IO(String):
  match event:
    case T.ToolExecutionEnd{+id, name, _, error}:
      do IO<String>:
        Test.assertion(String.eq(name, "echo") && Bool.not(error), "successful execution-end")
        releaseAfterSecond(gates, id)
        return "end:" ++ id
    case T.MessageEnd{T.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id, _, _, _, _, False{}, _}}}}: IO.pure(String, "message:" ++ id)
    case T.TurnEnd{_, results}: IO.pure(String, turnKey(results))
    case _: IO.pure(String, "")

@unsafe def consume(+gates: Gates, +iterator: S.Iterator<Validation.EventValue(), H.Outcome()>, +reversed: List<&2, String>, step: Maybe<&2, S.Iteration<Validation.EventValue()>>) -> IO(List<&2, String>):
  match step:
    case None{}:
      do IO<List<&2, String>>:
        next : S.Iteration<Validation.EventValue()> <- S.nextValue(Validation.EventValue(), H.Outcome(), iterator)
        consume(gates, iterator, reversed, Some{next})
    case Some{S.End{}}: IO.pure(List<&2, String>, List.reverse(&2, String, reversed))
    case Some{S.Yield{event}}:
      do IO<List<&2, String>>:
        +key : String <- observe(gates, event)
        consume(gates, iterator, Bool.pick(List<&2, String>, String.is_empty(key), reversed, key <> reversed), None{})

def checkOutcome(result: H.Outcome()) -> IO(Unit):
  match result:
    case Done{messages}: Test.assertion(String.eq(String.join(transcriptIds(H.converted(messages)), ","), "tool-1,tool-2"), "run result persists source order")
    case Fail{_}: Test.assertion(False{}, "parallel loop succeeds")

def main() -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +resolved : R.Ref<Bool> <- R.new(Bool, False{})
    +gates : Gates = Gates{started, release, resolved}
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +executor : C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()> <- C.create(~Gates, ~Validation.ExecuteInput(), ~Validation.ExecuteOutput(), ~execute, gates)
    +providerCallback : H.ProviderFunction() <- C.create(~Provider, ~H.ProviderInput(), ~H.StreamValue(), ~provider, Provider{calls, streams})
    +converter : C.Callback<Validation.Messages(), Validation.Converted()> <- C.create(~Unit, ~Validation.Messages(), ~Validation.Converted(), ~Tools.convert, Unit{})
    +validator : C.Callback<Validation.Input(), Validation.Checked()> <- C.create(~Unit, ~Validation.Input(), ~Validation.Checked(), ~Validation.validate, Unit{})
    +aborted : C.Callback<Maybe<&2, Unit>, Bool> <- C.create(~Unit, ~Maybe<&2, Unit>, ~Bool, ~H.abort, Unit{})
    config : Validation.Config() = T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, Some{T.Parallel{}}, None{}, None{}}
    context : Validation.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "Echo tool", Tools.schema(), None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    +run : H.StreamRun() <- W.agentLoop(~V.Value, ~Unit, ~String, ~String, ~V.Value, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"echo both"}, F.fromU32(0)}}} <> Nil{}, context, config, W.Options{None{}, validator, aborted, "empty", Defaults.Explicit{providerCallback}})
    +iterator : S.Iterator<Validation.EventValue(), H.Outcome()> <- W.iterator(V.Value, Unit, String, String, V.Value, Unit, String, run)
    trace : List<&2, String> <- consume(gates, iterator, Nil{}, None{})
    Test.assertion(String.eq(String.join(trace, "|"), "end:tool-2|end:tool-1|message:tool-1|message:tool-2|turn:tool-1,tool-2"), "execution-end completion order; message-end and turn-end source order")
    outcome : H.Outcome() <- W.result(V.Value, Unit, String, String, V.Value, Unit, String, run)
    checkOutcome(outcome)
    S.disposeIterator(Validation.EventValue(), H.Outcome(), iterator)
    W.dispose(V.Value, Unit, String, String, V.Value, Unit, String, run)
    count : U32 <- R.dispose(U32, calls)
    Test.assertion(U32.is_eq(count, 2), "tool turn then final response")
    C.dispose(Validation.ExecuteInput(), Validation.ExecuteOutput(), executor)
    C.dispose(H.ProviderInput(), H.StreamValue(), providerCallback)
    C.dispose(Validation.Messages(), Validation.Converted(), converter)
    C.dispose(Validation.Input(), Validation.Checked(), validator)
    C.dispose(Maybe<&2, Unit>, Bool, aborted)
    owned : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(owned)
    finished : Bool <- R.dispose(Bool, resolved)
    Test.assertion(finished, "first tool completed after release")
    Chan.close(Unit, started)
    Chan.close(Unit, release)
    IO.print("PASS should emit tool_execution_end in completion order but persist tool results in source order")
