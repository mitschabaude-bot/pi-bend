import Base
import ../packages/agent/src/agent.bend as Agent
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/agent/src/stream-fn.bend as StreamFn
import ../packages/agent/src/types.bend as T
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/event-stream.bend as Stream
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/date.bend as Date
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/json-event.bend as JsonEvent

# AgentSession scenarios over a faux provider that answers each request with
# the next scripted text, as upstream's registerFauxProvider does. The
# checker tests/agent_session_check.py reads the printed JSON events and the
# session file.

def Input() -> Data: T.StreamInput<Unit, Tools.ToolDetails, Runtime.LoopConfig()>
def Output() -> Type: Result<&2, &1, Tools.ToolError, T.StreamLease<Unit, Tools.ToolError>>
def EventStream() -> Data: Stream.AssistantMessageEventStream(V.Value, Unit)

type Faux is Data:
  Faux{responses: R.Ref<List<&2, String>>, streams: R.Ref<List<&2, EventStream()>>}

def fauxModel() -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"faux-model", "Faux", Ai.OpenAIResponsesApi{}, "faux", "https://faux.invalid", False{}, None{}, Ai.InputText{} <> Nil{}, Ai.ModelCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), None{}}, U32.to_f64(128000), U32.to_f64(4096), None{}, None{}, None{}}

def reply(text: String, now: F64) -> Ai.AssistantMessage<V.Value, Unit>:
  Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}, "openai-responses", "faux", "faux-model", None{}, None{}, None{}, None{}, Agent.emptyUsage(), Ai.Stop{}, None{}, None{}, None{}, None{}, now}

def popResponse(responses: List<&2, String>) -> List<&2, String> & String:
  match responses:
    case Nil{}: (Nil{}, "(no scripted response)")
    case text <> rest: (rest, text)

def push(stream: EventStream(), event: Ai.AssistantMessageEvent<V.Value, Unit>) -> IO(Unit):
  Stream.push(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, stream, event)

def provider(faux: Faux, input: Input()) -> IO(Output()):
  match faux:
    case Faux{responses, streams}:
      do IO<Output()>:
        +text : String <- R.modify(List<&2, String>, String, responses, remaining => popResponse(remaining))
        +now : F64 <- Date.now()
        +stream : EventStream() <- Stream.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, EventStream()>, Unit, streams, old => (stream <> old, Unit{}))
        push(stream, Ai.Start{reply("", now)})
        push(stream, Ai.TextStart{U32.to_f64(0), reply("", now)})
        push(stream, Ai.TextDelta{U32.to_f64(0), text, reply(text, now)})
        push(stream, Ai.TextEnd{U32.to_f64(0), text, reply(text, now)})
        push(stream, Ai.StreamDone{Ai.DoneStop{}, reply(text, now)})
        return Done{T.borrowedStream(Unit, Tools.ToolError, stream)}

def line(value: V.Value) -> String:
  Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(value)), "null")

def printed(result: Result<&2, &2, String, V.Value>) -> IO(Unit):
  match result:
    case Done{value}: IO.print(line(value))
    case Fail{error}: IO.print("{\"type\":\"unrenderable\",\"error\":" ++ Decode.quote(error) ++ "}")

def observe(env: Unit, event: Session.AgentSessionEvent) -> IO(Unit):
  printed(JsonEvent.toSessionJsonEvent(event))

type Fixture is Data:
  Fixture{session: Session.AgentSession, listener: Session.Listener(), stream: Runtime.Stream(), validator: Loop.Validator(Tools.ToolError), converter: Runtime.Converter(), registry: StreamFn.Registry(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError), faux: Faux}

def options(stream: Runtime.Stream(), converter: Runtime.Converter(), sessionId: String) -> Agent.AgentOptions<Unit, Tools.ToolDetails, Runtime.Custom(), Tools.ToolError, Unit>:
  Agent.AgentOptions{Some{Agent.AgentInitialState{Some{"You are helpful."}, Some{fauxModel()}, Some{Ai.Off{}}, Some{Nil{}}, None{}}}, Some{converter}, None{}, Some{stream}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{sessionId}, None{}, None{}, None{}, None{}}

def requireAgent(result: Result<&2, &2, StreamFn.MissingDefault, Runtime.Owner()>) -> IO(Runtime.Owner()):
  match result:
    case Done{agent}: IO.pure(Runtime.Owner(), agent)
    case Fail{_}: IO.die(Runtime.Owner(), 1, "agent construction failed")

def requireSession(result: Sessions.Outcome(Session.Session())) -> IO(Session.Session()):
  match result:
    case Done{session}: IO.pure(Session.Session(), session)
    case Fail{error}: IO.die(Session.Session(), 1, Sessions.message(error))

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case Tuple{_, manager}: manager

def fixture(+stored: Session.Session(), +cwd: String, agentDir: String, responses: List<&2, String>) -> IO(Fixture):
  do IO<Fixture>:
    +responseRef : R.Ref<List<&2, String>> <- R.new(List<&2, String>, responses)
    +streams : R.Ref<List<&2, EventStream()>> <- R.new(List<&2, EventStream()>, Nil{})
    +stream : Runtime.Stream() <- C.create(~Faux, ~Input(), ~Output(), ~provider, Faux{responseRef, streams})
    +registry : StreamFn.Registry(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError) <- StreamFn.create(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError)
    +validator : Loop.Validator(Tools.ToolError) <- Loop.createPlain(~Tools.ToolError, ~Runtime.validationError)
    +converter : Runtime.Converter() <- Runtime.createConverter(False{})
    created : Result<&2, &2, StreamFn.MissingDefault, Runtime.Owner()> <- Agent.new(~Unit, ~Tools.ToolDetails, ~Runtime.Custom(), ~Tools.ToolError, ~Unit, options(stream, converter, Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, stored)), registry, validator, Tools.WriteDetails{})
    +agent : Runtime.Owner() <- requireAgent(created)
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.options())
    +session : Session.AgentSession <- Session.create(agent, stored, settingsOf(loaded), cwd)
    +listener : Session.Listener() <- C.create(~Unit, ~Session.AgentSessionEvent, ~Unit, ~observe, Unit{})
    Session.subscribe(session, listener)
    return Fixture{session, listener, stream, validator, converter, registry, Faux{responseRef, streams}}

def disposeStreams(streams: List<&2, EventStream()>) -> IO(Unit):
  match streams:
    case Nil{}: IO.pure(Unit, Unit{})
    case stream <> rest:
      do IO<Unit>:
        Stream.disposeAssistantMessageEventStream(V.Value, Unit, stream)
        disposeStreams(rest)

def teardown(value: Fixture) -> IO(Unit):
  match value:
    case Fixture{+session, +listener, stream, validator, converter, registry, Faux{responses, streams}}:
      do IO<Unit>:
        Session.unsubscribe(session, listener)
        C.dispose(Session.AgentSessionEvent, Unit, listener)
        +agent : Runtime.Owner() = Session.agentOf(session)
        Session.dispose(session)
        Agent.dispose(Unit, Tools.ToolDetails, Runtime.Custom(), Tools.ToolError, Unit, agent)
        StreamFn.dispose(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError, registry)
        Loop.disposeValidation(Tools.ToolError, validator)
        Runtime.disposeConverter(converter)
        C.dispose(Input(), Output(), stream)
        remaining : List<&2, String> <- R.dispose(List<&2, String>, responses)
        opened : List<&2, EventStream()> <- R.dispose(List<&2, EventStream()>, streams)
        disposeStreams(opened)

def reportPrompt(result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("{\"type\":\"prompt_done\"}")
    case Fail{error}: IO.print("{\"type\":\"prompt_failed\",\"error\":" ++ Decode.quote(error) ++ "}")

def reportSession(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    IO.print("{\"type\":\"session\",\"file\":" ++ Maybe.default(&2, String, Maybe.map(&2, String, String, Decode.quote, Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored)), "null") ++ ",\"entries\":" ++ Nat.show(List.length(&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>, S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)))) ++ "}")
    last : Maybe<&2, String> <- Session.getLastAssistantText(session)
    IO.print("{\"type\":\"last_assistant_text\",\"text\":" ++ Maybe.default(&2, String, Maybe.map(&2, String, String, Decode.quote, last), "null") ++ "}")

def sessionOf(value: Fixture) -> Session.AgentSession:
  match value:
    case Fixture{session, _, _, _, _, _, _}: session

# persist: a prompt on a persisted session writes the user and assistant entries.
def persistScenario(+dir: String, +agentDir: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.createSession(dir, Some{dir}, agentDir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +value : Fixture <- fixture(stored, dir, agentDir, "answer" <> Nil{})
    result : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "hello", Nil{}, None{})
    reportPrompt(result)
    reportSession(sessionOf(value))
    teardown(value)

# queue: a steering message queued before the prompt leaves the queue when its
# user message starts, and the run continues into it.
def queueScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(dir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +value : Fixture <- fixture(stored, dir, agentDir, "answer" <> "again" <> Nil{})
    Session.steer(sessionOf(value), "steered", Nil{})
    Session.followUp(sessionOf(value), "later", Nil{})
    result : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "hello", Nil{}, None{})
    reportPrompt(result)
    reportSession(sessionOf(value))
    teardown(value)

def reportOutcome(+label: String, result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("{\"type\":\"" ++ label ++ "\",\"ok\":true}")
    case Fail{error}: IO.print("{\"type\":\"" ++ label ++ "\",\"ok\":false,\"error\":" ++ Decode.quote(error) ++ "}")

def entryKinds(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case S.ThinkingLevelChangeEntry{_, level} <> rest: ("thinking_level_change:" ++ level) <> entryKinds(rest)
    case S.ModelChangeEntry{_, provider, model} <> rest: ("model_change:" ++ provider ++ "/" ++ model) <> entryKinds(rest)
    case S.SessionInfoEntry{_, name} <> rest: ("session_info:" ++ Maybe.default(&2, String, name, "")) <> entryKinds(rest)
    case S.SessionMessageEntry{_, _} <> rest: "message" <> entryKinds(rest)
    case _ <> rest: "other" <> entryKinds(rest)

def quotedAll(values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: Decode.quote(value) <> quotedAll(rest)

def reportEntries(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    IO.print("{\"type\":\"entries\",\"kinds\":[" ++ String.join(quotedAll(entryKinds(S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)))), ",") ++ "]}")

# mutate: thinking level, model and name changes become entries and events.
def mutateScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(dir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +value : Fixture <- fixture(stored, dir, agentDir, Nil{})
    thinking : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(sessionOf(value), Ai.Thinking{Ai.High{}})
    reportOutcome("set_thinking", thinking)
    model : Result<&2, &2, String, Unit> <- Session.setModel(sessionOf(value), fauxModel())
    reportOutcome("set_model", model)
    named : Result<&2, &2, String, Unit> <- Session.setSessionName(sessionOf(value), "title")
    reportOutcome("set_name", named)
    reportEntries(sessionOf(value))
    teardown(value)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "persist" <> dir <> agentDir <> Nil{}: persistScenario(dir, agentDir)
    case "queue" <> dir <> agentDir <> Nil{}: queueScenario(dir, agentDir)
    case "mutate" <> dir <> agentDir <> Nil{}: mutateScenario(dir, agentDir)
    case _: IO.die(Unit, 1, "usage: agent-session <persist|queue|mutate> <dir> <agentDir>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
