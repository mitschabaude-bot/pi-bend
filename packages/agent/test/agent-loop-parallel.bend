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
import ../../runtime/src/f64.bend as F
import ./main-loop.bend as H
import ./validated-tool-execution.bend as Validation
import ./agent-loop-tools.bend as Tools
import ./message-events.bend as Test

type Gates is Data:
  Gates{mode: U32, firstStarted: Chan(Unit), releaseFirst: Chan(Unit), firstResolved: R.Ref<Bool>, starts: R.Ref<U32>, executions: H.Log()}
type Provider is Data:
  Provider{mode: U32, calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}

def sequential(+mode: U32) -> Bool: U32.is_eq(mode, 1) || U32.is_eq(mode, 2)
def valueFor(mode: U32, +first: Bool) -> String:
  Bool.pick(String, U32.is_eq(mode, 2), Bool.pick(String, first, "a", "b"), Bool.pick(String, first, "first", "second"))
def nameFor(mode: U32, first: Bool) -> String:
  match mode:
    case 1: "slow"
    case 2: Bool.pick(String, first, "slow", "fast")
    case _: "echo"

def notifyBlocked(mode: U32, update: Maybe<&2, T.AgentToolUpdateCallback(String)>) -> IO(Unit):
  match update:
    case Some{callback}: Bool.pick(IO(Unit), sequential(mode), C.call(T.AgentToolResult<String>, Unit, callback, T.AgentToolResult{Nil{}, "blocked", None{}, None{}}), IO.pure(Unit, Unit{}))
    case None{}: Test.assertion(False{}, "executor update callback available")

def received(value: Maybe<&1, Unit>) -> IO(Unit):
  match value:
    case Some{Unit{}}: IO.pure(Unit, Unit{})
    case None{}: Test.assertion(False{}, "gate closed before handoff")

def executeCall(gates: Gates, id: String, update: Maybe<&2, T.AgentToolUpdateCallback(String)>) -> IO(Unit):
  match gates id:
    case Gates{+mode, started, release, resolved, _, recording} "tool-1":
      do IO<Unit>:
        H.log(recording, nameFor(mode, True{}) ++ ":" ++ valueFor(mode, True{}))
        sent : Bool <- Chan.send(Unit, started, Unit{})
        R.requireSent(sent)
        notifyBlocked(mode, update)
        ready : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        received(ready)
        R.write(Bool, resolved, True{})
    case Gates{+mode, started, _, resolved, _, recording} "tool-2":
      do IO<Unit>:
        ready : Maybe<&1, Unit> <- Chan.recv(Unit, started)
        received(ready)
        H.log(recording, nameFor(mode, False{}) ++ ":" ++ valueFor(mode, False{}))
        +finished : Bool <- R.read(Bool, resolved)
        Test.assertion(Bool.pick(Bool, sequential(mode), finished, Bool.not(finished)), "second tool observes required sequential or parallel completion state")
    case _ _: Test.assertion(False{}, "unexpected tool id")

def execute(gates: Gates, input: Validation.ExecuteInput()) -> IO(Validation.ExecuteOutput()):
  match gates input:
    case Gates{+mode, started, release, resolved, starts, recording} T.ToolExecutionInput{+id, args, _, update}:
      do IO<Validation.ExecuteOutput()>:
        +first : Bool = String.eq(id, "tool-1")
        +value : String = valueFor(mode, first)
        Test.assertion(V.equal(args, Validation.field(V.Text{value})), "original tool arguments")
        executeCall(Gates{mode, started, release, resolved, starts, recording}, id, update)
        return Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{Bool.pick(String, sequential(mode), nameFor(mode, first), "echoed") ++ ": " ++ value, None{}}} <> Nil{}, value, None{}, None{}}}

def call(+mode: U32, +first: Bool) -> Ai.AssistantContent<V.Value>:
  Ai.AssistantToolCall{Ai.ToolCall{Bool.pick(String, first, "tool-1", "tool-2"), nameFor(mode, first), Validation.field(V.Text{valueFor(mode, first)}), None{}, None{}}}
def response(+mode: U32, index: U32) -> Ai.AssistantMessageEvent<V.Value, Unit>:
  match index:
    case 0: Ai.StreamDone{Ai.DoneToolUse{}, H.assistant(call(mode, True{}) <> call(mode, False{}) <> Nil{}, Ai.ToolUse{})}
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

def provider(environment: Provider, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match environment input:
    case Provider{mode, calls, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, _}:
      do IO<H.ProviderOutput()>:
        +index : U32 <- H.bump(calls)
        checkRequest(index, messages)
        +stream : H.StreamValue() <- S.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        S.push(Ai.AssistantMessageEvent<V.Value, Unit>, H.Assistant(), stream, response(mode, index))
        return Done{T.borrowedStream(V.Value, Unit, String, stream)}

def releaseParallel(mode: U32, release: Chan(Unit)) -> IO(Unit):
  match mode:
    case 1: IO.pure(Unit, Unit{})
    case 2: IO.pure(Unit, Unit{})
    case _:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, release, Unit{})
        R.requireSent(sent)

def recordStart(gates: Gates) -> IO(String):
  match gates:
    case Gates{_, _, _, _, starts, _}:
      do IO<String>:
        previous : U32 <- H.bump(starts)
        return ""

def releaseBlocked(gates: Gates) -> IO(String):
  match gates:
    case Gates{mode, _, release, _, starts, _}:
      do IO<String>:
        count : U32 <- R.read(U32, starts)
        Test.assertion(sequential(mode) && U32.is_eq(count, 1), "sequential batch has not started the second call while first is suspended")
        sent : Bool <- Chan.send(Unit, release, Unit{})
        R.requireSent(sent)
        return ""

def releaseAfterSecond(gates: Gates, id: String) -> IO(Unit):
  match gates id:
    case Gates{+mode, _, release, resolved, _, _} "tool-2":
      do IO<Unit>:
        +finished : Bool <- R.read(Bool, resolved)
        Test.assertion(Bool.pick(Bool, sequential(mode), finished, Bool.not(finished)), "second execution-end respects mode")
        releaseParallel(mode, release)
    case _ _: IO.pure(Unit, Unit{})

def turnKey(values: List<&2, Ai.ToolResultMessage<String>>) -> String:
  match values:
    case Nil{}: ""
    case values: "turn:" ++ String.join(resultIds(values), ",")

def observe(gates: Gates, event: Validation.EventValue()) -> IO(String):
  match event:
    case T.ToolExecutionStart{_, _, _}: recordStart(gates)
    case T.ToolExecutionUpdate{_, _, _, _}: releaseBlocked(gates)
    case T.ToolExecutionEnd{+id, name, _, error}:
      do IO<String>:
        Test.assertion(Bool.not(error), "successful execution-end")
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

def tool(+mode: U32, +first: Bool, executor: C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()>) -> T.AgentTool<V.Value, V.Value, String, V.Value, Unit, String>:
  T.AgentTool{nameFor(mode, first), "Tool", Tools.schema(), None{}, "Tool", None{}, executor, None{}, Bool.pick(Maybe<&2, T.ToolExecutionMode>, U32.is_eq(mode, 3), Some{T.Parallel{}}, Bool.pick(Maybe<&2, T.ToolExecutionMode>, sequential(mode) && first, Some{T.Sequential{}}, None{}))}

def tools(+mode: U32, +executor: C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()>) -> List<&2, T.AgentTool<V.Value, V.Value, String, V.Value, Unit, String>>:
  Bool.pick(List<&2, T.AgentTool<V.Value, V.Value, String, V.Value, Unit, String>>, U32.is_eq(mode, 2), tool(mode, True{}, executor) <> tool(mode, False{}, executor) <> Nil{}, tool(mode, True{}, executor) <> Nil{})

def scenario(+mode: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +resolved : R.Ref<Bool> <- R.new(Bool, False{})
    +starts : R.Ref<U32> <- R.new(U32, 0)
    +recording : H.Log() <- R.new(List<&2, String>, Nil{})
    +gates : Gates = Gates{mode, started, release, resolved, starts, recording}
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +executor : C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()> <- C.create(~Gates, ~Validation.ExecuteInput(), ~Validation.ExecuteOutput(), ~execute, gates)
    +providerCallback : H.ProviderFunction() <- C.create(~Provider, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, Provider{mode, calls, streams})
    +converter : C.Callback<Validation.Messages(), Validation.Converted()> <- C.create(~Unit, ~Validation.Messages(), ~Validation.Converted(), ~Tools.convert, Unit{})
    +validator : C.Callback<Validation.Input(), Validation.Checked()> <- C.create(~Unit, ~Validation.Input(), ~Validation.Checked(), ~Validation.validate, Unit{})
    +aborted : C.Callback<Maybe<&2, Unit>, Bool> <- C.create(~Unit, ~Maybe<&2, Unit>, ~Bool, ~H.abort, Unit{})
    config : Validation.Config() = T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, Bool.pick(Maybe<&2, T.ToolExecutionMode>, U32.is_eq(mode, 0), Some{T.Parallel{}}, None{}), None{}, None{}}
    context : Validation.Context() = T.AgentContext{Nil{}, Some{tools(mode, executor)}}
    +run : H.StreamRun() <- W.agentLoop(~V.Value, ~Unit, ~String, ~String, ~V.Value, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{Bool.pick(String, sequential(mode), "run both", "echo both")}, F.fromU32(0)}}} <> Nil{}, context, config, W.Options{None{}, validator, aborted, "empty", Defaults.Explicit{providerCallback}})
    +iterator : S.Iterator<Validation.EventValue(), H.Outcome()> <- W.iterator(V.Value, Unit, String, String, V.Value, Unit, String, run)
    trace : List<&2, String> <- consume(gates, iterator, Nil{}, None{})
    Test.assertion(String.eq(String.join(trace, "|"), Bool.pick(String, sequential(mode), "end:tool-1|message:tool-1|end:tool-2|message:tool-2|turn:tool-1,tool-2", "end:tool-2|end:tool-1|message:tool-1|message:tool-2|turn:tool-1,tool-2")), "execution-end completion order; message-end and turn-end source order")
    outcome : H.Outcome() <- W.resultStream(V.Value, Unit, String, String, V.Value, Unit, String, run)
    checkOutcome(outcome)
    S.disposeIterator(Validation.EventValue(), H.Outcome(), iterator)
    W.disposeStreamRun(V.Value, Unit, String, String, V.Value, Unit, String, run)
    count : U32 <- R.dispose(U32, calls)
    Test.assertion(U32.is_eq(count, 2), "tool turn then final response")
    C.dispose(Validation.ExecuteInput(), Validation.ExecuteOutput(), executor)
    C.dispose(H.ProviderInput(), H.ProviderOutput(), providerCallback)
    C.dispose(Validation.Messages(), Validation.Converted(), converter)
    C.dispose(Validation.Input(), Validation.Checked(), validator)
    C.dispose(Maybe<&2, Unit>, Bool, aborted)
    owned : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(owned)
    finished : Bool <- R.dispose(Bool, resolved)
    Test.assertion(finished, "first tool completed after release")
    startedCount : U32 <- R.dispose(U32, starts)
    Test.assertion(U32.is_eq(startedCount, 2), "both tools started exactly once")
    executionLog : List<&2, String> <- R.dispose(List<&2, String>, recording)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, executionLog), "|"), nameFor(mode, True{}) ++ ":" ++ valueFor(mode, True{}) ++ "|" ++ nameFor(mode, False{}) ++ ":" ++ valueFor(mode, False{})), "original executor order and arguments")
    Chan.close(Unit, started)
    Chan.close(Unit, release)
    IO.print("PASS " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(0, "should emit tool_execution_end in completion order but persist tool results in source order")
    scenario(1, "should force sequential execution when a tool has executionMode=sequential even with default parallel config")
    scenario(2, "should force sequential execution when one of multiple tools has executionMode=sequential")
    scenario(3, "should allow parallel execution when all tools have executionMode=parallel")
