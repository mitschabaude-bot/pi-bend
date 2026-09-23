import Base
import ../src/agent.bend as Run
import ../src/agent.bend as Runtime
import ../src/agent.bend as State
import ../src/agent.bend as Life
import ../src/agent.bend as Plan
import ../src/agent.bend as Listeners
import ../src/agent.bend as Events
import ../src/agent.bend as Failure
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/agent-loop.bend as Emission
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/record.bend as Record
import ../../runtime/src/f64.bend as F
import ../../runtime/src/abort.bend as Abort
import ./message-events.bend as Test
import ../../runtime/src/fetch.bend as Fetch

def Owner() -> Data: Run.RunRuntime(Unit, Unit, String, String)
def Message() -> Data: Run.RunMessage(Unit, Unit, String)
def Messages() -> Data: List<&2, Message()>
def EventValue() -> Data: Run.RunEvent(Unit, Unit, String)
def Config() -> Data: Run.Config(Unit, Unit, String, String, Unit)
def Converted() -> Data: Result<&2, &2, String, List<&2, Ai.Message<Schema.Value, Schema.Value, Unit, Unit>>>
def ProviderInput() -> Data: T.StreamInput<Unit, Unit, Config()>
def StreamValue() -> Data: Stream.AssistantMessageEventStream(Schema.Value, Unit)
def ProviderOutput() -> Type: Result<&2, &1, String, T.StreamLease<Unit, String>>
def Claim() -> Data: Result<&2, &2, Life.ClaimError<String>, Life.Claimed<Plan.Plan<Message()>>>
def Completion() -> Data: Run.Completed<Unit, Unit, String, String>
def user(text: String) -> Message(): T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, F.fromU32(0)}}}
def assistant() -> Ai.AssistantMessage<Schema.Value, Unit>:
  Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"answer", None{}}} <> Nil{}, "unknown", "unknown", "unknown", None{}, None{}, None{}, None{}, Failure.emptyUsage(), Ai.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(0)}
def role(message: Message()) -> String:
  match message:
    case T.LlmMessage{Ai.System{_}}: "s"
    case T.LlmMessage{Ai.User{_}}: "u"
    case T.LlmMessage{Ai.Assistant{_}}: "a"
    case _: "?"
def roles(messages: Messages()) -> String:
  match messages:
    case Nil{}: ""
    case message <> rest: role(message) ++ roles(rest)
def llmRoles(messages: List<&2, Ai.Message<Schema.Value, Schema.Value, Unit, Unit>>) -> String:
  match messages:
    case Nil{}: ""
    case message <> rest: role(T.LlmMessage{message}) ++ llmRoles(rest)
def partial(message: Maybe<&2, Message()>) -> String:
  match message:
    case None{}: "-"
    case Some{value}: role(value)
def key(state: T.AgentState<Unit, Unit, String, String>) -> String:
  match state:
    case T.AgentState{_, _, _, messages, streaming, current, _, error}: roles(messages) ++ ":" ++ Bool.pick(String, streaming, "1", "0") ++ ":" ++ partial(current) ++ ":" ++ Maybe.default(&2, String, error, "none")
def eventName(+event: EventValue()) -> String:
  match event:
    case T.AgentStart{}: "agent_start"
    case T.TurnStart{}: "turn_start"
    case T.MessageStart{message}: "start:" ++ role(message)
    case T.MessageUpdate{message, _}: "update:" ++ role(message)
    case T.MessageEnd{message}: "end:" ++ role(message)
    case T.TurnEnd{_, _}: "turn_end"
    case T.AgentEnd{_}: "agent_end"
    case _: T.eventType(Unit, Unit, String, T.AgentToolResult<Unit>, T.AgentToolResult<Unit>, event)
type ListenerCapture is Data:
  ListenerCapture{runtime: Owner(), trace: R.Ref<String>, mode: U32}
def listener(capture: ListenerCapture, input: Listeners.Input<EventValue()>) -> IO(Emission.Emission<String>):
  match capture input:
    case ListenerCapture{runtime, trace, +mode} Listeners.Input{+event, _}:
      do IO<Emission.Emission<String>>:
        state : T.AgentState<Unit, Unit, String, String> <- Runtime.readRuntime(Unit, Unit, String, String, runtime)
        R.modify(String, Unit, trace, old => (old ++ eventName(event) ++ "@" ++ key(state) ++ ";", Unit{}))
        return Emission.EmissionReady{Bool.pick(Result<&2, &2, String, Unit>, (U32.is_eq(mode, 2) && String.eq(eventName(event), "agent_start")) || (U32.is_eq(mode, 8) && String.eq(eventName(event), "start:a")), Fail{"listener failed"}, Done{Unit{}})}
def converter(unused: Unit, messages: Messages()) -> IO(Converted()): IO.pure(Converted(), Done{State.defaultConvertToLlm(Unit, Unit, String, String, messages)})
def config(convert: C.Callback<Messages(), Converted()>) -> Config():
  T.AgentLoopConfig{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String), State.defaultModel(Ai.JsonValue), convert, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
def validate(mode: U32, input: Loop.ToolValidationInput) -> IO(Result<&2, &2, String, Schema.Value>):
  match mode:
    case 9: IO.pure(Result<&2, &2, String, Schema.Value>, Done{Schema.Null{}})
    case _: IO.die(Result<&2, &2, String, Schema.Value>, 1, "no tools should be validated")
def executeTool(unused: Unit, input: T.ToolExecutionInput<Unit>) -> IO(Result<&2, &2, String, T.AgentToolResult<Unit>>):
  match input:
    case T.ToolExecutionInput{id, _, Some{signal}, _}:
      do IO<Result<&2, &2, String, T.AgentToolResult<Unit>>>:
        cancelled : Bool <- Abort.aborted(Unit, signal)
        Test.assertion(String.eq(id, "call") && Bool.not(cancelled), "tool receives the call ID and active signal")
        return Done{T.AgentToolResult{Nil{}, Unit{}, None{}, None{}}}
    case _: IO.die(Result<&2, &2, String, T.AgentToolResult<Unit>>, 1, "missing tool signal")
def tools(mode: U32, execute: C.Callback<T.ToolExecutionInput<Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>>) -> Maybe<&2, List<&2, T.AgentTool<Unit, String>>>:
  match mode:
    case 9: Some{T.AgentTool{"echo", "Echo", Schema.ObjectValue{Record.Record{Record.Property{"type", Schema.Text{"object"}} <> Nil{}}}, None{}, "Echo", None{}, execute, None{}, None{}} <> Nil{}}
    case _: None{}
def response(tool: Bool) -> Ai.AssistantMessage<Schema.Value, Unit>:
  match tool:
    case False{}: assistant()
    case True{}: Ai.AssistantMessage{Ai.AssistantToolCall{Ai.ToolCall{"call", "echo", Schema.Null{}, None{}, None{}}} <> Nil{}, "unknown", "unknown", "unknown", None{}, None{}, None{}, None{}, Failure.emptyUsage(), Ai.ToolUse{}, None{}, None{}, None{}, None{}, F.fromU32(0)}
type ProviderCapture is Data:
  ProviderCapture{runtime: Owner(), mode: U32, streams: R.Ref<List<&2, StreamValue()>>, requests: R.Ref<String>}
def opened(mode: U32, +tool: Bool, streams: R.Ref<List<&2, StreamValue()>>) -> IO(ProviderOutput()):
  match mode:
    case 1: IO.pure(ProviderOutput(), Fail{"provider failed"})
    case 3: IO.pure(ProviderOutput(), Fail{"provider failed"})
    case 8: IO.pure(ProviderOutput(), Fail{"provider failed"})
    case _:
      do IO<ProviderOutput()>:
        +stream : StreamValue() <- Stream.createAssistantMessageEventStream(~Schema.Value, ~Unit)
        R.modify(List<&2, StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Ai.AssistantMessage<Schema.Value, Unit>, stream, Ai.Start{response(tool)})
        Stream.push(Ai.AssistantMessageEvent<Schema.Value, Unit>, Ai.AssistantMessage<Schema.Value, Unit>, stream, Ai.StreamDone{Bool.pick(Ai.DoneReason, tool, Ai.DoneToolUse{}, Ai.DoneStop{}), response(tool)})
        return Done{T.borrowedStream(Unit, String, stream)}
def cancelIf(runtime: Owner(), mode: U32) -> IO(Unit):
  match mode:
    case 3: Runtime.abortRuntime(Unit, Unit, String, String, runtime)
    case _: IO.pure(Unit, Unit{})
def requestAdded(+old: String, request: String) -> String & Bool:
  (old ++ request ++ ";", String.is_empty(old))
def provider(capture: ProviderCapture, input: ProviderInput()) -> IO(ProviderOutput()):
  match capture input:
    case ProviderCapture{runtime, +mode, streams, requests} T.StreamInput{_, Ai.TranscriptContext{messages}, Some{T.AgentLoopConfig{Ai.SimpleStreamOptions{Some{+signal}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}}}:
      do IO<ProviderOutput()>:
        cancelled : Bool <- Abort.aborted(Unit, signal)
        Test.assertion(Bool.not(cancelled), "new run forwards its live uncancelled signal")
        first : Bool <- R.modify(String, Bool, requests, old => requestAdded(old, llmRoles(messages)))
        cancelIf(runtime, mode)
        cancelled : Bool <- Abort.aborted(Unit, signal)
        Test.assertion(Bool.not(Bool.xor(cancelled, U32.is_eq(mode, 3))), "provider signal observes runtime cancellation")
        opened(mode, U32.is_eq(mode, 9) && first, streams)
    case _ _: IO.die(ProviderOutput(), 1, "provider missing full options or active signal")
def initialMessages(mode: U32) -> Maybe<&2, Messages()>:
  match mode:
    case 6: Some{user("old") <> Nil{}}
    case 7: Some{T.LlmMessage{Ai.Assistant{assistant()}} <> Nil{}}
    case _: None{}
def queue(+runtime: Owner(), mode: U32) -> IO(Unit):
  match mode:
    case 4: Runtime.steerRuntime(Unit, Unit, String, String, runtime, user("steer"))
    case 5: Runtime.followUpRuntime(Unit, Unit, String, String, runtime, user("follow"))
    case 7:
      do IO<Unit>:
        Runtime.steerRuntime(Unit, Unit, String, String, runtime, user("first"))
        Runtime.steerRuntime(Unit, Unit, String, String, runtime, user("second"))
    case _: IO.pure(Unit, Unit{})
def claim(+runtime: Owner(), mode: U32) -> IO(Claim()):
  match mode:
    case 6: Runtime.beginContinue(Unit, Unit, String, String, runtime)
    case 7: Runtime.beginContinue(Unit, Unit, String, String, runtime)
    case _: Runtime.beginPrompt(Unit, Unit, String, String, runtime, user("prompt") <> Nil{})
def requireClaim(value: Claim()) -> IO(Life.Claimed<Plan.Plan<Message()>>):
  match value:
    case Done{claimed}: IO.pure(Life.Claimed<Plan.Plan<Message()>>, claimed)
    case _: IO.die(Life.Claimed<Plan.Plan<Message()>>, 1, "run claim failed")
def identity(value: String) -> String: value
def declaration(error: Declaration.DeclarationError) -> String: "declaration failed"
def resultKey(result: Result<&2, &2, Events.DeliveryError<String>, Unit>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{Events.ListenerFailed{error}}: error
    case Fail{Events.OutsideRun{message}}: message
def finish(completed: Completion()) -> IO(String):
  match completed:
    case Run.Completed{outcome, resources}:
      do IO<String>:
        Run.runDispose(Unit, Unit, String, String, resources)
        return resultKey(outcome)
def disposeStreams(streams: List<&2, StreamValue()>) -> IO(Unit):
  match streams:
    case Nil{}: IO.pure(Unit, Unit{})
    case stream <> rest:
      do IO<Unit>:
        Stream.disposeAssistantMessageEventStream(Schema.Value, Unit, stream)
        disposeStreams(rest)
def scenario(+mode: U32, +expected: String) -> IO(Unit):
  do IO<Unit>:
    +executor : C.Callback<T.ToolExecutionInput<Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>> <- C.create(~Unit, ~T.ToolExecutionInput<Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~executeTool, Unit{})
    initial : State.AgentInitialState<Unit, Unit, String, String> = State.AgentInitialState{Some{"base"}, None{}, None{}, tools(mode, executor), initialMessages(mode)}
    +runtime : Owner() <- Runtime.newRuntime(Unit, Unit, String, String, initial, T.OneAtATime{}, T.OneAtATime{})
    +listeners : Run.Registry(Unit, Unit, String, String) <- Listeners.newListeners(EventValue(), String)
    +trace : R.Ref<String> <- R.new(String, "")
    +requests : R.Ref<String> <- R.new(String, "")
    +streams : R.Ref<List<&2, StreamValue()>> <- R.new(List<&2, StreamValue()>, Nil{})
    +observe : Listeners.Handler(EventValue(), String) <- C.create(~ListenerCapture, ~Listeners.Input<EventValue()>, ~Emission.Emission<String>, ~listener, ListenerCapture{runtime, trace, mode})
    ignored : Listeners.Subscription<EventValue(), String> <- Listeners.subscribeListeners(EventValue(), String, listeners, observe)
    +convert : C.Callback<Messages(), Converted()> <- C.create(~Unit, ~Messages(), ~Converted(), ~converter, Unit{})
    +validation : C.Callback<Loop.ToolValidationInput, Result<&2, &2, String, Schema.Value>> <- C.create(~U32, ~Loop.ToolValidationInput, ~Result<&2, &2, String, Schema.Value>, ~validate, mode)
    +stream : T.StreamFn(Unit, Unit, Config(), String) <- C.create(~ProviderCapture, ~ProviderInput(), ~ProviderOutput(), ~provider, ProviderCapture{runtime, mode, streams, requests})
    queue(runtime, mode)
    prepared : Claim() <- claim(runtime, mode)
    claimed : Life.Claimed<Plan.Plan<Message()>> <- requireClaim(prepared)
    completed : Completion() <- Run.runClaimedRun(~Unit, ~Unit, ~String, ~String, ~Unit, ~identity, ~identity, ~declaration, runtime, listeners, Run.Options{config(convert), Provider.Explicit{stream}, validation, Unit{}}, claimed)
    outcome : String <- finish(completed)
    Runtime.waitForIdleRuntime(Unit, Unit, String, String, runtime)
    state : T.AgentState<Unit, Unit, String, String> <- Runtime.readRuntime(Unit, Unit, String, String, runtime)
    events : String <- R.read(String, trace)
    requested : String <- R.read(String, requests)
    +actual : String = events ++ "#" ++ outcome ++ "#" ++ key(state) ++ "#" ++ requested
    Test.assertion(String.eq(actual, expected), "composed Agent run mismatch: " ++ actual ++ " != " ++ expected)
    Listeners.disposeListeners(EventValue(), String, listeners)
    C.dispose(Listeners.Input<EventValue()>, Emission.Emission<String>, observe)
    C.dispose(Messages(), Converted(), convert)
    C.dispose(Loop.ToolValidationInput, Result<&2, &2, String, Schema.Value>, validation)
    C.dispose(ProviderInput(), ProviderOutput(), stream)
    C.dispose(T.ToolExecutionInput<Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>, executor)
    all : List<&2, StreamValue()> <- R.dispose(List<&2, StreamValue()>, streams)
    disposeStreams(all)
    old : String <- R.dispose(String, trace)
    old : String <- R.dispose(String, requests)
    old : Runtime.OwnedState<Unit, Unit, String, String> <- Runtime.disposeRuntime(Unit, Unit, String, String, runtime)
    return Unit{}
