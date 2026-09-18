import Base
import ../../runtime/src/string-set.bend as Set
import ../src/agent.bend as Agent
import ../src/agent-options.bend as Options
import ../src/agent-run.bend as Run
import ../src/agent-state.bend as State
import ../src/agent-runtime.bend as Runtime
import ../src/agent-listeners.bend as Listeners
import ../src/agent-events.bend as Events
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/event-emission.bend as Emission
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/tool-declaration.bend as Declaration
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ./agent-run.bend as H
import ./message-events.bend as Test

def Owner() -> Data: Agent.Agent<Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit>
def Outcome() -> Data: Result<&2, &2, Agent.AgentError<String>, Unit>
def requireOwner(result: Result<&2, &2, Provider.MissingDefault, Owner()>) -> IO(Owner()):
  match result:
    case Done{agent}: IO.pure(Owner(), agent)
    case _: IO.die(Owner(), 1, "Agent construction failed")
def agentRuntime(agent: Owner()) -> H.Owner():
  match agent:
    case Agent.Agent{runtime, _, _, _, _, _}: runtime
def outcome(result: Outcome()) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{Agent.ClaimFailed{message}}: message
    case Fail{Agent.DeliveryFailed{error}}: H.resultKey(Fail{error})
def options(initial: State.AgentInitialState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.Signal(), String, Unit>, converter: Options.Converter(Unit, Unit, Unit, String, String), stream: Maybe<&2, T.StreamFn(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)>, supplied: Bool) -> Options.AgentOptions<Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit>:
  Options.AgentOptions{Some{initial}, Bool.pick(Maybe<&2, Options.Converter(Unit, Unit, Unit, String, String)>, supplied, Some{converter}, None{}), None{}, stream, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
type ProviderCapture is Data:
  ProviderCapture{runtime: R.Ref<Maybe<&2, H.Owner()>>, mode: U32, streams: R.Ref<List<&2, H.StreamValue()>>, requests: R.Ref<String>}
def defaults(config: Maybe<&2, H.Config()>) -> Bool:
  match config:
    case Some{T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{Ai.AutoTransport{}}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{T.Parallel{}}, _, _}}: True{}
    case _: False{}
def callProvider(state: Maybe<&2, H.Owner()>, mode: U32, streams: R.Ref<List<&2, H.StreamValue()>>, requests: R.Ref<String>, +input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match state input:
    case Some{runtime} T.StreamInput{_, _, config}:
      do IO<H.ProviderOutput()>:
        Test.assertion(defaults(config), "constructor forwards default auto transport and parallel tool execution")
        H.provider(H.ProviderCapture{runtime, mode, streams, requests}, input)
    case _ _: IO.die(H.ProviderOutput(), 1, "provider called before Agent construction")
def provider(capture: ProviderCapture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture:
    case ProviderCapture{runtime, mode, streams, requests}:
      do IO<H.ProviderOutput()>:
        state : Maybe<&2, H.Owner()> <- R.read(Maybe<&2, H.Owner()>, runtime)
        callProvider(state, mode, streams, requests, input)
def queue(+agent: Owner(), mode: U32) -> IO(Unit):
  match mode:
    case 4: Agent.steer(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, H.user("steer"))
    case 5: Agent.followUp(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, H.user("follow"))
    case 7:
      do IO<Unit>:
        Agent.steer(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, H.user("first"))
        Agent.steer(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, H.user("second"))
    case _: IO.pure(Unit, Unit{})
def prompt(agent: Owner(), mode: U32) -> IO(Outcome()):
  match mode:
    case 6: Agent.continueRun(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent)
    case 7: Agent.continueRun(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent)
    case _: Agent.prompt(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent, Agent.Message{H.user("prompt")})
type ListenerCapture is Data:
  ListenerCapture{agent: Owner(), original: H.ListenerCapture}
def isRejected(result: Outcome(), expected: String) -> Bool:
  match result:
    case Fail{Agent.ClaimFailed{message}}: String.eq(message, expected)
    case _: False{}
def resetRejected(result: Result<&2, &2, String, Unit>) -> Bool:
  match result:
    case Fail{message}: String.eq(message, "Agent is already processing. Wait for completion before resetting.")
    case _: False{}
def checkBusy(+agent: Owner(), event: H.EventValue()) -> IO(Unit):
  match event:
    case T.AgentStart{}:
      do IO<Unit>:
        prompted : Outcome() <- Agent.prompt(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent, Agent.Text{"busy", Nil{}})
        Test.assertion(isRejected(prompted, "Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion."), "public prompt rejects busy before normalization or execution")
        continued : Outcome() <- Agent.continueRun(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, ~H.identity, ~H.identity, ~H.declaration, agent)
        Test.assertion(isRejected(continued, "Agent is already processing. Wait for completion before continuing."), "public continuation rejects busy")
        reset : Result<&2, &2, String, Unit> <- Agent.reset(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        Test.assertion(resetRejected(reset), "busy reset preserves the current run")
        signal : Maybe<&2, Run.Signal()> <- Agent.signal(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        Test.assertion(Maybe.is_some(&2, Run.Signal(), signal), "awaited listener exposes the active signal")
    case _: IO.pure(Unit, Unit{})
def preservedPending(state: T.AgentState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.Signal(), String, Unit>, event: H.EventValue()) -> IO(Unit):
  match state event:
    case T.AgentState{_, _, _, _, True{}, _, pending, _} T.ToolExecutionStart{id, _, _}: Test.assertion(Set.contains(pending, id), "state update retains the started pending tool")
    case T.AgentState{_, _, _, _, True{}, _, pending, _} T.ToolExecutionEnd{id, _, _, _}: Test.assertion(Bool.not(Set.contains(pending, id)), "state update retains completed-tool removal")
    case T.AgentState{_, _, _, _, True{}, _, _, _} _: IO.pure(Unit, Unit{})
    case _ _: Test.assertion(False{}, "state update must not end the active run")
def listener(capture: ListenerCapture, input: Listeners.Input<H.EventValue(), Run.Signal()>) -> IO(Emission.Emission<String>):
  match capture input:
    case ListenerCapture{+agent, original} Listeners.Input{+event, signal}:
      do IO<Emission.Emission<String>>:
        Agent.setThinkingLevel(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, Ai.Off{})
        snapshot : T.AgentState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.Signal(), String, Unit> <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        preservedPending(snapshot, event)
        checkBusy(agent, event)
        H.listener(original, Listeners.Input{event, signal})
def missing(result: Result<&2, &2, Provider.MissingDefault, Owner()>) -> Bool:
  match result:
    case Fail{_}: True{}
    case _: False{}
def scenario(+mode: U32, +expected: String) -> IO(Unit):
  do IO<Unit>:
    +executor : C.Callback<T.ToolExecutionInput<Unit, Run.Signal(), Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>> <- C.create(~Unit, ~T.ToolExecutionInput<Unit, Run.Signal(), Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~H.executeTool, Unit{})
    initial : State.AgentInitialState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.Signal(), String, Unit> = State.AgentInitialState{Some{"base"}, None{}, None{}, H.tools(mode, executor), H.initialMessages(mode)}
    +trace : R.Ref<String> <- R.new(String, "")
    +requests : R.Ref<String> <- R.new(String, "")
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +slot : R.Ref<Maybe<&2, H.Owner()>> <- R.new(Maybe<&2, H.Owner()>, None{})
    +converter : Options.Converter(Unit, Unit, Unit, String, String) <- C.create(~Unit, ~H.Messages(), ~H.Converted(), ~H.converter, Unit{})
    +validate : C.Callback<Loop.ToolValidationInput<Schema.Value, Unit, Unit>, Result<&2, &2, String, Unit>> <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, mode)
    +stream : T.StreamFn(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String) <- C.create(~ProviderCapture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, ProviderCapture{slot, mode, streams, requests})
    +fallback : Provider.Registry(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String) <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    +supplied : Bool = U32.is_eq(mode, 0) || U32.is_eq(mode, 9)
    Provider.setDefaultStreamFn(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String, fallback, Some{stream})
    created : Result<&2, &2, Provider.MissingDefault, Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, options(initial, converter, Bool.pick(Maybe<&2, T.StreamFn(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)>, supplied, Some{stream}, None{}), supplied), fallback, validate, Unit{})
    +agent : Owner() <- requireOwner(created)
    R.write(Maybe<&2, H.Owner()>, slot, Some{agentRuntime(agent)})
    Provider.setDefaultStreamFn(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String, fallback, None{})
    +observe : Listeners.Handler(H.EventValue(), Run.Signal(), String) <- C.create(~ListenerCapture, ~Listeners.Input<H.EventValue(), Run.Signal()>, ~Emission.Emission<String>, ~listener, ListenerCapture{agent, H.ListenerCapture{agentRuntime(agent), trace, mode}})
    ignored : Listeners.Subscription<H.EventValue(), Run.Signal(), String> <- Agent.subscribe(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, observe)
    queue(agent, mode)
    result : Outcome() <- prompt(agent, mode)
    Agent.waitForIdle(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    state : T.AgentState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.Signal(), String, Unit> <- Agent.state(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    events : String <- R.read(String, trace)
    requested : String <- R.read(String, requests)
    +actual : String = events ++ "#" ++ outcome(result) ++ "#" ++ H.key(state) ++ "#" ++ requested
    Test.assertion(String.eq(actual, expected), "Agent owner mismatch: " ++ actual ++ " != " ++ expected)
    Agent.dispose(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    converted : H.Converted() <- C.call(H.Messages(), H.Converted(), converter, H.user("borrowed") <> Nil{})
    C.dispose(H.Messages(), H.Converted(), converter)
    C.dispose(Listeners.Input<H.EventValue(), Run.Signal()>, Emission.Emission<String>, observe)
    rejected : Result<&2, &2, Provider.MissingDefault, Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, Options.defaults(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit), fallback, validate, Unit{})
    Test.assertion(missing(rejected), "missing default is rejected by construction before any run")
    Provider.dispose(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String, fallback)
    C.dispose(Loop.ToolValidationInput<Schema.Value, Unit, Unit>, Result<&2, &2, String, Unit>, validate)
    C.dispose(H.ProviderInput(), H.ProviderOutput(), stream)
    C.dispose(T.ToolExecutionInput<Unit, Run.Signal(), Unit>, Result<&2, &2, String, T.AgentToolResult<Unit>>, executor)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    old : String <- R.dispose(String, trace)
    old : String <- R.dispose(String, requests)
    old : Maybe<&2, H.Owner()> <- R.dispose(Maybe<&2, H.Owner()>, slot)
    return Unit{}
