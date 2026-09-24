import Base
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as StreamFn
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../ai/src/utils/model-api.bend as Api
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch
import ./validated-tool-execution.bend as H
import ./main-loop.bend as M
import ./agent-loop-tools.bend as Tools
import ./message-events.bend as Test

# Upstream agent-loop.test.ts cases for finishTurn and prepareRequest. Each
# case is one script: the callbacks log into one trace, and the upstream
# assertions are read back from that trace.
#
# 0 runs finishTurn after tool-result messages and before turn_end
# 1 runs finishTurn for an error assistant before turn_end
# 2 runs finishTurn for an aborted assistant before turn_end
# 3 action:end skips queue polling and next-turn preparation
# 4 makes exactly one context-only request
# 5 lets a natural tool-result request satisfy continuation
# 6 lets a natural steering request satisfy continuation
# 7 lets a natural follow-up request satisfy continuation
# 8 prepares the initial request after pending messages and can replace request state
# 9 does not poll steering after prepareRequest
# 10 picks up steering queued during prepareNextTurn before the next request

def RequestInput() -> Data: T.ToolHookInput<T.PrepareRequestContext<Unit, String, String, String>>
def RequestOutput() -> Data: Result<&2, &2, String, Maybe<&2, T.AgentRequestUpdate<Unit, String, String, String>>>
def Prompts() -> Data: List<&2, String>

type Script is Data:
  Script{scenario: U32, log: M.Log(), queued: R.Ref<Prompts()>, streams: R.Ref<List<&2, M.StreamValue()>>}

def user(text: String) -> T.AgentMessage<Unit, String, String>:
  T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, F.fromU32(0)}}}

def users(texts: Prompts()) -> H.Messages():
  match texts:
    case Nil{}: Nil{}
    case text <> rest: user(text) <> users(rest)

def countOf(entries: List<&2, String>, +name: String) -> U32:
  match entries:
    case Nil{}: 0
    case entry <> rest: U32.add(Bool.pick(U32, String.eq(entry, name), 1, 0), countOf(rest, name))

def logged(log: M.Log(), name: String) -> IO(U32):
  do IO<U32>:
    entries : List<&2, String> <- R.read(List<&2, String>, log)
    return countOf(entries, name)

def includes(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>, +text: String) -> Bool:
  match messages:
    case Nil{}: False{}
    case Ai.User{Ai.UserMessage{Ai.UserText{value}, _}} <> rest: String.eq(value, text) || includes(rest, text)
    case _ <> rest: includes(rest, text)

def includesMessage(messages: H.Messages(), text: String) -> Bool: includes(M.converted(messages), text)

# The queued text a case looks for in its provider requests.
def watched(scenario: U32) -> String:
  match scenario:
    case 6: "steering"
    case 7: "follow-up"
    case _: "late steering"

def respond(scenario: U32, index: U32) -> M.Assistant():
  match scenario index:
    case 0 _: M.assistant(M.toolContent(), Ai.ToolUse{})
    case 1 _: M.assistant(M.text("error"), Ai.Error{})
    case 2 _: M.assistant(M.text("aborted"), Ai.Aborted{})
    case 3 _: M.assistant(M.toolContent(), Ai.ToolUse{})
    case 5 0: M.assistant(M.toolContent(), Ai.ToolUse{})
    case 10 0: M.assistant(M.toolContent(), Ai.ToolUse{})
    case _ _: M.assistant(M.text("done"), Ai.Stop{})

def isHigh(reasoning: Maybe<&2, Ai.ThinkingLevel>) -> Bool:
  match reasoning:
    case Some{Ai.High{}}: True{}
    case _: False{}

def checkReplacedRequest(scenario: U32, model: Ai.Model<Ai.JsonValue>, messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>, options: Maybe<&2, H.Config()>) -> IO(Unit):
  match scenario options:
    case 8 Some{T.AgentLoopConfig{streamOptions, _, _, _, _, _, _, _, _, _, _, _, _}}:
      Test.assertion(isHigh(Ai.reasoningOption(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String, streamOptions)) && String.eq(Api.name(Api.modelApi(Ai.JsonValue, model)), "replacement") && String.eq(M.llmNames(messages), "canonical projection|"), "the provider receives the replacement model, context and thinking level")
    case 8 None{}: Test.assertion(False{}, "the provider receives request options")
    case _ _: IO.pure(Unit, Unit{})

def provider(script: Script, input: M.ProviderInput()) -> IO(M.ProviderOutput()):
  match script input:
    case Script{+scenario, +log, _, streams} T.StreamInput{model, Ai.TranscriptContext{+messages}, options}:
      do IO<M.ProviderOutput()>:
        +index : U32 <- logged(log, "provider")
        Test.assertion(U32.is_lt(index, 3), "loop must settle rather than spin")
        M.log(log, "provider")
        M.log(log, Bool.pick(String, includes(messages, watched(scenario)), "request:included", "request:absent"))
        checkReplacedRequest(scenario, model, messages, options)
        +stream : M.StreamValue() <- Stream.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, M.StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        Stream.push(Ai.AssistantMessageEvent<V.Value, Unit>, M.Assistant(), stream, M.finalEvent(respond(scenario, index)))
        return Done{T.borrowedStream(Unit, String, stream)}

def execute(scenario: U32, input: H.ExecuteInput()) -> IO(H.ExecuteOutput()):
  IO.pure(H.ExecuteOutput(), Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"done", None{}}} <> Nil{}, Some{"tool"}, None{}, Some{U32.is_eq(scenario, 0)}}})

def lastRole(messages: H.Messages()) -> String:
  match messages:
    case Nil{}: ""
    case T.LlmMessage{Ai.ToolResult{_}} <> Nil{}: "toolResult"
    case _ <> Nil{}: "other"
    case _ <> rest: lastRole(rest)

def checkFinished(scenario: U32, turn: M.Turn()) -> IO(Unit):
  match scenario turn:
    case 0 T.AgentTurnContext{_, results, T.AgentContext{messages, _}, _}: Test.assertion(Nat.is_eq(List.length(&2, Ai.ToolResultMessage<String>, results), 1n) && String.eq(lastRole(messages), "toolResult"), "finishTurn sees the tool result in its context")
    case 1 T.AgentTurnContext{message, _, _, _}: Test.assertion(String.eq(M.assistantName(message), "assistant:error"), "finishTurn receives the error assistant")
    case 2 T.AgentTurnContext{message, _, _, _}: Test.assertion(String.eq(M.assistantName(message), "assistant:aborted"), "finishTurn receives the aborted assistant")
    case _ _: IO.pure(Unit, Unit{})

def decide(scenario: U32, index: U32) -> Maybe<&2, T.AgentTurnDecision>:
  match scenario index:
    case 1 _: Some{T.ContinueTurn{}}
    case 2 _: Some{T.ContinueTurn{}}
    case 3 _: Some{T.EndTurn{}}
    case 4 0: Some{T.ContinueTurn{}}
    case 5 0: Some{T.ContinueTurn{}}
    case 6 0: Some{T.ContinueTurn{}}
    case 7 0: Some{T.ContinueTurn{}}
    case _ _: None{}

def finish(script: Script, input: M.FinishInput()) -> IO(M.FinishOutput()):
  match script input:
    case Script{+scenario, +log, _, _} T.ToolHookInput{turn, _}:
      do IO<M.FinishOutput()>:
        checkFinished(scenario, turn)
        index : U32 <- logged(log, "finish")
        M.log(log, "finish")
        return Done{decide(scenario, index)}

def enqueue(queued: R.Ref<Prompts()>, text: String) -> IO(Unit):
  R.modify(Prompts(), Unit, queued, previous => (List.append(&2, String, previous, text <> Nil{}), Unit{}))

def prepareNext(script: Script, input: M.Turn()) -> IO(M.PrepareOutput()):
  match script:
    case Script{+scenario, +log, +queued, _}:
      do IO<M.PrepareOutput()>:
        M.log(log, "prepareNext")
        Bool.pick(IO(Unit), U32.is_eq(scenario, 10), enqueue(queued, "late steering"), IO.pure(Unit, Unit{}))
        return Done{None{}}

def replacement(context: T.AgentContext<Unit, String, String, String>) -> T.AgentRequestUpdate<Unit, String, String, String>:
  match context:
    case T.AgentContext{_, tools}: T.AgentRequestUpdate{Some{T.AgentContext{user("canonical projection") <> Nil{}, tools}}, Some{Model.model(Ai.CustomModelApi{"replacement"}, None{})}, Some{Ai.Thinking{Ai.High{}}}}

def requestUpdate(scenario: U32, index: U32, log: M.Log(), queued: R.Ref<Prompts()>, context: T.AgentContext<Unit, String, String, String>) -> IO(RequestOutput()):
  match scenario index context:
    case 8 _ T.AgentContext{+messages, tools}:
      do IO<RequestOutput()>:
        steered : U32 <- logged(log, "message_end:steering")
        Test.assertion(U32.is_eq(steered, 1) && includesMessage(messages, "steering"), "the pending steering message is completed and in the request context")
        return Done{Some{replacement(T.AgentContext{messages, tools})}}
    case 9 0 _:
      do IO<RequestOutput()>:
        enqueue(queued, "late steering")
        return Done{None{}}
    case _ _ _: IO.pure(RequestOutput(), Done{None{}})

def prepareRequest(script: Script, input: RequestInput()) -> IO(RequestOutput()):
  match script input:
    case Script{+scenario, +log, +queued, _} T.ToolHookInput{T.PrepareRequestContext{context, _, _}, _}:
      do IO<RequestOutput()>:
        index : U32 <- logged(log, "prepareRequest")
        M.log(log, "prepareRequest")
        requestUpdate(scenario, index, log, queued, context)

def steered(scenario: U32, index: U32, queued: R.Ref<Prompts()>) -> IO(M.QueueOutput()):
  match scenario index:
    case 6 1: IO.pure(M.QueueOutput(), Done{user("steering") <> Nil{}})
    case 8 0: IO.pure(M.QueueOutput(), Done{user("steering") <> Nil{}})
    case 9 _:
      do IO<M.QueueOutput()>:
        texts : Prompts() <- R.swap(Prompts(), queued, Nil{})
        return Done{users(texts)}
    case 10 _:
      do IO<M.QueueOutput()>:
        texts : Prompts() <- R.swap(Prompts(), queued, Nil{})
        return Done{users(texts)}
    case _ _: IO.pure(M.QueueOutput(), Done{Nil{}})

def steering(script: Script, unused: Unit) -> IO(M.QueueOutput()):
  match script:
    case Script{+scenario, +log, +queued, _}:
      do IO<M.QueueOutput()>:
        index : U32 <- logged(log, "steering")
        M.log(log, "steering")
        steered(scenario, index, queued)

def followed(scenario: U32, index: U32) -> M.QueueOutput():
  match scenario index:
    case 7 0: Done{user("follow-up") <> Nil{}}
    case 7 _: Done{Nil{}}
    case 6 _: Done{Nil{}}
    case _ _: Done{user("queued") <> Nil{}}

def followUp(script: Script, unused: Unit) -> IO(M.QueueOutput()):
  match script:
    case Script{+scenario, +log, _, _}:
      do IO<M.QueueOutput()>:
        index : U32 <- logged(log, "followUp")
        M.log(log, "followUp")
        return followed(scenario, index)

def eventKey(event: H.EventValue()) -> String:
  match event:
    case T.MessageEnd{T.LlmMessage{Ai.ToolResult{_}}}: "message_end:toolResult"
    case T.MessageEnd{T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, _}}}}: "message_end:" ++ text
    case T.MessageEnd{T.LlmMessage{Ai.Assistant{_}}}: "message_end:assistant"
    case T.TurnEnd{_, _}: "turn_end"
    case _: ""

def emit(log: M.Log(), event: H.EventValue()) -> IO(Loop.Emission<String>):
  do IO<Loop.Emission<String>>:
    +name : String = eventKey(event)
    Bool.pick(IO(Unit), String.is_empty(name), IO.pure(Unit, Unit{}), M.log(log, name))
    return Loop.EmissionReady{Done{Unit{}}}

def notAborted(unused: Unit, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Bool): IO.pure(Bool, False{})

def selected(-A: Data, enabled: Bool, value: A) -> Maybe<&2, A>: Bool.pick(Maybe<&2, A>, enabled, Some{value}, None{})

def usesFinish(+scenario: U32) -> Bool: U32.is_lt(scenario, 8)
def usesSteering(+scenario: U32) -> Bool: U32.is_eq(scenario, 1) || U32.is_eq(scenario, 2) || U32.is_eq(scenario, 3) || U32.is_eq(scenario, 6) || U32.is_eq(scenario, 7) || U32.is_eq(scenario, 8) || U32.is_eq(scenario, 9) || U32.is_eq(scenario, 10)
def usesFollowUp(+scenario: U32) -> Bool: U32.is_eq(scenario, 1) || U32.is_eq(scenario, 2) || U32.is_eq(scenario, 3) || U32.is_eq(scenario, 6) || U32.is_eq(scenario, 7)
def usesPrepareNext(+scenario: U32) -> Bool: U32.is_eq(scenario, 3) || U32.is_eq(scenario, 10)
def usesPrepareRequest(+scenario: U32) -> Bool: U32.is_eq(scenario, 8) || U32.is_eq(scenario, 9)

def lastThree(entries: List<&2, String>) -> String:
  match entries:
    case a <> b <> c <> Nil{}: a ++ "|" ++ b ++ "|" ++ c
    case _ <> rest: lastThree(rest)
    case Nil{}: ""

def finishOrder(entries: List<&2, String>) -> String:
  match entries:
    case Nil{}: ""
    case "finish" <> rest: "finish|" ++ finishOrder(rest)
    case "turn_end" <> rest: "turn_end|" ++ finishOrder(rest)
    case _ <> rest: finishOrder(rest)

def requests(entries: List<&2, String>) -> String:
  match entries:
    case Nil{}: ""
    case "request:included" <> rest: "included|" ++ requests(rest)
    case "request:absent" <> rest: "absent|" ++ requests(rest)
    case _ <> rest: requests(rest)

def verdict(scenario: U32, +entries: List<&2, String>, +providers: U32, +finishes: U32, +steerings: U32, +follows: U32) -> IO(Unit):
  match scenario:
    case 0: Test.assertion(String.eq(lastThree(entries), "message_end:toolResult|finish|turn_end"), "finishTurn runs after tool-result messages and before turn_end")
    case 1: Test.assertion(String.eq(finishOrder(entries), "finish|turn_end|") && U32.is_eq(providers, 1) && U32.is_eq(steerings, 1) && U32.is_eq(follows, 0), "an error turn finishes before turn_end and still exits")
    case 2: Test.assertion(String.eq(finishOrder(entries), "finish|turn_end|") && U32.is_eq(providers, 1) && U32.is_eq(steerings, 1) && U32.is_eq(follows, 0), "an aborted turn finishes before turn_end and still exits")
    case 3: Test.assertion(U32.is_eq(providers, 1) && U32.is_eq(steerings, 1) && U32.is_eq(follows, 0) && U32.is_eq(countOf(entries, "prepareNext"), 0), "action:end skips queue polling and next-turn preparation")
    case 4: Test.assertion(U32.is_eq(providers, 2) && U32.is_eq(finishes, 2), "exactly one context-only continuation request")
    case 5: Test.assertion(U32.is_eq(providers, 2) && U32.is_eq(finishes, 2), "the tool-result request satisfies continuation")
    case 8: Test.assertion(U32.is_eq(countOf(entries, "prepareRequest"), 1), "prepareRequest runs once for the single request")
    case 9: Test.assertion(String.eq(requests(entries), "absent|included|") && U32.is_eq(countOf(entries, "prepareRequest"), 2) && U32.is_eq(steerings, 3), "steering queued by prepareRequest waits for the next request")
    case 10: Test.assertion(U32.is_eq(providers, 2) && String.eq(requests(entries), "absent|included|"), "steering queued during prepareNextTurn reaches the next request")
    case _: Test.assertion(U32.is_eq(providers, 2) && U32.is_eq(finishes, 2) && String.eq(requests(entries), "absent|included|"), "the queued request satisfies continuation")

def check(scenario: U32, +entries: List<&2, String>) -> IO(Unit):
  verdict(scenario, entries, countOf(entries, "provider"), countOf(entries, "finish"), countOf(entries, "steering"), countOf(entries, "followUp"))

def decisionCase(+kind: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    +log : M.Log() <- R.new(List<&2, String>, Nil{})
    +queued : R.Ref<Prompts()> <- R.new(Prompts(), Nil{})
    +streams : R.Ref<List<&2, M.StreamValue()>> <- R.new(List<&2, M.StreamValue()>, Nil{})
    +script : Script = Script{kind, log, queued, streams}
    +executor : C.Callback<H.ExecuteInput(), H.ExecuteOutput()> <- C.create(~U32, ~H.ExecuteInput(), ~H.ExecuteOutput(), ~execute, kind)
    +validator : C.Callback<H.Input(), H.Checked()> <- C.create(~Unit, ~H.Input(), ~H.Checked(), ~H.validate, Unit{})
    +converter : C.Callback<H.Messages(), H.Converted()> <- C.create(~Unit, ~H.Messages(), ~H.Converted(), ~Tools.convert, Unit{})
    +providerCallback : M.ProviderFunction() <- C.create(~Script, ~M.ProviderInput(), ~M.ProviderOutput(), ~provider, script)
    +finisher : C.Callback<M.FinishInput(), M.FinishOutput()> <- C.create(~Script, ~M.FinishInput(), ~M.FinishOutput(), ~finish, script)
    +requester : C.Callback<RequestInput(), RequestOutput()> <- C.create(~Script, ~RequestInput(), ~RequestOutput(), ~prepareRequest, script)
    +preparer : C.Callback<M.Turn(), M.PrepareOutput()> <- C.create(~Script, ~M.Turn(), ~M.PrepareOutput(), ~prepareNext, script)
    +steeringCallback : C.Callback<Unit, M.QueueOutput()> <- C.create(~Script, ~Unit, ~M.QueueOutput(), ~steering, script)
    +followCallback : C.Callback<Unit, M.QueueOutput()> <- C.create(~Script, ~Unit, ~M.QueueOutput(), ~followUp, script)
    +aborted : C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool> <- C.create(~Unit, ~Maybe<&2, Abort.AbortSignal<Unit>>, ~Bool, ~notAborted, Unit{})
    +emitter : C.Callback<H.EventValue(), Loop.Emission<String>> <- C.create(~M.Log(), ~H.EventValue(), ~Loop.Emission<String>, ~emit, log)
    +sink : C.Callback<H.EventValue(), Result<&2, &2, String, Unit>> <- Loop.createAwaitedEventSink(~Unit, ~String, ~String, ~T.AgentToolResult<String>, ~T.AgentToolResult<String>, ~String, emitter)
    +updates : Loop.Owners(String, String) <- Loop.newOwners(String, String)
    +batches : Loop.Batches(Unit, String, String, String) <- Loop.newBatches(Unit, String, String, String)
    schema : V.Value = V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", H.field(V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"number"}} <> Nil{}}})} <> Record.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}
    context : H.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "", schema, None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    config : H.Config() = T.AgentLoopConfig{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String), Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, selected(C.Callback<M.FinishInput(), M.FinishOutput()>, usesFinish(kind), finisher), selected(C.Callback<RequestInput(), RequestOutput()>, usesPrepareRequest(kind), requester), selected(C.Callback<M.Turn(), M.PrepareOutput()>, usesPrepareNext(kind), preparer), selected(C.Callback<Unit, M.QueueOutput()>, usesSteering(kind), steeringCallback), selected(C.Callback<Unit, M.QueueOutput()>, usesFollowUp(kind), followCallback), None{}, None{}, None{}}
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    services : Loop.Services<Unit, String, String, String> = Loop.Services{Some{Abort.signal(Unit, controller)}, validator, aborted, emitter, sink, updates, batches, "empty"}
    outcome : M.Outcome() <- Loop.runAgentLoop(~Unit, ~String, ~String, ~String, ~Unit, ~M.render, ~M.declarationError, ~StreamFn.errorMessage, user("run") <> Nil{}, context, config, Loop.EntryCapture{services, StreamFn.Explicit{providerCallback}})
    Test.assertion(Result.is_done(&2, &2, String, H.Messages(), outcome), "the run completes")
    Loop.disposeBatches(Unit, String, String, String, batches)
    Loop.disposeOwners(String, String, updates)
    entries : List<&2, String> <- R.dispose(List<&2, String>, log)
    check(kind, List.reverse(&2, String, entries))
    C.dispose(H.ExecuteInput(), H.ExecuteOutput(), executor)
    C.dispose(H.Input(), H.Checked(), validator)
    C.dispose(H.Messages(), H.Converted(), converter)
    C.dispose(M.ProviderInput(), M.ProviderOutput(), providerCallback)
    C.dispose(M.FinishInput(), M.FinishOutput(), finisher)
    C.dispose(RequestInput(), RequestOutput(), requester)
    C.dispose(M.Turn(), M.PrepareOutput(), preparer)
    C.dispose(Unit, M.QueueOutput(), steeringCallback)
    C.dispose(Unit, M.QueueOutput(), followCallback)
    C.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, aborted)
    C.dispose(H.EventValue(), Result<&2, &2, String, Unit>, sink)
    C.dispose(H.EventValue(), Loop.Emission<String>, emitter)
    left : Prompts() <- R.dispose(Prompts(), queued)
    owned : List<&2, M.StreamValue()> <- R.dispose(List<&2, M.StreamValue()>, streams)
    M.disposeStreams(owned)
    IO.print("PASS " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    decisionCase(0, "runs finishTurn after tool-result messages and before turn_end")
    decisionCase(1, "runs finishTurn for a error assistant before turn_end without changing the hard exit")
    decisionCase(2, "runs finishTurn for a aborted assistant before turn_end without changing the hard exit")
    decisionCase(3, "action:end skips queue polling and next-turn preparation")
    decisionCase(4, "makes exactly one context-only request when no natural request satisfies continuation")
    decisionCase(5, "lets a natural tool-result request satisfy continuation")
    decisionCase(6, "lets a natural steering request satisfy continuation")
    decisionCase(7, "lets a natural follow-up request satisfy continuation")
    decisionCase(8, "prepares the initial request after pending messages and can replace request state")
    decisionCase(9, "does not poll steering after prepareRequest")
    decisionCase(10, "picks up steering queued during prepareNextTurn before the next request")
