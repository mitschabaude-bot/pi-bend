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
import ../packages/runtime/src/record.bend as Rec
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/number-string.bend as Numbers
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/compaction/compaction.bend as Compaction
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/json-event.bend as JsonEvent
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/coding-agent/src/core/bash-executor.bend as BashExec
import ../packages/coding-agent/src/core/tools/bash.bend as Bash
import ../packages/runtime/src/child-process.bend as Child
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/coding-agent/src/core/skills.bend as Skills
import ../packages/coding-agent/src/core/prompt-templates.bend as Templates

# AgentSession scenarios over a faux provider that answers each request with
# the next scripted text, as upstream's registerFauxProvider does. The
# checker tests/agent_session_check.py reads the printed JSON events and the
# session file.

def Input() -> Data: T.StreamInput<Unit, Tools.ToolDetails, Runtime.LoopConfig()>
def Output() -> Type: Result<&2, &1, Tools.ToolError, T.StreamLease<Unit, Tools.ToolError>>
def EventStream() -> Data: Stream.AssistantMessageEventStream(V.Value, Unit)

# A gate holds one request open: the provider reports `started` and waits
# for `release`, which keeps the session streaming for the busy scenario.
type Gate is Data:
  Gate{started: Chan(Unit), release: Chan(Unit)}

type Faux is Data:
  Faux{responses: R.Ref<List<&2, String>>, streams: R.Ref<List<&2, EventStream()>>, gates: R.Ref<List<&2, Gate>>}

def popGate(gates: List<&2, Gate>) -> List<&2, Gate> & Maybe<&2, Gate>:
  match gates:
    case Nil{}: (Nil{}, None{})
    case gate <> rest: (rest, Some{gate})

def holdAt(gate: Maybe<&2, Gate>) -> IO(Unit):
  match gate:
    case None{}: IO.pure(Unit, Unit{})
    case Some{Gate{started, release}}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        R.requireSent(sent)
        released : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Unit{}

def fauxModel() -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"faux-model", "Faux", Ai.OpenAIResponsesApi{}, "faux", "https://faux.invalid", False{}, None{}, Ai.InputText{} <> Nil{}, None{}, Ai.ModelCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), None{}}, None{}, U32.to_f64(128000), U32.to_f64(4096), None{}, None{}, None{}}

# A scripted response is its text, optionally "text#tokens" to report that
# much context usage, "~text" to stop at the length limit, or "!message" to
# fail with that error message.
type Scripted is Data:
  Answered{text: String, stop: Ai.StopReason, tokens: F64}
  Failed{message: String}

def zero() -> F64: U32.to_f64(0)

def usageOf(+tokens: F64) -> Ai.Usage:
  Ai.Usage{tokens, zero(), zero(), zero(), None{}, None{}, tokens, Ai.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def reply(text: String, stop: Ai.StopReason, tokens: F64, now: F64) -> Ai.AssistantMessage<V.Value, Unit>:
  Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}, "openai-responses", "faux", "faux-model", None{}, None{}, None{}, None{}, usageOf(tokens), stop, None{}, None{}, None{}, None{}, now}

def failure(message: String, now: F64) -> Ai.AssistantMessage<V.Value, Unit>:
  Ai.AssistantMessage{Nil{}, "openai-responses", "faux", "faux-model", None{}, None{}, None{}, None{}, Agent.emptyUsage(), Ai.Error{}, None{}, Some{message}, None{}, None{}, now}

def popResponse(responses: List<&2, String>) -> List<&2, String> & String:
  match responses:
    case Nil{}: (Nil{}, "(no scripted response)")
    case text <> rest: (rest, text)

def push(stream: EventStream(), event: Ai.AssistantMessageEvent<V.Value, Unit>) -> IO(Unit):
  Stream.push(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, stream, event)

def withTokens(stop: Ai.StopReason, text: String, parts: List<&2, String>) -> Scripted:
  match parts:
    case answer <> tokens <> Nil{}: Answered{answer, stop, Numbers.toNumber(tokens)}
    case _: Answered{text, stop, zero()}

def answered(stop: Ai.StopReason, +text: String) -> Scripted: withTokens(stop, text, String.split(text, '#'))

def scripted(text: String) -> Scripted:
  match text:
    case SCon{'!', message}: Failed{message}
    case SCon{'~', rest}: answered(Ai.Length{}, rest)
    case _: answered(Ai.Stop{}, text)

def doneReason(stop: Ai.StopReason) -> Ai.DoneReason:
  match stop:
    case Ai.Length{}: Ai.DoneLength{}
    case _: Ai.DoneStop{}

def answer(+stream: EventStream(), script: Scripted, +now: F64) -> IO(Unit):
  match script:
    case Failed{message}:
      do IO<Unit>:
        push(stream, Ai.Start{reply("", Ai.Stop{}, zero(), now)})
        push(stream, Ai.StreamError{Ai.ErrorError{}, failure(message, now)})
    case Answered{+text, +stop, +tokens}:
      do IO<Unit>:
        push(stream, Ai.Start{reply("", stop, zero(), now)})
        push(stream, Ai.TextStart{zero(), reply("", stop, zero(), now)})
        push(stream, Ai.TextDelta{zero(), text, reply(text, stop, zero(), now)})
        push(stream, Ai.TextEnd{zero(), text, reply(text, stop, zero(), now)})
        push(stream, Ai.StreamDone{doneReason(stop), reply(text, stop, tokens, now)})

# A reply takes at least a millisecond, as a real provider's does: the
# compaction boundary compares millisecond timestamps, so a reply stamped in
# the compaction's own millisecond would count as pre-compaction.
def provider(faux: Faux, input: Input()) -> IO(Output()):
  match faux:
    case Faux{responses, streams, gates}:
      do IO<Output()>:
        gate : Maybe<&2, Gate> <- R.modify(List<&2, Gate>, Maybe<&2, Gate>, gates, remaining => popGate(remaining))
        holdAt(gate)
        text : String <- R.modify(List<&2, String>, String, responses, remaining => popResponse(remaining))
        IO.sleep(1)
        +now : F64 <- Date.now()
        +stream : EventStream() <- Stream.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, EventStream()>, Unit, streams, old => (stream <> old, Unit{}))
        answer(stream, scripted(text), now)
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

def options(stream: Runtime.Stream(), converter: Runtime.Converter(), sessionId: String, selected: Maybe<&2,Ai.Model<Ai.JsonValue>>) -> Agent.AgentOptions<Unit, Tools.ToolDetails, Runtime.Custom(), Tools.ToolError, Unit>:
  Agent.AgentOptions{Some{Agent.AgentInitialState{Some{""}, selected, Some{Ai.Off{}}, Some{Nil{}}, None{}}}, Some{converter}, None{}, Some{stream}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{sessionId}, None{}, None{}, None{}, None{}}

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

def fixtureWithModel(+stored: Session.Session(), +cwd: String, agentDir: String, responses: List<&2, String>, gates: List<&2, Gate>, +loadout: Runtime.Loadout, selected: Maybe<&2,Ai.Model<Ai.JsonValue>>) -> IO(Fixture):
  do IO<Fixture>:
    +responseRef : R.Ref<List<&2, String>> <- R.new(List<&2, String>, responses)
    +streams : R.Ref<List<&2, EventStream()>> <- R.new(List<&2, EventStream()>, Nil{})
    +gateRef : R.Ref<List<&2, Gate>> <- R.new(List<&2, Gate>, gates)
    +stream : Runtime.Stream() <- C.create(~Faux, ~Input(), ~Output(), ~provider, Faux{responseRef, streams, gateRef})
    +registry : StreamFn.Registry(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError) <- StreamFn.create(Unit, Tools.ToolDetails, Runtime.LoopConfig(), Tools.ToolError)
    +validator : Loop.Validator(Tools.ToolError) <- Loop.createPlain(~Tools.ToolError, ~Runtime.validationError)
    +converter : Runtime.Converter() <- Runtime.createConverter(False{})
    created : Result<&2, &2, StreamFn.MissingDefault, Runtime.Owner()> <- Agent.new(~Unit, ~Tools.ToolDetails, ~Runtime.Custom(), ~Tools.ToolError, ~Unit, options(stream, converter, Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, stored), selected), registry, validator, Tools.WriteDetails{})
    +agent : Runtime.Owner() <- requireAgent(created)
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.options())
    +session : Session.AgentSession <- Session.create(agent, stored, settingsOf(loaded), cwd, loadout)
    +listener : Session.Listener() <- C.create(~Unit, ~Session.AgentSessionEvent, ~Unit, ~observe, Unit{})
    Session.subscribe(session, listener)
    return Fixture{session, listener, stream, validator, converter, registry, Faux{responseRef, streams, gateRef}}

def fixtureWith(+stored: Session.Session(), +cwd: String, agentDir: String, responses: List<&2, String>, gates: List<&2, Gate>, +loadout: Runtime.Loadout) -> IO(Fixture):
  fixtureWithModel(stored,cwd,agentDir,responses,gates,loadout,Some{fauxModel()})

def fixtureNoModel(+stored: Session.Session(), +cwd: String, agentDir: String, responses: List<&2, String>, gates: List<&2, Gate>) -> IO(Fixture):
  fixtureWithModel(stored,cwd,agentDir,responses,gates,Runtime.Loadout{Rec.new(String),Nil{},Nil{},Nil{}},None{})

def fixture(+stored: Session.Session(), +cwd: String, agentDir: String, responses: List<&2, String>, gates: List<&2, Gate>) -> IO(Fixture):
  fixtureWith(stored, cwd, agentDir, responses, gates, Runtime.Loadout{Rec.new(String), Nil{}, Nil{}, Nil{}})

def disposeStreams(streams: List<&2, EventStream()>) -> IO(Unit):
  match streams:
    case Nil{}: IO.pure(Unit, Unit{})
    case stream <> rest:
      do IO<Unit>:
        Stream.disposeAssistantMessageEventStream(V.Value, Unit, stream)
        disposeStreams(rest)

def teardown(value: Fixture) -> IO(Unit):
  match value:
    case Fixture{+session, +listener, stream, validator, converter, registry, Faux{responses, streams, gates}}:
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
        unused : List<&2, Gate> <- R.dispose(List<&2, Gate>, gates)
        return Unit{}

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
    +value : Fixture <- fixture(stored, dir, agentDir, "answer" <> Nil{}, Nil{})
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
    +value : Fixture <- fixture(stored, dir, agentDir, "answer" <> "again" <> Nil{}, Nil{})
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
    case S.ModelChangeEntry{_, providerName, model} <> rest: ("model_change:" ++ providerName ++ "/" ++ model) <> entryKinds(rest)
    case S.SessionInfoEntry{_, name} <> rest: ("session_info:" ++ Maybe.default(&2, String, name, "")) <> entryKinds(rest)
    case S.SessionMessageEntry{_, _} <> rest: "message" <> entryKinds(rest)
    case S.Compaction{_} <> rest: "compaction" <> entryKinds(rest)
    case S.ContextEditEntry{_, _, None{}} <> rest: "context_edit:omit" <> entryKinds(rest)
    case S.ContextEditEntry{_, _, Some{_}} <> rest: "context_edit:replace" <> entryKinds(rest)
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
    +value : Fixture <- fixture(stored, dir, agentDir, Nil{}, Nil{})
    thinking : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(sessionOf(value), Ai.Thinking{Ai.High{}})
    reportOutcome("set_thinking", thinking)
    model : Result<&2, &2, String, Unit> <- Session.setModel(sessionOf(value), fauxModel())
    reportOutcome("set_model", model)
    named : Result<&2, &2, String, Unit> <- Session.setSessionName(sessionOf(value), "title")
    reportOutcome("set_name", named)
    reportEntries(sessionOf(value))
    teardown(value)

# busy: while the first request is held open, a plain prompt is refused with
# upstream's message, steer/followUp are queued, and the run finishes both.
def promptInBackground(session: Session.AgentSession, done: Chan(Result<&2, &2, String, Unit>)) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.prompt(session, "hello", Nil{}, None{})
    sent : Bool <- Chan.send(Result<&2, &2, String, Unit>, done, result)
    R.requireSent(sent)

def reportStreaming(session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    streaming : Bool <- Session.isStreaming(session)
    IO.print("{\"type\":\"streaming\",\"value\":" ++ Bool.pick(String, streaming, "true", "false") ++ "}")

def reportFinished(finished: Maybe<&1, Result<&2, &2, String, Unit>>) -> IO(Unit):
  match finished:
    case Some{result}: reportPrompt(result)
    case None{}: reportPrompt(Fail{"prompt fiber did not finish"})

def busyScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(dir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Result<&2, &2, String, Unit>) <- Chan.new(Result<&2, &2, String, Unit>, 1)
    +value : Fixture <- fixture(stored, dir, agentDir, "answer" <> "again" <> "finally" <> Nil{}, Gate{started, release} <> Nil{})
    IO.spawn(Unit, promptInBackground(sessionOf(value), done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    reportStreaming(sessionOf(value))
    refused : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "too early", Nil{}, None{})
    reportOutcome("prompt_while_streaming", refused)
    steered : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "steered", Nil{}, Some{Session.Steer{}})
    reportOutcome("steer_while_streaming", steered)
    followed : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "later", Nil{}, Some{Session.FollowUp{}})
    reportOutcome("follow_up_while_streaming", followed)
    sent : Bool <- Chan.send(Unit, release, Unit{})
    R.requireSent(sent)
    finished : Maybe<&1, Result<&2, &2, String, Unit>> <- Chan.recv(Result<&2, &2, String, Unit>, done)
    reportFinished(finished)
    reportStreaming(sessionOf(value))
    reportSession(sessionOf(value))
    teardown(value)
    Chan.close(Unit, started)
    Chan.close(Unit, release)
    Chan.close(Result<&2, &2, String, Unit>, done)

# retry: scripted failures drive the settings' retry policy; "cancel" aborts
# the first backoff sleep from another fiber as upstream's abortRetry test.
type RetrySignal is Data:
  RetrySignal{started: Chan(Unit)}

def signalStarted(started: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit, started, Unit{})
    return Unit{}

# Signals when a retry backoff, of the agent or of the summarizer, begins.
def signalRetry(env: RetrySignal, event: Session.AgentSessionEvent) -> IO(Unit):
  match env event:
    case RetrySignal{started} Session.AutoRetryStart{_, _, _, _}: signalStarted(started)
    case RetrySignal{started} Session.SummarizationRetryScheduled{_, _, _, _}: signalStarted(started)
    case _ _: IO.pure(Unit, Unit{})

def cancelOnRetry(session: Session.AgentSession, started: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    seen : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    Session.abortRetry(session)

def responsesOf(value: Fixture) -> R.Ref<List<&2, String>>:
  match value:
    case Fixture{_, _, _, _, _, _, Faux{responses, _, _}}: responses

def reportRetrying(session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    retrying : Bool <- Session.isRetrying(session)
    IO.print("{\"type\":\"retrying\",\"value\":" ++ Bool.pick(String, retrying, "true", "false") ++ "}")

def reportRemaining(responses: R.Ref<List<&2, String>>) -> IO(Unit):
  do IO<Unit>:
    remaining : List<&2, String> <- R.read(List<&2, String>, responses)
    IO.print("{\"type\":\"remaining\",\"count\":" ++ Nat.show(List.length(&2, String, remaining)) ++ "}")

def retryScenario(+dir: String, agentDir: String, responses: String, cancel: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(dir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +value : Fixture <- fixture(stored, dir, agentDir, String.split(responses, ';'), Nil{})
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +canceller : Session.Listener() <- C.create(~RetrySignal, ~Session.AgentSessionEvent, ~Unit, ~signalRetry, RetrySignal{started})
    Bool.pick(Unit -> IO(Unit), String.eq(cancel, "cancel"), _ => IO.bind(Unit, Unit, Session.subscribe(sessionOf(value), canceller), _ => IO.spawn(Unit, cancelOnRetry(sessionOf(value), started))), _ => IO.pure(Unit, Unit{}))(Unit{})
    result : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "test", Nil{}, None{})
    reportPrompt(result)
    reportRetrying(sessionOf(value))
    reportRemaining(responsesOf(value))
    reportSession(sessionOf(value))
    Session.unsubscribe(sessionOf(value), canceller)
    C.dispose(Session.AgentSessionEvent, Unit, canceller)
    teardown(value)
    Chan.close(Unit, started)

# compact: prompts run in order, then the action: "manual" compacts, "cancel"
# compacts and calls abortCompaction once the summarizer's retry backoff
# starts, "abort" does the same with abort() and prompts again, "none" only
# lets automatic compaction act on the prompts.
def reportCompact(result: Result<&2, &2, String, Compaction.CompactionResult>) -> IO(Unit):
  match result:
    case Done{value}: printed(Done{Json.object(Json.field("type", Json.text("compact_result"), Json.field("result", JsonEvent.compactionResult(value), Nil{})))})
    case Fail{error}: IO.print("{\"type\":\"compact_failed\",\"error\":" ++ Decode.quote(error) ++ "}")

def reportMessages(session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    current : List<&2, Session.Message()> <- Session.messages(session)
    printed(Done{Json.object(Json.field("type", Json.text("messages"), Json.field("messages", V.ArrayValue{JsonEvent.messages(current)}, Nil{})))})

def userIds(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case S.SessionMessageEntry{S.SessionEntryBase{id,_,_}, T.LlmMessage{Ai.User{_}}} <> rest: id <> userIds(rest)
    case _ <> rest: userIds(rest)

def secondUserId(ids: List<&2, String>) -> String:
  match ids:
    case _ <> id <> _: id
    case _: "missing-second-user"

def maybeQuoted(value: Maybe<&2, String>) -> String:
  Maybe.default(&2, String, Maybe.map(&2, String, String, Decode.quote, value), "null")

def secondUserInSession(stored: Session.Session()) -> String:
  secondUserId(userIds(S.getEntries(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored))))

def currentLeaf(stored: Session.Session()) -> String:
  Maybe.default(&2, String, S.getLeafId(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored)), "missing-leaf")

def reportNavigation(result: Result<&2, &2, String, Session.Navigation>) -> IO(Unit):
  match result:
    case Done{Session.Navigation{editorText,leafId}}: IO.print("{\"type\":\"navigation\",\"editorText\":" ++ maybeQuoted(editorText) ++ ",\"leafId\":" ++ maybeQuoted(leafId) ++ "}")
    case Fail{error}: IO.print("{\"type\":\"navigation_error\",\"error\":" ++ Decode.quote(error) ++ "}")

def reportFork(result: Result<&2, &2, String, Session.Fork>) -> IO(Unit):
  match result:
    case Done{Session.Fork{text,id,file}}: IO.print("{\"type\":\"fork\",\"selectedText\":" ++ Decode.quote(text) ++ ",\"sessionId\":" ++ Decode.quote(id) ++ ",\"sessionFile\":" ++ maybeQuoted(file) ++ "}")
    case Fail{error}: IO.print("{\"type\":\"fork_error\",\"error\":" ++ Decode.quote(error) ++ "}")

def navigationScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(dir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +value : Fixture <- fixture(stored, dir, agentDir, "a1" <> "a2" <> "branched" <> Nil{}, Nil{})
    first : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "one", Nil{}, None{})
    reportPrompt(first)
    second : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "two", Nil{}, None{})
    reportPrompt(second)
    +before : Session.Session() <- Session.sessionOf(sessionOf(value))
    navigated : Result<&2, &2, String, Session.Navigation> <- Session.navigateTree(sessionOf(value), secondUserInSession(before))
    reportNavigation(navigated)
    reportMessages(sessionOf(value))
    after : Session.Session() <- Session.sessionOf(sessionOf(value))
    unchanged : Result<&2, &2, String, Session.Navigation> <- Session.navigateTree(sessionOf(value), currentLeaf(after))
    reportNavigation(unchanged)
    invalid : Result<&2, &2, String, Session.Navigation> <- Session.navigateTree(sessionOf(value), "missing-entry")
    reportNavigation(invalid)
    replacement : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "replacement", Nil{}, None{})
    reportPrompt(replacement)
    reportMessages(sessionOf(value))
    reportEntries(sessionOf(value))
    teardown(value)

def forkScenario(+dir: String, +agentDir: String, persisted: Bool) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Bool.pick(Unit -> IO(Sessions.Outcome(Session.Session())), persisted,
      _ => Session.createSession(dir, Some{dir}, agentDir, Sessions.noOptions()),
      _ => Session.memorySession(dir, Sessions.noOptions()))(Unit{})
    stored : Session.Session() <- requireSession(created)
    +value : Fixture <- fixture(stored, dir, agentDir, "a1" <> "a2" <> "branched" <> Nil{}, Nil{})
    first : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "one", Nil{}, None{})
    reportPrompt(first)
    second : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "two", Nil{}, None{})
    reportPrompt(second)
    +before : Session.Session() <- Session.sessionOf(sessionOf(value))
    IO.print("{\"type\":\"source_session\",\"id\":" ++ Decode.quote(Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, before)) ++ "}")
    forked : Result<&2, &2, String, Session.Fork> <- Session.forkAt(sessionOf(value), secondUserInSession(before))
    reportFork(forked)
    reportMessages(sessionOf(value))
    reportEntries(sessionOf(value))
    replacement : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "replacement", Nil{}, None{})
    reportPrompt(replacement)
    reportMessages(sessionOf(value))
    reportEntries(sessionOf(value))
    teardown(value)

def reportCompacting(session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    compacting : Bool <- Session.isCompacting(session)
    IO.print("{\"type\":\"compacting\",\"value\":" ++ Bool.pick(String, compacting, "true", "false") ++ "}")

def promptAll(+session: Session.AgentSession, prompts: List<&2, String>) -> IO(Unit):
  match prompts:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Session.prompt(session, text, Nil{}, None{})
        reportPrompt(result)
        promptAll(session, rest)

def interruptOnRetry(+session: Session.AgentSession, started: Chan(Unit), abortAll: Bool) -> IO(Unit):
  do IO<Unit>:
    seen : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    Bool.pick(Unit -> IO(Unit), abortAll, _ => Session.abort(session), _ => Session.abortCompaction(session))(Unit{})

def compactThen(+session: Session.AgentSession, prompts: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Compaction.CompactionResult> <- Session.compact(session, None{})
    reportCompact(result)
    reportCompacting(session)
    promptAll(session, prompts)

# The interrupt waits for the summarizer's first retry backoff.
def interrupted(+session: Session.AgentSession, abortAll: Bool, prompts: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +signal : Session.Listener() <- C.create(~RetrySignal, ~Session.AgentSessionEvent, ~Unit, ~signalRetry, RetrySignal{started})
    Session.subscribe(session, signal)
    IO.spawn(Unit, interruptOnRetry(session, started, abortAll))
    compactThen(session, prompts)
    Session.unsubscribe(session, signal)
    C.dispose(Session.AgentSessionEvent, Unit, signal)
    Chan.close(Unit, started)

def compactAction(+session: Session.AgentSession, action: String) -> IO(Unit):
  match action:
    case "manual": compactThen(session, Nil{})
    case "cancel": interrupted(session, False{}, Nil{})
    case "abort": interrupted(session, True{}, "next prompt" <> Nil{})
    case _: IO.pure(Unit, Unit{})

# "queued" queues a follow-up before the prompts, so the run continues past
# its first turn.
def beforePrompts(session: Session.AgentSession, action: String) -> IO(Unit):
  match action:
    case "queued": Session.followUp(session, "later", Nil{})
    case _: IO.pure(Unit, Unit{})

def promptsOf(+prompts: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(prompts, "-"), Nil{}, String.split(prompts, ';'))

def compactScenario(+dir: String, +agentDir: String, prompts: String, responses: String, action: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.createSession(dir, Some{dir}, agentDir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +value : Fixture <- fixture(stored, dir, agentDir, String.split(responses, ';'), Nil{})
    +chosen : String = action
    beforePrompts(sessionOf(value), chosen)
    promptAll(sessionOf(value), promptsOf(prompts))
    compactAction(sessionOf(value), chosen)
    reportRemaining(responsesOf(value))
    reportMessages(sessionOf(value))
    reportEntries(sessionOf(value))
    reportSession(sessionOf(value))
    teardown(value)

# bash: user bash commands (suite/agent-session-bash-persistence.test.ts).
def ExecResult() -> Data: Result<&2, &2, Bash.OperationError, Maybe<&2, U32>>
def BashOutcome() -> Data: Result<&2, &2, String, BashExec.BashResult>

def exitText(code: Maybe<&2, U32>) -> String:
  match code:
    case None{}: "null"
    case Some{value}: Nat.show(U32.to_nat(value))

def flag(value: Bool) -> String: Bool.pick(String, value, "true", "false")

def reportBash(+label: String, result: BashOutcome()) -> IO(Unit):
  match result:
    case Done{BashExec.BashResult{output, exitCode, cancelled, truncated, _}}: IO.print("{\"type\":\"bash_result\",\"label\":" ++ Decode.quote(label) ++ ",\"output\":" ++ Decode.quote(output) ++ ",\"exitCode\":" ++ exitText(exitCode) ++ ",\"cancelled\":" ++ flag(cancelled) ++ ",\"truncated\":" ++ flag(truncated) ++ "}")
    case Fail{error}: IO.print("{\"type\":\"bash_failed\",\"label\":" ++ Decode.quote(label) ++ ",\"error\":" ++ Decode.quote(error) ++ "}")

def reportBashState(+session: Session.AgentSession, +label: String) -> IO(Unit):
  do IO<Unit>:
    running : Bool <- Session.isBashRunning(session)
    pending : Bool <- Session.hasPendingBashMessages(session)
    IO.print("{\"type\":\"bash_state\",\"label\":" ++ Decode.quote(label) ++ ",\"running\":" ++ flag(running) ++ ",\"pending\":" ++ flag(pending) ++ "}")

def sendText(onData: C.Callback<List<&2, U32>, Result<&2, &2, String, Unit>>, text: String) -> IO(Unit):
  do IO<Unit>:
    written : Result<&2, &2, String, Unit> <- C.call(List<&2, U32>, Result<&2, &2, String, Unit>, onData, Utf8.encode(text))
    return Unit{}

# Custom operations writing "hello " and "world" through onData.
def streamingExec(env: Unit, input: Bash.BashExecutionInput) -> IO(ExecResult()):
  match input:
    case Bash.BashExecutionInput{_, _, +onData, _, _, _}:
      do IO<ExecResult()>:
        sendText(onData, "hello ")
        sendText(onData, "world")
        return Done{Some{0}}

# Controlled operations: announce the invocation, wait for release, report
# whether the signal was aborted by then and exit 0.
type Hold is Data:
  Hold{label: String, entered: Chan(Unit), release: Chan(Unit)}

def heldExec(hold: Hold, input: Bash.BashExecutionInput) -> IO(ExecResult()):
  match hold input:
    case Hold{label, entered, release} Bash.BashExecutionInput{_, _, _, signal, _, _}:
      do IO<ExecResult()>:
        sent : Bool <- Chan.send(Unit, entered, Unit{})
        R.requireSent(sent)
        released : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        aborted : Bool <- Child.parentAborted(signal)
        IO.print("{\"type\":\"exec_signal\",\"command\":" ++ Decode.quote(label) ++ ",\"aborted\":" ++ flag(aborted) ++ "}")
        return Done{Some{0}}

def heldOperations(hold: Hold) -> IO(Bash.BashOperations):
  do IO<Bash.BashOperations>:
    exec : C.Callback<Bash.BashExecutionInput, ExecResult()> <- C.create(~Hold, ~Bash.BashExecutionInput, ~ExecResult(), ~heldExec, hold)
    return Bash.BashOperations{exec}

def collect(chunks: R.Ref<List<&2, String>>, delta: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, chunks, old => (List.append(&2, String, old, delta <> Nil{}), Unit{}))

def bashInBackground(session: Session.AgentSession, command: String, operations: Bash.BashOperations, +done: Chan(BashOutcome())) -> IO(Unit):
  do IO<Unit>:
    result : BashOutcome() <- Session.executeBash(session, command, None{}, Session.BashOptions{None{}, None{}, Some{operations}})
    sent : Bool <- Chan.send(BashOutcome(), done, result)
    R.requireSent(sent)

def reportReceived(+label: String, received: Maybe<&1, BashOutcome()>) -> IO(Unit):
  match received:
    case Some{result}: reportBash(label, result)
    case None{}: reportBash(label, Fail{"bash fiber did not finish"})

def hiResult() -> BashExec.BashResult: BashExec.BashResult{"hi", Some{0}, False{}, False{}, None{}}

def customScenario(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +chunks : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +collector : C.Callback<String, Unit> <- C.create(~R.Ref<List<&2, String>>, ~String, ~Unit, ~collect, chunks)
    exec : C.Callback<Bash.BashExecutionInput, ExecResult()> <- C.create(~Unit, ~Bash.BashExecutionInput, ~ExecResult(), ~streamingExec, Unit{})
    +operations : Bash.BashOperations = Bash.BashOperations{exec}
    custom : BashOutcome() <- Session.executeBash(session, "custom", Some{collector}, Session.BashOptions{None{}, Some{"bash-1"}, Some{operations}})
    reportBash("custom", custom)
    C.dispose(String, Unit, collector)
    Bash.disposeOperations(operations)
    deltas : List<&2, String> <- R.dispose(List<&2, String>, chunks)
    IO.print("{\"type\":\"callback_deltas\",\"deltas\":[" ++ String.join(quotedAll(deltas), ",") ++ "]}")

def concurrentScenario(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +entered1 : Chan(Unit) <- Chan.new(Unit, 1)
    +release1 : Chan(Unit) <- Chan.new(Unit, 1)
    +entered2 : Chan(Unit) <- Chan.new(Unit, 1)
    +release2 : Chan(Unit) <- Chan.new(Unit, 1)
    +done1 : Chan(BashOutcome()) <- Chan.new(BashOutcome(), 1)
    +done2 : Chan(BashOutcome()) <- Chan.new(BashOutcome(), 1)
    +first : Bash.BashOperations <- heldOperations(Hold{"first", entered1, release1})
    +second : Bash.BashOperations <- heldOperations(Hold{"second", entered2, release2})
    IO.spawn(Unit, bashInBackground(session, "first", first, done1))
    IO.spawn(Unit, bashInBackground(session, "second", second, done2))
    began1 : Maybe<&1, Unit> <- Chan.recv(Unit, entered1)
    began2 : Maybe<&1, Unit> <- Chan.recv(Unit, entered2)
    reportBashState(session, "both_running")
    sent1 : Bool <- Chan.send(Unit, release1, Unit{})
    R.requireSent(sent1)
    finished1 : Maybe<&1, BashOutcome()> <- Chan.recv(BashOutcome(), done1)
    reportReceived("first", finished1)
    reportBashState(session, "after_first")
    Session.abortBash(session)
    sent2 : Bool <- Chan.send(Unit, release2, Unit{})
    R.requireSent(sent2)
    finished2 : Maybe<&1, BashOutcome()> <- Chan.recv(BashOutcome(), done2)
    reportReceived("second", finished2)
    reportBashState(session, "after_abort")
    Bash.disposeOperations(first)
    Bash.disposeOperations(second)
    Chan.close(Unit, entered1)
    Chan.close(Unit, release1)
    Chan.close(Unit, entered2)
    Chan.close(Unit, release2)
    Chan.close(BashOutcome(), done1)
    Chan.close(BashOutcome(), done2)

def bashScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(dir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +value : Fixture <- fixture(stored, dir, agentDir, Nil{}, Nil{})
    Session.recordBashResult(sessionOf(value), "echo hi", hiResult(), None{})
    reportBashState(sessionOf(value), "idle_record")
    reportMessages(sessionOf(value))
    reportEntries(sessionOf(value))
    local : BashOutcome() <- Session.executeBash(sessionOf(value), "printf 'hello'", None{}, Session.bashDefaults())
    reportBash("local", local)
    customScenario(sessionOf(value))
    concurrentScenario(sessionOf(value))
    reportMessages(sessionOf(value))
    teardown(value)

# bash_deferred: a result recorded while the agent streams waits for the run
# to settle, then precedes the next prompt.
def bashDeferredScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(dir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Result<&2, &2, String, Unit>) <- Chan.new(Result<&2, &2, String, Unit>, 1)
    +value : Fixture <- fixture(stored, dir, agentDir, "done" <> "after flush" <> Nil{}, Gate{started, release} <> Nil{})
    IO.spawn(Unit, promptInBackground(sessionOf(value), done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    Session.recordBashResult(sessionOf(value), "echo hi", hiResult(), None{})
    reportBashState(sessionOf(value), "while_streaming")
    reportMessages(sessionOf(value))
    sent : Bool <- Chan.send(Unit, release, Unit{})
    R.requireSent(sent)
    finished : Maybe<&1, Result<&2, &2, String, Unit>> <- Chan.recv(Result<&2, &2, String, Unit>, done)
    reportFinished(finished)
    reportBashState(sessionOf(value), "settled")
    reportMessages(sessionOf(value))
    next : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "next turn", Nil{}, None{})
    reportPrompt(next)
    reportMessages(sessionOf(value))
    reportEntries(sessionOf(value))
    teardown(value)
    Chan.close(Unit, started)
    Chan.close(Unit, release)
    Chan.close(Result<&2, &2, String, Unit>, done)

# expand: /skill: commands and prompt templates are expanded before the
# prompt runs or is queued (agent-session skill command and template tests).
def sourceIn(dir: String) -> Skills.SourceInfo: Skills.SourceInfo{dir, "local", Skills.Temporary{}, Skills.TopLevel{}, None{}}

def expandLoadout(+dir: String) -> Runtime.Loadout:
  +source = sourceIn(dir)
  Runtime.Loadout{Rec.new(String), Nil{}, Skills.Skill{"demo", "Demo skill", dir ++ "/skills/demo/SKILL.md", dir ++ "/skills/demo", source, False{}} <> Skills.Skill{"gone", "Missing file", dir ++ "/skills/gone/SKILL.md", dir ++ "/skills/gone", source, False{}} <> Nil{}, Templates.PromptTemplate{"greet", "", None{}, "Hello $1 ($@)", source, dir ++ "/prompts/greet.md"} <> Nil{}}

def expandScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(dir, Sessions.noOptions())
    stored : Session.Session() <- requireSession(created)
    +value : Fixture <- fixtureWith(stored, dir, agentDir, "a1" <> "a2" <> "a3" <> "a4" <> "a5" <> Nil{}, Nil{}, expandLoadout(dir))
    Session.steer(sessionOf(value), "/greet queued", Nil{})
    first : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "/skill:demo please help", Nil{}, None{})
    reportPrompt(first)
    second : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "/greet world \"big day\"", Nil{}, None{})
    reportPrompt(second)
    third : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "/skill:unknown x", Nil{}, None{})
    reportPrompt(third)
    fourth : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(value), "/skill:gone y", Nil{}, None{})
    reportPrompt(fourth)
    teardown(value)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "persist" <> dir <> agentDir <> Nil{}: persistScenario(dir, agentDir)
    case "queue" <> dir <> agentDir <> Nil{}: queueScenario(dir, agentDir)
    case "mutate" <> dir <> agentDir <> Nil{}: mutateScenario(dir, agentDir)
    case "busy" <> dir <> agentDir <> Nil{}: busyScenario(dir, agentDir)
    case "retry" <> dir <> agentDir <> responses <> cancel <> Nil{}: retryScenario(dir, agentDir, responses, cancel)
    case "compact" <> dir <> agentDir <> prompts <> responses <> action <> Nil{}: compactScenario(dir, agentDir, prompts, responses, action)
    case "navigate" <> dir <> agentDir <> Nil{}: navigationScenario(dir, agentDir)
    case "fork" <> dir <> agentDir <> Nil{}: forkScenario(dir, agentDir, False{})
    case "fork_persisted" <> dir <> agentDir <> Nil{}: forkScenario(dir, agentDir, True{})
    case "bash" <> dir <> agentDir <> Nil{}: bashScenario(dir, agentDir)
    case "bash_deferred" <> dir <> agentDir <> Nil{}: bashDeferredScenario(dir, agentDir)
    case "expand" <> dir <> agentDir <> Nil{}: expandScenario(dir, agentDir)
    case _: IO.die(Unit, 1, "usage: agent-session <persist|queue|mutate|busy|navigate|fork|fork_persisted|bash|bash_deferred|expand> <dir> <agentDir> | retry <dir> <agentDir> <responses> <cancel|run> | compact <dir> <agentDir> <prompts|-> <responses> <manual|cancel|abort|queued|none>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
