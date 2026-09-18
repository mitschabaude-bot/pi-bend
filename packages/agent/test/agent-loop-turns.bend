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

type Preparing is Data:
  Preparing{calls: R.Ref<U32>, log: H.Log()}
type Provider is Data:
  Provider{stopRun: Bool, calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}

def user(text: String) -> T.AgentMessage<V.Value, V.Value, Unit, String, String>:
  T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, F.fromU32(0)}}}
def guidance() -> T.AgentMessage<V.Value, V.Value, Unit, String, String>:
  T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"updated guidance"}, None{}, None{}, None{}, F.fromU32(1)}}}

def roles(messages: Validation.Messages()) -> String:
  match messages:
    case Nil{}: ""
    case T.LlmMessage{Ai.System{_}} <> rest: "system|" ++ roles(rest)
    case T.LlmMessage{Ai.User{_}} <> rest: "user|" ++ roles(rest)
    case T.LlmMessage{Ai.Assistant{_}} <> rest: "assistant|" ++ roles(rest)
    case T.LlmMessage{Ai.ToolResult{_}} <> rest: "toolResult|" ++ roles(rest)
    case _ <> rest: "custom|" ++ roles(rest)

def checkTurn(input: H.Turn()) -> IO(Unit):
  match input:
    case T.ShouldStopAfterTurnContext{message, Ai.ToolResultMessage{id, _, _, _, _, False{}, _} <> Nil{}, T.AgentContext{messages, _}, history}:
      Test.assertion(String.eq(H.assistantName(message), "assistant:tool") && String.eq(id, "tool-1") && String.eq(roles(messages), "system|user|assistant|toolResult|") && String.eq(roles(history), "system|user|assistant|toolResult|"), "hook receives assistant, completed tool result, committed context and generated history")
    case _: Test.assertion(False{}, "completed tool turn snapshot")

def nextUpdate(index: U32, context: Validation.Context()) -> H.PrepareOutput():
  match index:
    case 0: Done{Some{T.AgentLoopTurnUpdate{Some{context}, Some{guidance() <> Nil{}}, None{}, None{}}}}
    case _: Done{None{}}

def updateFrom(index: U32, input: H.Turn()) -> H.PrepareOutput():
  match input:
    case T.ShouldStopAfterTurnContext{_, _, context, _}: nextUpdate(index, context)

def prepare(environment: Preparing, input: H.Turn()) -> IO(H.PrepareOutput()):
  match environment:
    case Preparing{calls, recording}:
      +input = input
      do IO<H.PrepareOutput()>:
        checkTurn(input)
        H.log(recording, "prepare")
        index : U32 <- H.bump(calls)
        return updateFrom(index, input)

def stop(recording: H.Log(), input: H.Turn()) -> IO(Result<&2, &2, String, Bool>):
  do IO<Result<&2, &2, String, Bool>>:
    checkTurn(input)
    H.log(recording, "stop")
    return Done{True{}}

def steering(recording: H.Log(), unused: Unit) -> IO(H.QueueOutput()):
  do IO<H.QueueOutput()>:
    H.log(recording, "steering")
    return Done{Nil{}}

def followUp(recording: H.Log(), unused: Unit) -> IO(H.QueueOutput()):
  do IO<H.QueueOutput()>:
    H.log(recording, "followUp")
    return Done{user("follow up should stay queued") <> Nil{}}

def execute(recording: H.Log(), input: Validation.ExecuteInput()) -> IO(Validation.ExecuteOutput()):
  match input:
    case T.ToolExecutionInput{id, args, _, _}:
      do IO<Validation.ExecuteOutput()>:
        Test.assertion(String.eq(id, "tool-1") && V.equal(args, Validation.field(V.Text{"hello"})), "original tool execution")
        H.log(recording, "hello")
        return Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"echoed: hello", None{}}} <> Nil{}, "hello", None{}, None{}}}

def hasGuidance(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> Bool:
  match messages:
    case Nil{}: False{}
    case Ai.System{Ai.SystemMessage{Ai.SystemText{"updated guidance"}, _, _, _, _}} <> _: True{}
    case _ <> rest: hasGuidance(rest)

def checkRequest(stopRun: Bool, index: U32, messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> IO(Unit):
  match index:
    case 0: Test.assertion(Bool.not(hasGuidance(messages)), "first request precedes preparation")
    case 1: Test.assertion(Bool.not(stopRun) && hasGuidance(messages), "second provider request uses prepared guidance; stop suppresses this request")
    case _: Test.assertion(False{}, "no unexpected provider requests")

def provider(environment: Provider, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match environment input:
    case Provider{stopRun, calls, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, _}:
      do IO<H.ProviderOutput()>:
        +index : U32 <- H.bump(calls)
        checkRequest(stopRun, index, messages)
        +stream : H.StreamValue() <- S.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        S.push(Ai.AssistantMessageEvent<V.Value, Unit>, H.Assistant(), stream, Tools.response(False{}, index))
        return Done{stream}

@unsafe def collect(+iterator: S.Iterator<Validation.EventValue(), H.Outcome()>, reversed: List<&2, String>, step: Maybe<&2, S.Iteration<Validation.EventValue()>>) -> IO(List<&2, String>):
  match step:
    case None{}:
      do IO<List<&2, String>>:
        next : S.Iteration<Validation.EventValue()> <- S.nextValue(Validation.EventValue(), H.Outcome(), iterator)
        collect(iterator, reversed, Some{next})
    case Some{S.End{}}: IO.pure(List<&2, String>, List.reverse(&2, String, reversed))
    case Some{S.Yield{event}}: collect(iterator, T.eventType(V.Value, V.Value, Unit, String, String, T.AgentToolResult<String>, T.AgentToolResult<String>, event) <> reversed, None{})

def checkOutcome(stopRun: Bool, result: H.Outcome()) -> IO(Unit):
  match result:
    case Fail{_}: Test.assertion(False{}, "turn loop succeeds")
    case Done{messages}: Test.assertion(String.eq(roles(messages), Bool.pick(String, stopRun, "system|user|assistant|toolResult|", "system|user|assistant|toolResult|system|assistant|")), "complete run history at stop/preparation boundary")

def checkEvents(stopRun: Bool, events: List<&2, String>) -> IO(Unit):
  match stopRun:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: Test.assertion(String.eq(String.join(events, "|"), "agent_start|turn_start|message_start|message_end|message_start|message_end|message_start|message_end|tool_execution_start|tool_execution_end|message_start|message_end|turn_end|agent_end"), "exact original stop-hook event sequence")

def scenario(+stopMode: Bool, name: String) -> IO(Unit):
  do IO<Unit>:
    +recording : H.Log() <- R.new(List<&2, String>, Nil{})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +prepares : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +executor : C.Callback<Validation.ExecuteInput(), Validation.ExecuteOutput()> <- C.create(~H.Log(), ~Validation.ExecuteInput(), ~Validation.ExecuteOutput(), ~execute, recording)
    +preparer : C.Callback<H.Turn(), H.PrepareOutput()> <- C.create(~Preparing, ~H.Turn(), ~H.PrepareOutput(), ~prepare, Preparing{prepares, recording})
    +stopper : C.Callback<H.Turn(), Result<&2, &2, String, Bool>> <- C.create(~H.Log(), ~H.Turn(), ~Result<&2, &2, String, Bool>, ~stop, recording)
    +steeringCallback : C.Callback<Unit, H.QueueOutput()> <- C.create(~H.Log(), ~Unit, ~H.QueueOutput(), ~steering, recording)
    +followCallback : C.Callback<Unit, H.QueueOutput()> <- C.create(~H.Log(), ~Unit, ~H.QueueOutput(), ~followUp, recording)
    +providerCallback : H.ProviderFunction() <- C.create(~Provider, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, Provider{stopMode, calls, streams})
    +converter : C.Callback<Validation.Messages(), Validation.Converted()> <- C.create(~Unit, ~Validation.Messages(), ~Validation.Converted(), ~Tools.convert, Unit{})
    +validator : C.Callback<Validation.Input(), Validation.Checked()> <- C.create(~Unit, ~Validation.Input(), ~Validation.Checked(), ~Validation.validate, Unit{})
    +aborted : C.Callback<Maybe<&2, Unit>, Bool> <- C.create(~Unit, ~Maybe<&2, Unit>, ~Bool, ~H.abort, Unit{})
    config : Validation.Config() = T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, Bool.pick(Maybe<&2, C.Callback<H.Turn(), Result<&2, &2, String, Bool>>>, stopMode, Some{stopper}, None{}), Bool.pick(Maybe<&2, C.Callback<H.Turn(), H.PrepareOutput()>>, stopMode, None{}, Some{preparer}), Bool.pick(Maybe<&2, C.Callback<Unit, H.QueueOutput()>>, stopMode, Some{steeringCallback}, None{}), Bool.pick(Maybe<&2, C.Callback<Unit, H.QueueOutput()>>, stopMode, Some{followCallback}, None{}), None{}, None{}, None{}}
    context : Validation.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "Echo tool", Tools.schema(), None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    +run : H.StreamRun() <- W.agentLoop(~V.Value, ~Unit, ~String, ~String, ~V.Value, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, user("echo something") <> Nil{}, context, config, W.Options{None{}, validator, aborted, "empty", Defaults.Explicit{providerCallback}})
    +iterator : S.Iterator<Validation.EventValue(), H.Outcome()> <- W.iterator(V.Value, Unit, String, String, V.Value, Unit, String, run)
    events : List<&2, String> <- collect(iterator, Nil{}, None{})
    checkEvents(stopMode, events)
    outcome : H.Outcome() <- W.result(V.Value, Unit, String, String, V.Value, Unit, String, run)
    checkOutcome(stopMode, outcome)
    S.disposeIterator(Validation.EventValue(), H.Outcome(), iterator)
    W.dispose(V.Value, Unit, String, String, V.Value, Unit, String, run)
    count : U32 <- R.dispose(U32, calls)
    Test.assertion(U32.is_eq(count, Bool.pick(U32, stopMode, 1, 2)), "original provider call count")
    prepareCount : U32 <- R.dispose(U32, prepares)
    Test.assertion(U32.is_eq(prepareCount, Bool.pick(U32, stopMode, 0, 1)), "prepareNextTurn called once only when continuing")
    trace : List<&2, String> <- R.dispose(List<&2, String>, recording)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, trace), "|"), Bool.pick(String, stopMode, "steering|hello|stop", "hello|prepare")), "one execution, correct hook/poll counts, follow-up stays queued on stop")
    C.dispose(Validation.ExecuteInput(), Validation.ExecuteOutput(), executor)
    C.dispose(H.Turn(), H.PrepareOutput(), preparer)
    C.dispose(H.Turn(), Result<&2, &2, String, Bool>, stopper)
    C.dispose(Unit, H.QueueOutput(), steeringCallback)
    C.dispose(Unit, H.QueueOutput(), followCallback)
    C.dispose(H.ProviderInput(), H.ProviderOutput(), providerCallback)
    C.dispose(Validation.Messages(), Validation.Converted(), converter)
    C.dispose(Validation.Input(), Validation.Checked(), validator)
    C.dispose(Maybe<&2, Unit>, Bool, aborted)
    owned : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(owned)
    IO.print("PASS " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{}, "should use prepareNextTurn snapshot before continuing")
    scenario(True{}, "should stop after the current turn when shouldStopAfterTurn returns true")
