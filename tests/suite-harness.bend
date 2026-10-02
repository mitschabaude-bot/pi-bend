import Base
import ../packages/agent/src/types.bend as T
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/record.bend as Rec
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/child-process.bend as Child
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/tools/bash.bend as Bash
import ../packages/coding-agent/src/core/bash-executor.bend as BashExec
import ../packages/coding-agent/src/modes/json-event.bend as JsonEvent
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/utils/shell.bend as Shell
import ../packages/coding-agent/src/core/session-stats.bend as Stats
import ../packages/coding-agent/src/core/tools/file-mutation-queue.bend as Queue
import ../packages/coding-agent/src/utils/tools-manager.bend as Manager
import ../packages/coding-agent/src/core/compaction/compaction.bend as Compaction
import ../packages/coding-agent/src/core/messages.bend as Messages
import ../packages/coding-agent/src/core/session-json.bend as SessionJson
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/f64.bend as F
import ./agent-session.bend as H
import ./regressions.bend as Reg
import ../packages/coding-agent/src/core/system-prompt.bend as Prompt
import ../packages/coding-agent/src/core/skills.bend as Skills
import ../packages/coding-agent/src/core/prompt-templates.bend as Templates
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/coding-agent/examples/extensions/trigger-compact.bend as TriggerCompact

# The port of upstream test/suite/harness.ts (createHarness): an AgentSession
# over tests/regressions.bend's faux provider, an in-memory session, the
# settings of the scenario's agent directory, a system prompt (upstream's
# test resource loader) and the scenario's tools, all active (upstream
# baseToolsOverride). Every session event is printed as a JSON line, as
# upstream's `harness.events`. tests/regressions_check.py reads them.

# Tools
# -----
# Tool behaviors the suites use. Echo returns its `text` argument after a
# prefix; Notify sends a custom message without triggering a turn while it
# runs (#8537's background task); Stub is never called.
type ToolKind is Data:
  Echo{prefix: String}
  UsageEcho{usage: Ai.Usage}
  Notify{}
  Throws{message: String}
  Records{}
  Gated{started: Chan(Unit), release: Chan(Unit)}
  NoContent{}
  Runs{label: String, delay: U32}

type ToolSpec is Data:
  ToolSpec{name: String, kind: ToolKind}

type ToolEnv is Data:
  ToolEnv{session: R.Ref<Maybe<&2, Session.AgentSession>>, kind: ToolKind}

def textOf(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""

def valueArgument(params: V.Value) -> String:
  match params:
    case V.ObjectValue{record}: textOf(Rec.get(V.Value, record, "value"))
    case _: ""

def textArgument(params: V.Value) -> String:
  match params:
    case V.ObjectValue{record}: textOf(Rec.get(V.Value, record, "text"))
    case _: ""

def textResult(+text: String, details: V.Value) -> Tools.Output():
  Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, Some{Tools.RawDetails{details}}, None{}, None{}}}

def notified(found: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{session}:
      do IO<Unit>:
        sent : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(session, Ext.CustomMessageInput{"subagent-reply", Ai.UserText{"subagent replied"}, True{}, None{}}, Ext.SendMessageOptions{Some{False{}}, None{}})
        return Unit{}

def executeTool(env: ToolEnv, input: Tools.Input()) -> IO(Tools.Output()):
  match env input:
    case ToolEnv{_, Echo{prefix}} T.ToolExecutionInput{_, +params, _, _}:
      +text = textArgument(params)
      do IO<Tools.Output()>:
        IO.print("{\"type\":\"tool_run\",\"run\":" ++ Decode.quote(text) ++ "}")
        return textResult(prefix ++ text, Json.object(Json.field("text", Json.text(text), Nil{})))
    case ToolEnv{_, UsageEcho{usage}} T.ToolExecutionInput{_, params, _, _}:
      +text = textArgument(params)
      IO.pure(Tools.Output(), Done{T.AgentToolResult{[Ai.TextImageText{Ai.TextContent{text, None{}}}], Some{Tools.RawDetails{Json.object(Json.field("text", Json.text(text), Nil{}))}}, Some{usage}, None{}}})
    case ToolEnv{session, Notify{}} _:
      do IO<Tools.Output()>:
        found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, session)
        notified(found)
        return textResult("tool done", Json.object(Nil{}))
    case ToolEnv{_, Throws{message}} _: IO.pure(Tools.Output(), Fail{Tools.failure(message)})
    case ToolEnv{_, NoContent{}} _: IO.pure(Tools.Output(), Done{T.AgentToolResult{Nil{}, Some{Tools.RawDetails{Json.object(Nil{})}}, None{}, None{}}})
    case ToolEnv{_, Gated{started, release}} _:
      do IO<Tools.Output()>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        released : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return textResult("released", Json.object(Nil{}))
    case ToolEnv{_, Runs{label, delay}} T.ToolExecutionInput{_, +params, _, _}:
      +run = label ++ ":" ++ valueArgument(params)
      do IO<Tools.Output()>:
        IO.sleep(delay)
        IO.print("{\"type\":\"tool_run\",\"run\":" ++ Decode.quote(run) ++ "}")
        return textResult(run, Json.object(Json.field("value", Json.text(valueArgument(params)), Nil{})))
    case ToolEnv{_, Records{}} T.ToolExecutionInput{_, +params, _, _}:
      +value = valueArgument(params)
      do IO<Tools.Output()>:
        IO.print("{\"type\":\"executed\",\"value\":" ++ Decode.quote(value) ++ "}")
        return textResult(value, Json.object(Json.field("value", Json.text(value), Nil{})))

def textSchema() -> V.Value:
  Json.object(Json.field("type", Json.text("object"), Json.field("properties", Json.object(Json.field("text", Json.object(Json.field("type", Json.text("string"), Nil{})), Nil{})), Nil{})))

def emptySchema() -> V.Value: Json.object(Json.field("type", Json.text("object"), Json.field("properties", Json.object(Nil{}), Nil{})))

def valueSchema() -> V.Value:
  Json.object(Json.field("type", Json.text("object"), Json.field("properties", Json.object(Json.field("value", Json.object(Json.field("type", Json.text("string"), Nil{})), Nil{})), Nil{})))

def schemaOf(kind: ToolKind) -> V.Value:
  match kind:
    case Echo{_}: textSchema()
    case UsageEcho{_}: textSchema()
    case Throws{_}: textSchema()
    case Records{}: valueSchema()
    case Runs{_, _}: valueSchema()
    case Gated{_, _}: emptySchema()
    case NoContent{}: emptySchema()
    case Notify{}: emptySchema()

type Built is Data:
  Built{tools: List<&2, Tools.Tool()>, executes: List<&2, Tools.Execute()>}

def withTool(tool: Tools.Tool(), execute: Tools.Execute(), built: Built) -> Built:
  match built:
    case Built{tools, executes}: Built{tool <> tools, execute <> executes}

def buildTools(+session: R.Ref<Maybe<&2, Session.AgentSession>>, specs: List<&2, ToolSpec>) -> IO(Built):
  match specs:
    case Nil{}: IO.pure(Built, Built{Nil{}, Nil{}})
    case ToolSpec{+name, +kind} <> rest:
      do IO<Built>:
        +execute : Tools.Execute() <- C.create(~ToolEnv, ~Tools.Input(), ~Tools.Output(), ~executeTool, ToolEnv{session, kind})
        built : Built <- buildTools(session, rest)
        return withTool(T.AgentTool{name, name, schemaOf(kind), None{}, name, None{}, execute, None{}, None{}}, execute, built)

def disposeExecutes(executes: List<&2, Tools.Execute()>) -> IO(Unit):
  match executes:
    case Nil{}: IO.pure(Unit, Unit{})
    case execute <> rest:
      do IO<Unit>:
        C.dispose(Tools.Input(), Tools.Output(), execute)
        disposeExecutes(rest)

# Harness
# -------

# upstream createHarness({ tools }): without `tools` the session has pi's
# built-in tools (read, bash, edit, write); with them, exactly those.
type Tooling is Data:
  Builtins{}
  Scripted{specs: List<&2, ToolSpec>}

# The built-in tools are owned by a task holding their owners and file
# mutation queue until the harness releases them (`release`, then `done`).
type BuiltinsHandle is Data:
  BuiltinsHandle{release: Chan(Unit), done: Chan(Unit)}

type BuiltinSet is Data:
  BuiltinSet{handle: Maybe<&2, BuiltinsHandle>, tools: List<&2, Tools.Tool()>}

type Harness is Data:
  Harness{fixture: Reg.Fixture, session: R.Ref<Maybe<&2, Session.AgentSession>>, executes: List<&2, Tools.Execute()>, builtins: Maybe<&2, BuiltinsHandle>}

# upstream's test resource loader has no system prompt override, so the
# session builds pi's default system prompt for the active tools.
def promptSections(+source: Runtime.LoadoutSource, tools: List<&2, Tools.Tool()>) -> Rec.Record<String>:
  Result.default(&2, &2, String, Rec.Record<String>, Runtime.sectionsForTools(source, Session.toolNamesOf(tools), Nil{}, Nil{}), Rec.new(String))

# upstream createHarness({ resourceLoader }): the skills and prompt
# templates its resource loader provides.
type Resources is Data:
  Resources{skills: List<&2, Skills.Skill>, templates: List<&2, Templates.PromptTemplate>}
  DiscoveredPrompts{}

def noResources() -> Resources: Resources{Nil{}, Nil{}}

def harnessLoadout(+source: Runtime.LoadoutSource, +tools: List<&2, Tools.Tool()>, runner: Maybe<&2, Runner.ExtensionRunner>, resources: Resources) -> Runtime.Loadout:
  match resources:
    case Resources{skills, templates}: Runtime.Loadout{promptSections(source, tools), tools, skills, templates, runner, Nil{}, Some{source}, tools}
    case DiscoveredPrompts{}: Runtime.Loadout{promptSections(source, tools), tools, Nil{}, Nil{}, runner, Nil{}, Some{source}, tools}

def loadoutSource(+dir: String, +agentDir: String, +settings: Settings.SettingsManager) -> Runtime.LoadoutSource:
  Runtime.LoadoutSource{Paths.Environment{dir, agentDir, Runtime.urlContext()}, Reg.toolOptions(dir, agentDir, Runtime.defaultToolSelection(), settings), "/pi", None{}, None{}}

# upstream createTestExtensionsResult: the inline extensions load into a
# runtime whose runner shares the session's model runtime.
def extensionLoadout(runtime: Maybe<&2, Ext.ExtensionRuntime()>, +source: Runtime.LoadoutSource, +cwd: String, +tools: List<&2, Tools.Tool()>, resources: Resources, models: Models.ModelRuntime) -> IO(Runtime.Loadout):
  match runtime:
    case None{}: IO.pure(Runtime.Loadout, harnessLoadout(source, tools, None{}, resources))
    case Some{loaded}:
      do IO<Runtime.Loadout>:
        runner : Runner.ExtensionRunner <- Runner.create(loaded, cwd, models)
        return harnessLoadout(source, tools, Some{runner}, resources)

def loadErrorLines(errors: List<&2, Ext.LoadError>) -> IO(Unit):
  match errors:
    case Nil{}: IO.pure(Unit, Unit{})
    case Ext.LoadError{path, error} <> rest:
      do IO<Unit>:
        IO.print("{\"type\":\"load_error\",\"path\":" ++ Decode.quote(path) ++ ",\"error\":" ++ Decode.quote(error) ++ "}")
        loadErrorLines(rest)

def loadedRuntime(extensions: List<&2, Ext.InlineExtension>) -> IO(Maybe<&2, Ext.ExtensionRuntime()>):
  match extensions:
    case Nil{}: IO.pure(Maybe<&2, Ext.ExtensionRuntime()>, None{})
    case +more:
      do IO<Maybe<&2, Ext.ExtensionRuntime()>>:
        +runtime : Ext.ExtensionRuntime() <- Loader.createExtensionRuntime()
        errors : List<&2, Ext.LoadError> <- Loader.loadExtensionFactories(runtime, more)
        Loader.disposeInlineExtensions(more)
        loadErrorLines(errors)
        return Some{runtime}

def builtTools(built: Built) -> List<&2, Tools.Tool()>:
  match built:
    case Built{tools, _}: tools

def builtExecutes(built: Built) -> List<&2, Tools.Execute()>:
  match built:
    case Built{_, executes}: executes

# upstream createHarness({ tools, extensionFactories }): `ref` receives the
# session once it exists, for tools and handlers that act on it.
# `seed` is appended to the session first (upstream tests append to
# harness.sessionManager and load the agent from buildSessionContext());
# `others` are further faux models (upstream `models`).
def holdBuiltins(queue: Queue.Owner, owners: List<&1, Tools.ToolOwner>, release: Chan(Unit), done: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    released : Maybe<&1, Unit> <- Chan.recv(Unit, release)
    Tools.disposeTools(owners)
    Queue.dispose(queue)
    sent : Bool <- Chan.send(Unit, done, Unit{})
    return Unit{}

def heldTools(queue: Queue.Owner, pair: List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>) -> IO(BuiltinSet):
  match pair:
    case Tuple{owners, tools}:
      do IO<BuiltinSet>:
        +release : Chan(Unit) <- Chan.new(Unit, 1)
        +done : Chan(Unit) <- Chan.new(Unit, 1)
        IO.spawn(Unit, holdBuiltins(queue, owners, release, done))
        return BuiltinSet{Some{BuiltinsHandle{release, done}}, tools}

def createdBuiltins(+dir: String, +agentDir: String, pair: Queue.Owner & Queue.Queue) -> IO(BuiltinSet):
  match pair:
    case Tuple{queue, handle}:
      do IO<BuiltinSet>:
        owners : List<&1, Tools.ToolOwner> <- Tools.createTools(Tools.allToolNames(), Tools.Environment{Paths.Environment{dir, agentDir, Runtime.urlContext()}, dir, Manager.ToolsManager{agentDir ++ "/bin", Runtime.urlContext(), None{}}, handle, "", None{}}, Tools.defaultOptions())
        heldTools(queue, Tools.borrowTools(owners))

def builtinsFor(+dir: String, +agentDir: String, tooling: Tooling) -> IO(BuiltinSet):
  match tooling:
    case Scripted{_}: IO.pure(BuiltinSet, BuiltinSet{None{}, Nil{}})
    case Builtins{}:
      do IO<BuiltinSet>:
        queue : Queue.Owner <- Queue.create()
        createdBuiltins(dir, agentDir, Queue.borrow(queue))

def specsOf(tooling: Tooling) -> List<&2, ToolSpec>:
  match tooling:
    case Builtins{}: Nil{}
    case Scripted{specs}: specs

def disposeBuiltins(builtins: Maybe<&2, BuiltinsHandle>) -> IO(Unit):
  match builtins:
    case None{}: IO.pure(Unit, Unit{})
    case Some{BuiltinsHandle{+release, +done}}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, release, Unit{})
        finished : Maybe<&1, Unit> <- Chan.recv(Unit, done)
        Chan.close(Unit, release)
        Chan.close(Unit, done)

def splitTools(split: BuiltinSet) -> List<&2, Tools.Tool()>:
  match split:
    case BuiltinSet{_, tools}: tools

def splitOwners(split: BuiltinSet) -> Maybe<&2, BuiltinsHandle>:
  match split:
    case BuiltinSet{handle, _}: handle

# DiscoveredPrompts: prompt templates are discovered (upstream's resource
# loader without noPromptTemplates); skills stay off.
def withDiscovery(resources: Resources, +source: Runtime.LoadoutSource) -> Runtime.LoadoutSource:
  match resources source:
    case DiscoveredPrompts{} Runtime.LoadoutSource{environment, Runtime.CreateOptions{cwd, agentDir, auth, bundle, packageDir, provider, model, apiKey, thinking, systemPrompt, append, selection, contextFiles, seed, settings, Runtime.ResourceOptions{skillPaths, noSkills, promptPaths, _}}, root, loader, extensions}:
      Runtime.LoadoutSource{environment, Runtime.CreateOptions{cwd, agentDir, auth, bundle, packageDir, provider, model, apiKey, thinking, systemPrompt, append, selection, contextFiles, seed, settings, Runtime.ResourceOptions{skillPaths, noSkills, promptPaths, False{}}}, root, loader, extensions}
    case _ other: other

def createHarnessResources(+dir: String, +agentDir: String, +tooling: Tooling, setup: Reg.Setup, +ref: R.Ref<Maybe<&2, Session.AgentSession>>, extensions: List<&2, Ext.InlineExtension>, seed: List<&2, Session.Message()>, others: List<&2, Ai.Model<Ai.JsonValue>>, +resources: Resources) -> IO(Harness):
  do IO<Harness>:
    +runtime : Maybe<&2, Ext.ExtensionRuntime()> <- loadedRuntime(extensions)
    +built : Built <- buildTools(ref, specsOf(tooling))
    +split : BuiltinSet <- builtinsFor(dir, agentDir, tooling)
    uuids : Uuid.Generator <- Uuid.generator()
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(uuids, dir, Sessions.noOptions())
    empty : Session.Session() <- H.requireSession(created)
    stored : Session.Session() <- Reg.seeded(seed, empty)
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(dir, agentDir, Settings.options())
    +settings : Settings.SettingsManager = H.settingsOf(loaded)
    +source : Runtime.LoadoutSource = withDiscovery(resources, loadoutSource(dir, agentDir, settings))
    +value : Reg.Fixture <- Reg.fixtureModels(stored, dir, settings, setup, others, models => extensionLoadout(runtime, source, dir, List.append(&2, Tools.Tool(), splitTools(split), builtTools(built)), resources, models))
    R.write(Maybe<&2, Session.AgentSession>, ref, Some{Reg.sessionOf(value)})
    return Harness{value, ref, builtExecutes(built), splitOwners(split)}

def createHarnessFull(+dir: String, +agentDir: String, +tooling: Tooling, setup: Reg.Setup, +ref: R.Ref<Maybe<&2, Session.AgentSession>>, extensions: List<&2, Ext.InlineExtension>, seed: List<&2, Session.Message()>, others: List<&2, Ai.Model<Ai.JsonValue>>) -> IO(Harness):
  createHarnessResources(dir, agentDir, tooling, setup, ref, extensions, seed, others, noResources())

def createHarnessWith(+dir: String, agentDir: String, tooling: Tooling, setup: Reg.Setup, +ref: R.Ref<Maybe<&2, Session.AgentSession>>, extensions: List<&2, Ext.InlineExtension>) -> IO(Harness):
  createHarnessFull(dir, agentDir, tooling, setup, ref, extensions, Nil{}, Nil{})

def createHarness(+dir: String, agentDir: String, tooling: Tooling, setup: Reg.Setup) -> IO(Harness):
  do IO<Harness>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    createHarnessWith(dir, agentDir, tooling, setup, ref, Nil{})

def harnessFixture(harness: Harness) -> Reg.Fixture:
  match harness:
    case Harness{fixture, _, _, _}: fixture

def sessionOf(harness: Harness) -> Session.AgentSession:
  match harness:
    case Harness{fixture, _, _, _}: Reg.sessionOf(fixture)

def disposeRunner(runner: Maybe<&2, Runner.ExtensionRunner>) -> IO(Unit):
  match runner:
    case None{}: IO.pure(Unit, Unit{})
    case Some{found}: Runner.dispose(found)

def cleanup(harness: Harness) -> IO(Unit):
  match harness:
    case Harness{+fixture, ref, executes, builtins}:
      do IO<Unit>:
        found : Maybe<&2, Session.AgentSession> <- R.dispose(Maybe<&2, Session.AgentSession>, ref)
        runner : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(Reg.sessionOf(fixture))
        Reg.teardown(fixture)
        disposeRunner(runner)
        disposeExecutes(executes)
        disposeBuiltins(builtins)

# Reports
# -------

# upstream sessionManager.getEntries(): each entry's type, with a message
# entry's role.
def roleOf(message: Session.Message()) -> String:
  match message:
    case T.LlmMessage{Ai.System{_}}: "system"
    case T.LlmMessage{Ai.User{_}}: "user"
    case T.LlmMessage{Ai.Assistant{_}}: "assistant"
    case T.LlmMessage{Ai.ToolResult{_}}: "toolResult"
    case T.CustomMessage{Messages.CompactionSummary{_}}: "compactionSummary"
    case T.CustomMessage{Messages.BranchSummary{_}}: "branchSummary"
    case T.CustomMessage{Messages.BashExecution{_}}: "bashExecution"
    case T.CustomMessage{Messages.Custom{_}}: "custom"

def entryShape(entry: S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>) -> V.Value:
  match entry:
    case S.SessionMessageEntry{_, message}: Json.object(Json.field("type", Json.text("message"), Json.field("role", Json.text(roleOf(message)), Nil{})))
    case S.CustomMessageEntry{_, _, _, _, _}: Json.object(Json.field("type", Json.text("custom_message"), Nil{}))
    case S.Compaction{_}: Json.object(Json.field("type", Json.text("compaction"), Nil{}))
    case _: Json.object(Json.field("type", Json.text("other"), Nil{}))

def entryShapes(entries: List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: entryShape(entry) <> entryShapes(rest)

def reportEntries(+label: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    H.printed(Done{Json.object(Json.field("type", Json.text(label), Json.field("entries", V.ArrayValue{entryShapes(S.getEntries(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, stored)))}, Nil{})))})

def reportBranch(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    +branch : List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>> = Result.default(&2, &2, S.Error, List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>, S.getBranch(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, stored), S.Latest{}), Nil{})
    H.printed(Done{Json.object(Json.field("type", Json.text("branch"), Json.field("entries", V.ArrayValue{entryShapes(branch)}, Nil{})))})

def prompted(+session: Session.AgentSession, +text: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.prompt(session, text, Nil{}, None{})
    H.reportPrompt(result)

def echoCall(+id: String, +text: String) -> Reg.Reply:
  Reg.Call{id, "echo", Json.object(Json.field("text", Json.text(text), Nil{})), "{\"text\":" ++ Decode.quote(text) ++ "}"}

def setup(replies: List<&2, Reg.Reply>) -> Reg.Setup: Reg.Setup{replies, Nil{}, H.fauxModel()}

# suite/agent-session-bash-persistence.test.ts
# ---------------------------------------------

# "persists user, assistant, toolResult, and custom messages in order"
def customOrder(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Scripted{[ToolSpec{"echo", Echo{"echo:"}}]}, setup([echoCall("call_echo", "hello"), Reg.Text{"done"}]))
    sent : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(sessionOf(harness), Ext.CustomMessageInput{"note", Ai.UserText{"hello"}, True{}, Some{Json.object(Json.field("a", V.Number{U32.to_f64(1)}, Nil{}))}}, Session.sendDefaults())
    H.reportOutcome("sent", sent)
    prompted(sessionOf(harness), "start")
    reportEntries("entries", sessionOf(harness))
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# "does not emit message_end for bash execution messages"
def bashRecorded(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup(Nil{}))
    IO.print("{\"type\":\"recording\"}")
    Session.recordBashResult(sessionOf(harness), "echo hi", H.hiResult(), None{})
    IO.print("{\"type\":\"recorded\"}")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# "cancels running bash commands with abortBash": the operation rejects
# ("aborted") once its signal is aborted.
def ExecResult() -> Data: Result<&2, &2, Bash.OperationError, Maybe<&2, U32>>

def untilSignalled(fuel: Nat, +signal: Maybe<&2, Reg.Signal()>) -> IO(Bool):
  match fuel:
    case 0n: IO.pure(Bool, False{})
    case 1n+rest:
      do IO<Bool>:
        aborted : Bool <- Child.parentAborted(signal)
        Bool.pick(Unit -> IO(Bool), aborted, _ => IO.pure(Bool, True{}), _ => IO.bind(Unit, Bool, IO.sleep(1), _ => untilSignalled(rest, signal)))(Unit{})

def rejectOnAbort(entered: Chan(Unit), input: Bash.BashExecutionInput) -> IO(ExecResult()):
  match input:
    case Bash.BashExecutionInput{_, _, _, signal, _, _}:
      do IO<ExecResult()>:
        sent : Bool <- Chan.send(Unit, entered, Unit{})
        aborted : Bool <- untilSignalled(10000n, signal)
        return Fail{Bash.Operation{"aborted"}}

def bashInBackground(session: Session.AgentSession, operations: Bash.BashOperations, +done: Chan(H.BashOutcome())) -> IO(Unit):
  do IO<Unit>:
    result : H.BashOutcome() <- Session.executeBash(session, "sleep", None{}, Session.BashOptions{None{}, None{}, Some{operations}})
    sent : Bool <- Chan.send(H.BashOutcome(), done, result)
    R.requireSent(sent)

def bashAbort(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup(Nil{}))
    +entered : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(H.BashOutcome()) <- Chan.new(H.BashOutcome(), 1)
    exec : C.Callback<Bash.BashExecutionInput, ExecResult()> <- C.create(~Chan(Unit), ~Bash.BashExecutionInput, ~ExecResult(), ~rejectOnAbort, entered)
    +operations : Bash.BashOperations = Bash.BashOperations{exec}
    IO.spawn(Unit, bashInBackground(sessionOf(harness), operations, done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, entered)
    H.reportBashState(sessionOf(harness), "running")
    Session.abortBash(sessionOf(harness))
    finished : Maybe<&1, H.BashOutcome()> <- Chan.recv(H.BashOutcome(), done)
    H.reportReceived("aborted", finished)
    H.reportBashState(sessionOf(harness), "after_abort")
    Bash.disposeOperations(operations)
    Chan.close(Unit, entered)
    Chan.close(H.BashOutcome(), done)
    cleanup(harness)

# "aborts all active bash executions": both invocations are held; abortBash
# runs before either finishes.
def bashAbortAll(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup(Nil{}))
    +entered1 : Chan(Unit) <- Chan.new(Unit, 1)
    +release1 : Chan(Unit) <- Chan.new(Unit, 1)
    +entered2 : Chan(Unit) <- Chan.new(Unit, 1)
    +release2 : Chan(Unit) <- Chan.new(Unit, 1)
    +done1 : Chan(H.BashOutcome()) <- Chan.new(H.BashOutcome(), 1)
    +done2 : Chan(H.BashOutcome()) <- Chan.new(H.BashOutcome(), 1)
    +first : Bash.BashOperations <- H.heldOperations(H.Hold{"first", entered1, release1})
    +second : Bash.BashOperations <- H.heldOperations(H.Hold{"second", entered2, release2})
    IO.spawn(Unit, H.bashInBackground(sessionOf(harness), "first", first, done1))
    began1 : Maybe<&1, Unit> <- Chan.recv(Unit, entered1)
    IO.spawn(Unit, H.bashInBackground(sessionOf(harness), "second", second, done2))
    began2 : Maybe<&1, Unit> <- Chan.recv(Unit, entered2)
    Session.abortBash(sessionOf(harness))
    sent1 : Bool <- Chan.send(Unit, release1, Unit{})
    finished1 : Maybe<&1, H.BashOutcome()> <- Chan.recv(H.BashOutcome(), done1)
    sent2 : Bool <- Chan.send(Unit, release2, Unit{})
    finished2 : Maybe<&1, H.BashOutcome()> <- Chan.recv(H.BashOutcome(), done2)
    H.reportReceived("first", finished1)
    H.reportReceived("second", finished2)
    H.reportBashState(sessionOf(harness), "after_abort")
    Bash.disposeOperations(first)
    Bash.disposeOperations(second)
    Chan.close(Unit, entered1)
    Chan.close(Unit, release1)
    Chan.close(Unit, entered2)
    Chan.close(Unit, release2)
    Chan.close(H.BashOutcome(), done1)
    Chan.close(H.BashOutcome(), done2)
    cleanup(harness)

# "persists aborted assistant messages": the reply waits after its first
# chunk until the run is aborted.
def abortedAssistant(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Result<&2, &2, String, Unit>) <- Chan.new(Result<&2, &2, String, Unit>, 1)
    +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup([Reg.Interrupted{Reg.repeated(20000n), started}]))
    IO.spawn(Unit, Reg.promptLater(sessionOf(harness), "hi", done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    Session.abort(sessionOf(harness))
    finished : Maybe<&1, Result<&2, &2, String, Unit>> <- Chan.recv(Result<&2, &2, String, Unit>, done)
    H.reportFinished(finished)
    Reg.reportPersisted(sessionOf(harness))
    cleanup(harness)
    Chan.close(Unit, started)
    Chan.close(Result<&2, &2, String, Unit>, done)

# suite/regressions/8537-custom-message-tool-result-ordering.test.ts
# -----------------------------------------------------------------
# The wait tool sends a custom message (triggerTurn: false) while it runs.
def customDuringTool(+dir: String, agentDir: String, +second: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Scripted{[ToolSpec{"wait", Notify{}}]}, setup([Reg.Call{"call_wait", "wait", Json.object(Nil{}), "{}"}, Reg.Text{"done"}, Reg.Text{"second turn"}]))
    prompted(sessionOf(harness), "hi")
    H.reportMessages(sessionOf(harness))
    reportBranch(sessionOf(harness))
    Bool.pick(Unit -> IO(Unit), String.eq(second, "-"), _ => IO.pure(Unit, Unit{}), _ => IO.bind(Unit, Unit, prompted(sessionOf(harness), second), _ => H.reportMessages(sessionOf(harness))))(Unit{})
    cleanup(harness)

# Extensions
# ----------
# Inline extensions (upstream extensionFactories): each factory subscribes
# handlers through the ExtensionAPI. Handlers print what upstream's tests
# collect in arrays.

def Handled(-R: Data) -> Data: Result<&2, &2, String, Maybe<&2, R>>

def nothing(-R: Data) -> IO(Handled(R)): IO.pure(Handled(R), Done{None{}})

def registered(result: Result<&2, &2, String, Loader.Unsubscribe>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{error}: Fail{error}
    case Done{_}: Done{Unit{}}

def subscribe(api: Ext.ExtensionAPI, handler: Ext.EventHandler) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    result : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, handler)
    return registered(result)

def both(first: Result<&2, &2, String, Unit>, second: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, Unit>:
  match first:
    case Fail{error}: Fail{error}
    case Done{_}: second

def inline(+name: String, factory: Ext.ExtensionFactory()) -> Ext.InlineExtension: Ext.InlineExtension{name, factory, False{}}

def print(+kind: String, fields: List<&2, Rec.Property<V.Value>>) -> IO(Unit):
  H.printed(Done{Json.object(Json.field("type", Json.text(kind), fields))})

# #3982: message_end replaces the assistant's cost total with 0.123.
def costOverride(usage: Ai.Usage) -> Ai.Usage:
  match usage:
    case Ai.Usage{input, output, cacheRead, cacheWrite, a, b, total, Ai.UsageCost{i, o, r, w, _}}: Ai.Usage{input, output, cacheRead, cacheWrite, a, b, total, Ai.UsageCost{i, o, r, w, F64.div(U32.to_f64(123), U32.to_f64(1000))}}

def withCost(message: Session.Message()) -> Maybe<&2, Session.Message()>:
  match message:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, api, provider, model, a, b, c, d, usage, stop, e, f, g, h, time}}}: Some{T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, api, provider, model, a, b, c, d, costOverride(usage), stop, e, f, g, h, time}}}}
    case _: None{}

def costHandler(env: Unit, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)):
  match call:
    case Ext.HandlerCall{Ext.MessageEndEvent{message}, _}: IO.pure(Handled(Ext.MessageEndEventResult), Done{Some{Ext.MessageEndEventResult{withCost(message)}}})

def costFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.MessageEndEvent, Ext.MessageEndEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.MessageEndEvent>, ~Handled(Ext.MessageEndEventResult), ~costHandler, Unit{})
    subscribe(api, Ext.OnMessageEnd{handler})

def messageEndCost(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => costFactory(api)), Unit{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup([Reg.Text{"hello"}]), ref, [inline("cost", factory)])
    prompted(sessionOf(harness), "hi")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# #1717/#2113: a message_end handler that yields for assistant messages.
def isAssistant(message: Session.Message()) -> Bool:
  match message:
    case T.LlmMessage{Ai.Assistant{_}}: True{}
    case _: False{}

def slowEnd(env: Unit, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)):
  match call:
    case Ext.HandlerCall{Ext.MessageEndEvent{message}, _}: Bool.pick(Unit -> IO(Handled(Ext.MessageEndEventResult)), isAssistant(message), _ => IO.bind(Unit, Handled(Ext.MessageEndEventResult), IO.sleep(20), _ => nothing(Ext.MessageEndEventResult)), _ => nothing(Ext.MessageEndEventResult))(Unit{})

def slowEndFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.MessageEndEvent, Ext.MessageEndEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.MessageEndEvent>, ~Handled(Ext.MessageEndEventResult), ~slowEnd, Unit{})
    subscribe(api, Ext.OnMessageEnd{handler})

def echoCalls(texts: List<&2, String>, +index: Nat) -> List<&2, Ai.ToolCall<V.Value>>:
  match texts:
    case Nil{}: Nil{}
    case +text <> rest: Ai.ToolCall{"call_echo_" ++ Nat.show(index), "echo", Json.object(Json.field("text", Json.text(text), Nil{})), None{}, None{}} <> echoCalls(rest, index + 1n)

def settledOrder(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => slowEndFactory(api)), Unit{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Scripted{[ToolSpec{"echo", Echo{""}}]}, setup([Reg.Calls{echoCalls(["one", "two"], 1n)}, Reg.Text{"done"}]), ref, [inline("slow-end", factory)])
    prompted(sessionOf(harness), "run tools")
    reportBranch(sessionOf(harness))
    cleanup(harness)

# ... and a tool_call handler that reads the session branch.
def branchRoles(found: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{session}:
      do IO<Unit>:
        +stored : Session.Session() <- Session.sessionOf(session)
        +branch : List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>> = Result.default(&2, &2, S.Error, List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>, S.getBranch(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, stored), S.Latest{}), Nil{})
        print("roles_at_tool_call", Json.field("entries", V.ArrayValue{entryShapes(branch)}, Nil{}))

def rolesAtToolCall(env: R.Ref<Maybe<&2, Session.AgentSession>>, call: Ext.HandlerCall<Ext.ToolCallEvent>) -> IO(Handled(Ext.ToolCallEventResult)):
  do IO<Handled(Ext.ToolCallEventResult)>:
    found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, env)
    branchRoles(found)
    nothing(Ext.ToolCallEventResult)

def rolesFactory(ref: R.Ref<Maybe<&2, Session.AgentSession>>, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.ToolCallEvent, Ext.ToolCallEventResult) <- C.create(~R.Ref<Maybe<&2, Session.AgentSession>>, ~Ext.HandlerCall<Ext.ToolCallEvent>, ~Handled(Ext.ToolCallEventResult), ~rolesAtToolCall, ref)
    subscribe(api, Ext.OnToolCall{handler})

def toolCallSettled(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~R.Ref<Maybe<&2, Session.AgentSession>>, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => rolesFactory(environment, api)), ref)
    +harness : Harness <- createHarnessWith(dir, agentDir, Scripted{[ToolSpec{"echo", Echo{""}}]}, setup([echoCall("call_echo", "hello"), Reg.Text{"done"}]), ref, [inline("roles", factory)])
    prompted(sessionOf(harness), "run tool")
    cleanup(harness)

# #5998: a tool_call handler blocks every call and asks to terminate.
def blockAll(env: Unit, call: Ext.HandlerCall<Ext.ToolCallEvent>) -> IO(Handled(Ext.ToolCallEventResult)):
  IO.pure(Handled(Ext.ToolCallEventResult), Done{Some{Ext.ToolCallEventResult{Some{True{}}, Some{"Blocked by terminating policy"}, Some{True{}}}}})

def blockFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.ToolCallEvent, Ext.ToolCallEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ToolCallEvent>, ~Handled(Ext.ToolCallEventResult), ~blockAll, Unit{})
    subscribe(api, Ext.OnToolCall{handler})

def blockedTerminate(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => blockFactory(api)), Unit{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Scripted{[ToolSpec{"echo", Throws{"tool should have been blocked"}}]}, setup([echoCall("call_echo", "hello"), Reg.Text{"should not run"}]), ref, [inline("terminate", factory)])
    prompted(sessionOf(harness), "hi")
    Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# #8935: preflight records each call and aborts at the second; tool_result
# records its calls.
def preflight(env: Unit, call: Ext.HandlerCall<Ext.ToolCallEvent>) -> IO(Handled(Ext.ToolCallEventResult)):
  match call:
    case Ext.HandlerCall{Ext.ToolCallEvent{_, _, input}, ctx}:
      +value = valueArgument(input)
      do IO<Handled(Ext.ToolCallEventResult)>:
        print("preflight", Json.field("value", Json.text(value), Nil{}))
        Bool.pick(Unit -> IO(Unit), String.eq(value, "second"), _ => Ctx.abort(ctx), _ => IO.pure(Unit, Unit{}))(Unit{})
        nothing(Ext.ToolCallEventResult)

def resultHook(env: Unit, call: Ext.HandlerCall<Ext.ToolResultEvent>) -> IO(Handled(Ext.ToolResultEventResult)):
  match call:
    case Ext.HandlerCall{Ext.ToolResultEvent{id, _, _, _, _, _, _}, _}:
      do IO<Handled(Ext.ToolResultEventResult)>:
        print("result_hook", Json.field("toolCallId", Json.text(id), Nil{}))
        nothing(Ext.ToolResultEventResult)

def preflightFactoryWith(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    calls : Ext.ExtensionHandler(Ext.ToolCallEvent, Ext.ToolCallEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ToolCallEvent>, ~Handled(Ext.ToolCallEventResult), ~preflight, Unit{})
    results : Ext.ExtensionHandler(Ext.ToolResultEvent, Ext.ToolResultEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ToolResultEvent>, ~Handled(Ext.ToolResultEventResult), ~resultHook, Unit{})
    first : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnToolCall{calls})
    second : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnToolResult{results})
    return both(first, second)

def preflightFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): preflightFactoryWith(api)

def writeCall(+id: String, +value: String) -> Ai.ToolCall<V.Value>:
  Ai.ToolCall{id, "external_write", Json.object(Json.field("value", Json.text(value), Nil{})), None{}, None{}}

def preflightAbort(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => preflightFactory(api)), Unit{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Scripted{[ToolSpec{"external_write", Records{}}]}, setup([Reg.Calls{[writeCall("call_first", "first"), writeCall("call_second", "second")]}]), ref, [inline("preflight", factory)])
    prompted(sessionOf(harness), "run both writes")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# #6363: agent_end and agent_settled handlers; the second extension queues
# one follow-up from agent_end.
def logEnd(env: Unit, call: Ext.HandlerCall<Ext.AgentEndEvent>) -> IO(Handled(Unit)):
  do IO<Handled(Unit)>:
    print("extension_event", Json.field("event", Json.text("agent_end"), Nil{}))
    nothing(Unit)

def logSettled(env: Unit, call: Ext.HandlerCall<Ext.AgentSettledEvent>) -> IO(Handled(Unit)):
  match call:
    case Ext.HandlerCall{_, ctx}:
      do IO<Handled(Unit)>:
        idle : Bool <- Ctx.isIdle(ctx)
        print("extension_event", Json.field("event", Json.text("agent_settled"), Json.field("idle", V.Boolean{idle}, Nil{})))
        nothing(Unit)

def settledFactoryWith(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    ended : Ext.ExtensionHandler(Ext.AgentEndEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.AgentEndEvent>, ~Handled(Unit), ~logEnd, Unit{})
    settled : Ext.ExtensionHandler(Ext.AgentSettledEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.AgentSettledEvent>, ~Handled(Unit), ~logSettled, Unit{})
    first : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnAgentEnd{ended})
    second : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnAgentSettled{settled})
    return both(first, second)

def settledFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): settledFactoryWith(api)

type FollowUpEnv is Data:
  FollowUpEnv{api: Ext.ExtensionAPI, queued: R.Ref<Bool>}

def followUpOnce(env: FollowUpEnv, call: Ext.HandlerCall<Ext.AgentEndEvent>) -> IO(Handled(Unit)):
  match env:
    case FollowUpEnv{api, queued}:
      do IO<Handled(Unit)>:
        already : Bool <- R.modify(Bool, Bool, queued, previous => (True{}, previous))
        Bool.pick(Unit -> IO(Unit), already, _ => IO.pure(Unit, Unit{}), _ => IO.bind(Result<&2, &2, String, Unit>, Unit, Loader.sendUserMessage(api, Ai.UserText{"status follow-up"}, Ext.SendUserMessageOptions{Some{Ext.UserFollowUp{}}, None{}}), _ => IO.pure(Unit, Unit{})))(Unit{})
        nothing(Unit)

def followUpFactoryWith(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    queued : R.Ref<Bool> <- R.new(Bool, False{})
    ended : Ext.ExtensionHandler(Ext.AgentEndEvent, Unit) <- C.create(~FollowUpEnv, ~Ext.HandlerCall<Ext.AgentEndEvent>, ~Handled(Unit), ~followUpOnce, FollowUpEnv{api, queued})
    settled : Ext.ExtensionHandler(Ext.AgentSettledEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.AgentSettledEvent>, ~Handled(Unit), ~logSettled, Unit{})
    first : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnAgentEnd{ended})
    second : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnAgentSettled{settled})
    return both(first, second)

def followUpFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): followUpFactoryWith(api)

def settledAfterRetry(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => settledFactory(api)), Unit{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup([Reg.Failed{"overloaded_error"}, Reg.Text{"recovered"}]), ref, [inline("settled", factory)])
    prompted(sessionOf(harness), "test")
    cleanup(harness)

def settledAfterFollowUp(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => followUpFactory(api)), Unit{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup([Reg.Text{"first"}, Reg.Text{"second"}]), ref, [inline("follow-up", factory)])
    prompted(sessionOf(harness), "hello")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# ... and an extension command whose waitForIdle waits for session-level
# settlement. The command context actions are bound as the upstream test's
# bindExtensions({ commandContextActions }) binds them.
def afterIdle(env: Chan(Unit), call: Ext.CommandCall) -> IO(Result<&2, &2, String, Unit>):
  match call:
    case Ext.CommandCall{_, +ctx}:
      do IO<Result<&2, &2, String, Unit>>:
        sent : Bool <- Chan.send(Unit, env, Unit{})
        Ctx.waitForIdle(ctx)
        idle : Bool <- Ctx.isIdle(Ctx.commandContext(ctx))
        print("command_result", Json.field("idle", V.Boolean{idle}, Nil{}))
        return Done{Unit{}}

def afterIdleFactory(started: Chan(Unit), api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.CommandHandler() <- C.create(~Chan(Unit), ~Ext.CommandCall, ~Result<&2, &2, String, Unit>, ~afterIdle, started)
    Loader.registerCommand(api, "after-idle", Ext.CommandOptions{Some{"Wait for idle"}, None{}, handler})

def waitFound(found: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{session}: Session.waitForIdle(session)

def waitIdle(env: R.Ref<Maybe<&2, Session.AgentSession>>, unit: Unit) -> IO(Unit):
  do IO<Unit>:
    found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, env)
    waitFound(found)

def notCancelled(-A: Data, env: Unit, request: A) -> IO(Ctx.SessionChange): IO.pure(Ctx.SessionChange, Ctx.notCancelled())
def nothingToDo(env: Unit, unit: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def commandActions(ref: R.Ref<Maybe<&2, Session.AgentSession>>) -> IO(Ctx.ExtensionCommandContextActions):
  do IO<Ctx.ExtensionCommandContextActions>:
    idle : C.Callback<Unit, Unit> <- C.create(~R.Ref<Maybe<&2, Session.AgentSession>>, ~Unit, ~Unit, ~waitIdle, ref)
    fresh : C.Callback<Ctx.NewSessionRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.NewSessionRequest, ~Ctx.SessionChange, ~notCancelled(Ctx.NewSessionRequest), Unit{})
    forked : C.Callback<Ctx.ForkRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.ForkRequest, ~Ctx.SessionChange, ~notCancelled(Ctx.ForkRequest), Unit{})
    navigated : C.Callback<Ctx.NavigateTreeRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.NavigateTreeRequest, ~Ctx.SessionChange, ~notCancelled(Ctx.NavigateTreeRequest), Unit{})
    switched : C.Callback<Ctx.SwitchSessionRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.SwitchSessionRequest, ~Ctx.SessionChange, ~notCancelled(Ctx.SwitchSessionRequest), Unit{})
    reloaded : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~nothingToDo, Unit{})
    return Ctx.ExtensionCommandContextActions{idle, fresh, forked, navigated, switched, reloaded}

def bindCommands(runner: Maybe<&2, Runner.ExtensionRunner>, actions: Ctx.ExtensionCommandContextActions) -> IO(Unit):
  match runner:
    case None{}: IO.pure(Unit, Unit{})
    case Some{found}: Runner.bindCommandContext(found, Some{actions})

def promptInBackground(session: Session.AgentSession, +text: String, done: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.prompt(session, text, Nil{}, None{})
    H.reportOutcome("prompted", result)
    sent : Bool <- Chan.send(Unit, done, Unit{})
    return Unit{}

def commandWaitsForIdle(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +toolStarted : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +commandStarted : Chan(Unit) <- Chan.new(Unit, 1)
    +promptDone : Chan(Unit) <- Chan.new(Unit, 1)
    +commandDone : Chan(Unit) <- Chan.new(Unit, 1)
    +factory : Ext.ExtensionFactory() <- C.create(~Chan(Unit), ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => afterIdleFactory(environment, api)), commandStarted)
    +harness : Harness <- createHarnessWith(dir, agentDir, Scripted{[ToolSpec{"wait", Gated{toolStarted, release}}]}, setup([Reg.Call{"call_wait", "wait", Json.object(Nil{}), "{}"}, Reg.Text{"done"}]), ref, [inline("after-idle", factory)])
    actions : Ctx.ExtensionCommandContextActions <- commandActions(ref)
    runner : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(sessionOf(harness))
    bindCommands(runner, actions)
    IO.spawn(Unit, promptInBackground(sessionOf(harness), "start", promptDone))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, toolStarted)
    IO.spawn(Unit, promptInBackground(sessionOf(harness), "/after-idle", commandDone))
    entered : Maybe<&1, Unit> <- Chan.recv(Unit, commandStarted)
    IO.sleep(1)
    print("released", Nil{})
    sent : Bool <- Chan.send(Unit, release, Unit{})
    first : Maybe<&1, Unit> <- Chan.recv(Unit, promptDone)
    second : Maybe<&1, Unit> <- Chan.recv(Unit, commandDone)
    cleanup(harness)

# #3688: session_before_tree cancels the navigation.
def cancelTree(env: Unit, call: Ext.HandlerCall<Ext.SessionBeforeTreeEvent>) -> IO(Handled(Ext.SessionBeforeTreeResult)):
  IO.pure(Handled(Ext.SessionBeforeTreeResult), Done{Some{Ext.SessionBeforeTreeResult{Some{True{}}, None{}, None{}, None{}, None{}}}})

def cancelTreeFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionBeforeTreeEvent, Ext.SessionBeforeTreeResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.SessionBeforeTreeEvent>, ~Handled(Ext.SessionBeforeTreeResult), ~cancelTree, Unit{})
    subscribe(api, Ext.OnSessionBeforeTree{handler})

def currentLeaf(+session: Session.AgentSession) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    +stored : Session.Session() <- Session.sessionOf(session)
    return S.getLeafId(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, stored))

def reportLeafValue(+label: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    leaf : Maybe<&2, String> <- currentLeaf(session)
    IO.print("{\"type\":\"" ++ label ++ "\",\"leafId\":" ++ H.maybeQuoted(leaf) ++ "}")

def firstEntryId(+session: Session.AgentSession) -> IO(String):
  do IO<String>:
    +stored : Session.Session() <- Session.sessionOf(session)
    return Reg.firstUser(stored)

def treeCancelCompacting(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => cancelTreeFactory(api)), Unit{})
    +harness : Harness <- createHarnessFull(dir, agentDir, Builtins{}, setup(Nil{}), ref, [inline("cancel-tree", factory)], [Reg.userMsg("first"), Reg.assistantAt("reply", Ai.Stop{}, Reg.usageOf(Reg.zero()), Reg.zero()), Reg.userMsg("second")], Nil{})
    reportLeafValue("before", sessionOf(harness))
    +target : String <- firstEntryId(sessionOf(harness))
    result : Result<&2, &2, String, Session.TreeNavigation> <- Session.navigateTreeWith(sessionOf(harness), target, Session.noSummary())
    Reg.reportTreeNavigation(result)
    H.reportCompacting(sessionOf(harness))
    reportLeafValue("after", sessionOf(harness))
    cleanup(harness)

# #9178: a navigation waits in session_before_tree while a second one runs.
def waitingTree(env: H.Gate, call: Ext.HandlerCall<Ext.SessionBeforeTreeEvent>) -> IO(Handled(Ext.SessionBeforeTreeResult)):
  do IO<Handled(Ext.SessionBeforeTreeResult)>:
    H.holdAt(Some{env})
    nothing(Ext.SessionBeforeTreeResult)

def waitingTreeFactory(gate: H.Gate, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionBeforeTreeEvent, Ext.SessionBeforeTreeResult) <- C.create(~H.Gate, ~Ext.HandlerCall<Ext.SessionBeforeTreeEvent>, ~Handled(Ext.SessionBeforeTreeResult), ~waitingTree, gate)
    subscribe(api, Ext.OnSessionBeforeTree{handler})

def navigateLater(session: Session.AgentSession, +targetId: String, done: Chan(Reg.Navigated)) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Session.TreeNavigation> <- Session.navigateTreeWith(session, targetId, Session.noSummary())
    sent : Bool <- Chan.send(Reg.Navigated, done, Reg.Navigated{result})
    return Unit{}

def assistantIdAt(+session: Session.AgentSession, +index: Nat) -> IO(String):
  do IO<String>:
    +stored : Session.Session() <- Session.sessionOf(session)
    return Reg.targetIn(stored, "assistant:" ++ Nat.show(index))

def treeWaiting(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Reg.Navigated) <- Chan.new(Reg.Navigated, 1)
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~H.Gate, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => waitingTreeFactory(environment, api)), H.Gate{started, release})
    +harness : Harness <- createHarnessFull(dir, agentDir, Builtins{}, setup(Nil{}), ref, [inline("waiting-tree", factory)], [Reg.userMsg("first user"), Reg.assistantAt("first assistant", Ai.Stop{}, Reg.usageOf(Reg.zero()), Reg.zero()), Reg.userMsg("second user"), Reg.assistantAt("second assistant", Ai.Stop{}, Reg.usageOf(Reg.zero()), Reg.zero())], Nil{})
    reportLeafValue("original", sessionOf(harness))
    +firstTarget : String <- assistantIdAt(sessionOf(harness), 1n)
    +secondTarget : String <- firstEntryId(sessionOf(harness))
    print("targets", Json.field("first", Json.text(firstTarget), Json.field("second", Json.text(secondTarget), Nil{})))
    IO.spawn(Unit, navigateLater(sessionOf(harness), firstTarget, done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    second : Result<&2, &2, String, Session.TreeNavigation> <- Session.navigateTreeWith(sessionOf(harness), secondTarget, Session.noSummary())
    Reg.reportTreeNavigation(second)
    reportLeafValue("during", sessionOf(harness))
    sent : Bool <- Chan.send(Unit, release, Unit{})
    first : Maybe<&1, Reg.Navigated> <- Chan.recv(Reg.Navigated, done)
    Reg.reportNavigated(first)
    reportLeafValue("final", sessionOf(harness))
    cleanup(harness)

# suite/agent-session-compaction-model-overrides.test.ts
# ------------------------------------------------------
# History of two 400-character exchanges whose assistant usage reports
# `total` input tokens (upstream seedHistory).
def padded(+label: String, +fill: String) -> String: label ++ String.repeat(fill, Nat.sub(400n, String.length(label)))

def seededUsage(+total: U32) -> Ai.Usage:
  Ai.Usage{U32.to_f64(total), Reg.zero(), Reg.zero(), Reg.zero(), None{}, None{}, U32.to_f64(total), Ai.UsageCost{Reg.zero(), Reg.zero(), Reg.zero(), Reg.zero(), Reg.zero()}}

def seedHistory(+total: U32, +now: F64) -> List<&2, Session.Message()>:
  [Reg.userAt(padded("old", "x"), Reg.before(now, 2000)), Reg.assistantAt(padded("old", "y"), Ai.Stop{}, seededUsage(total), Reg.before(now, 1000)), Reg.userAt(padded("recent", "x"), Reg.before(now, 2000)), Reg.assistantAt(padded("recent", "y"), Ai.Stop{}, seededUsage(total), Reg.before(now, 1000))]

def reasonName(reason: Ext.CompactionReason) -> String:
  match reason:
    case Ext.ManualReason{}: "manual"
    case Ext.ThresholdReason{}: "threshold"
    case Ext.OverflowReason{}: "overflow"

def preparationFields(preparation: Compaction.CompactionPreparation<V.Value, Tools.ToolDetails, V.Value>) -> List<&2, Rec.Property<V.Value>>:
  match preparation:
    case Compaction.CompactionPreparation{firstKept, _, _, _, _, _, _, Compaction.CompactionSettings{enabled, reserve, keep}}:
      Json.field("firstKeptEntryId", Json.text(firstKept), Json.field("settings", Json.object(Json.field("enabled", V.Boolean{enabled}, Json.field("reserveTokens", V.Number{reserve}, Json.field("keepRecentTokens", V.Number{keep}, Nil{})))), Nil{}))

def suppliedCompaction(preparation: Compaction.CompactionPreparation<V.Value, Tools.ToolDetails, V.Value>, +summary: String) -> Compaction.CompactionResult:
  match preparation:
    case Compaction.CompactionPreparation{firstKept, _, _, _, tokensBefore, _, _, _}: Compaction.CompactionResult{summary, firstKept, tokensBefore, None{}, None{}, None{}}

# The handler records each preparation and supplies the compaction.
def supplyCompaction(summary: String, call: Ext.HandlerCall<Ext.SessionBeforeCompactEvent>) -> IO(Handled(Ext.SessionBeforeCompactResult)):
  match call:
    case Ext.HandlerCall{Ext.SessionBeforeCompactEvent{+preparation, _, _, reason, _, _}, _}:
      do IO<Handled(Ext.SessionBeforeCompactResult)>:
        print("preparation", Json.field("reason", Json.text(reasonName(reason)), preparationFields(preparation)))
        return Done{Some{Ext.SessionBeforeCompactResult{None{}, Some{suppliedCompaction(preparation, summary)}}}}

def supplyFactory(summary: String, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionBeforeCompactEvent, Ext.SessionBeforeCompactResult) <- C.create(~String, ~Ext.HandlerCall<Ext.SessionBeforeCompactEvent>, ~Handled(Ext.SessionBeforeCompactResult), ~supplyCompaction, summary)
    subscribe(api, Ext.OnSessionBeforeCompact{handler})

def reportSeeded(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    print("seeded", Json.field("userIds", V.ArrayValue{Reg.texts(H.userIds(S.getEntries(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, stored))))}, Nil{}))

def compactionShapes(entries: List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case S.Compaction{S.CompactionEntry{_, summary, keep, _, _, _, _, _}} <> rest: Json.object(Json.field("summary", Json.text(summary), Json.field("firstKeptEntryId", Json.text(keep), Nil{}))) <> compactionShapes(rest)
    case _ <> rest: compactionShapes(rest)

def reportCompactions(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    print("compactions", Json.field("entries", V.ArrayValue{compactionShapes(S.getEntries(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, stored)))}, Nil{}))

def overrideReplies(+path: String) -> List<&2, Reg.Reply>:
  match path:
    case "manual": Nil{}
    case "overflow": [Reg.Failed{"prompt is too long"}, Reg.Text{"recovered"}]
    case "post-run": [Reg.Text{String.repeat("z", 8000n)}]
    case _: [Reg.Text{"done"}]

def compactOrPrompt(+path: String, +session: Session.AgentSession) -> IO(Unit):
  match path:
    case "manual":
      do IO<Unit>:
        result : Result<&2, &2, String, Compaction.CompactionResult> <- Session.compact(session, None{})
        H.reportCompact(result)
    case _: prompted(session, "continue")

def compactionOverride(+dir: String, agentDir: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +now : F64 <- Date.now()
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~String, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => supplyFactory(environment, api)), "compacted history")
    +harness : Harness <- createHarnessFull(dir, agentDir, Scripted{Nil{}}, Reg.Setup{overrideReplies(path), Nil{}, Reg.sizedModel(4000, 16384)}, ref, [inline("supply", factory)], seedHistory(Bool.pick(U32, String.eq(path, "pre-prompt"), 2500, 650), now), Nil{})
    reportSeeded(sessionOf(harness))
    compactOrPrompt(path, sessionOf(harness))
    Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
    cleanup(harness)

# "passes resolved budgets to built-in %s summarization": no extension; the
# summary request's output cap is printed with the request.
def compactionBudget(+dir: String, agentDir: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    +now : F64 <- Date.now()
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +replies : List<&2, Reg.Reply> = Bool.pick(List<&2, Reg.Reply>, String.eq(path, "manual"), [Reg.Text{"built-in summary"}], [Reg.Text{"built-in summary"}, Reg.Text{"done"}])
    +harness : Harness <- createHarnessFull(dir, agentDir, Scripted{Nil{}}, Reg.Setup{replies, Nil{}, Reg.sizedModel(4000, 3000)}, ref, Nil{}, seedHistory(2500, now), Nil{})
    reportSeeded(sessionOf(harness))
    compactOrPrompt(Bool.pick(String, String.eq(path, "manual"), "manual", "prompt"), sessionOf(harness))
    reportCompactions(sessionOf(harness))
    Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
    cleanup(harness)

# "uses the newly selected model without changing ordinary settings".
def reportReserve(+label: String, +session: Session.AgentSession, model: Maybe<&2, Settings.ModelIdentity>) -> IO(Unit):
  do IO<Unit>:
    manager : Settings.SettingsManager <- Session.getSettings(session)
    print(label, Json.field("reserveTokens", V.Number{F.fromU64(Settings.getCompactionReserveTokens(manager, model))}, Nil{}))

def switched(+session: Session.AgentSession, +model: Ai.Model<Ai.JsonValue>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.setModel(session, model, Session.ModelMutationOptions{True{}})
    H.reportOutcome("set_model", result)

def appendAll(+session: Session.AgentSession, messages: List<&2, Session.Message()>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit, Unit{})
    case message <> rest:
      do IO<Unit>:
        appended : Result<&2, &2, String, Unit> <- Session.appendSessionMessage(session, message)
        appendAll(session, rest)

def reseed(+session: Session.AgentSession, +now: F64) -> IO(Unit):
  do IO<Unit>:
    appendAll(session, seedHistory(2500, now))
    Session.refreshSessionContext(session)

def compactionModelSwitch(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +now : F64 <- Date.now()
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +small : Ai.Model<Ai.JsonValue> = Reg.namedModel("small", 4000, 16384)
    +big : Ai.Model<Ai.JsonValue> = Reg.namedModel("big", 10000, 16384)
    +factory : Ext.ExtensionFactory() <- C.create(~String, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => supplyFactory(environment, api)), "big model summary")
    +harness : Harness <- createHarnessFull(dir, agentDir, Scripted{Nil{}}, Reg.Setup{[Reg.Text{"small response"}, Reg.Text{"big response"}], Nil{}, small}, ref, [inline("supply", factory)], seedHistory(2500, now), [big])
    prompted(sessionOf(harness), "continue on small")
    print("small_done", Nil{})
    reseed(sessionOf(harness), now)
    switched(sessionOf(harness), big)
    prompted(sessionOf(harness), "continue on big")
    reportReserve("reserve", sessionOf(harness), None{})
    switched(sessionOf(harness), small)
    reportReserve("reserve_small", sessionOf(harness), Some{Settings.ModelIdentity{"faux", "small"}})
    cleanup(harness)

# suite/lax-message-content.test.ts: session entries with null or missing
# content become context messages with empty content.
def reportContextMessages(result: Result<&2, &2, S.Error, List<&2, Session.Message()>>) -> IO(Unit):
  match result:
    case Done{messages}: print("context_messages", Json.field("messages", V.ArrayValue{JsonEvent.messages(messages)}, Nil{}))
    case Fail{_}: print("entry_invalid", Nil{})

def reportContextOf(entry: Maybe<&2, S.FileEntry<V.Value, Tools.ToolDetails, V.Value>>) -> IO(Unit):
  match entry:
    case Some{S.Entry{value}}: reportContextMessages(S.sessionEntryToContextMessages(V.Value, Tools.ToolDetails, V.Value, value))
    case _: print("entry_invalid", Nil{})

def entryMessages(+line: String) -> IO(Unit):
  reportContextOf(SessionJson.parseSessionEntryLine(~V.Value, ~Tools.ToolDetails, ~V.Value, ~Session.readRaw, ~Session.readDetails, ~Session.readRaw, line))

# The in-memory cases of lax-message-content with the native value for
# "no content" (an empty list): a tool result without content, a message_end
# replacement without content and a custom message without content.
def withoutContent(message: Session.Message()) -> Maybe<&2, Session.Message()>:
  match message:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{_, api, provider, model, a, b, c, d, usage, stop, e, f, g, h, time}}}: Some{T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Nil{}, api, provider, model, a, b, c, d, usage, stop, e, f, g, h, time}}}}
    case _: None{}

def emptyEnd(env: Unit, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)):
  match call:
    case Ext.HandlerCall{Ext.MessageEndEvent{message}, _}: IO.pure(Handled(Ext.MessageEndEventResult), Done{Some{Ext.MessageEndEventResult{withoutContent(message)}}})

def emptyEndFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.MessageEndEvent, Ext.MessageEndEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.MessageEndEvent>, ~Handled(Ext.MessageEndEventResult), ~emptyEnd, Unit{})
    subscribe(api, Ext.OnMessageEnd{handler})

def laxContent(+dir: String, agentDir: String, +kind: String) -> IO(Unit):
  match kind:
    case "tool":
      do IO<Unit>:
        +harness : Harness <- createHarness(dir, agentDir, Scripted{[ToolSpec{"web_search", NoContent{}}]}, setup([Reg.Call{"call_search", "web_search", Json.object(Nil{}), "{}"}, Reg.Text{"done"}]))
        prompted(sessionOf(harness), "search something")
        H.reportMessages(sessionOf(harness))
        Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
        cleanup(harness)
    case "message_end":
      do IO<Unit>:
        +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
        +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => emptyEndFactory(api)), Unit{})
        +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup([Reg.Text{"hello"}]), ref, [inline("empty-end", factory)])
        prompted(sessionOf(harness), "hi")
        H.reportMessages(sessionOf(harness))
        cleanup(harness)
    case _:
      do IO<Unit>:
        +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup(Nil{}))
        sent : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(sessionOf(harness), Ext.CustomMessageInput{"test", Ai.UserBlocks{Nil{}}, False{}, None{}}, Session.sendDefaults())
        H.reportMessages(sessionOf(harness))
        cleanup(harness)

# #2023: a follow-up an extension queues with sendUserMessage is raw user
# text, not an extension command.
def recordCommand(env: Unit, call: Ext.CommandCall) -> IO(Result<&2, &2, String, Unit>):
  match call:
    case Ext.CommandCall{args, _}:
      do IO<Result<&2, &2, String, Unit>>:
        print("command_run", Json.field("args", Json.text(args), Nil{}))
        return Done{Unit{}}

def testCommandFactory(apiRef: R.Ref<Maybe<&2, Ext.ExtensionAPI>>, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    R.write(Maybe<&2, Ext.ExtensionAPI>, apiRef, Some{api})
    handler : Ext.CommandHandler() <- C.create(~Unit, ~Ext.CommandCall, ~Result<&2, &2, String, Unit>, ~recordCommand, Unit{})
    Loader.registerCommand(api, "testcmd", Ext.CommandOptions{Some{"Test command"}, None{}, handler})

def sendFollowUp(found: Maybe<&2, Ext.ExtensionAPI>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{api}:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Loader.sendUserMessage(api, Ai.UserText{"/testcmd queued"}, Ext.SendUserMessageOptions{Some{Ext.UserFollowUp{}}, None{}})
        H.reportOutcome("sent", result)

def queuedSlashFollowUp(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +apiRef : R.Ref<Maybe<&2, Ext.ExtensionAPI>> <- R.new(Maybe<&2, Ext.ExtensionAPI>, None{})
    +toolStarted : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Unit) <- Chan.new(Unit, 1)
    +factory : Ext.ExtensionFactory() <- C.create(~R.Ref<Maybe<&2, Ext.ExtensionAPI>>, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => testCommandFactory(environment, api)), apiRef)
    +harness : Harness <- createHarnessWith(dir, agentDir, Scripted{[ToolSpec{"wait", Gated{toolStarted, release}}]}, setup([Reg.Call{"call_wait", "wait", Json.object(Nil{}), "{}"}, Reg.Text{"first turn complete"}, Reg.Text{"queued follow-up handled by model"}]), ref, [inline("testcmd", factory)])
    IO.spawn(Unit, promptInBackground(sessionOf(harness), "start", done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, toolStarted)
    found : Maybe<&2, Ext.ExtensionAPI> <- R.read(Maybe<&2, Ext.ExtensionAPI>, apiRef)
    sendFollowUp(found)
    sent : Bool <- Chan.send(Unit, release, Unit{})
    finished : Maybe<&1, Unit> <- Chan.recv(Unit, done)
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# suite/agent-session-boundaries.test.ts
# --------------------------------------
# A scripted boundary handler: optionally only for one outcome and only
# once, it sends messages through the ExtensionAPI and returns drafts and a
# continuation decision. Each call prints the event (`boundary` lines).
type Send is Data:
  SendUser{text: String, delivery: Ext.UserDelivery}
  SendCustom{customType: String, text: String, triggerTurn: Bool}

type Drafts is Data:
  Literal{drafts: List<&2, Ext.SessionBoundaryDraft>}
  ReplaceUser{instruction: String}
  OmitTurn{}
  ReplaceMessage{text: String}
  OmitAll{}
  OmitUser{}
  OmitMessage{}
  NoDrafts{}

type Action is Data:
  Action{once: Bool, onlyOutcome: Maybe<&2, String>, sends: List<&2, Send>, drafts: Drafts, continue: Maybe<&2, Bool>}

type ActionEnv is Data:
  ActionEnv{api: Ext.ExtensionAPI, fired: R.Ref<Bool>, action: Action, session: R.Ref<Maybe<&2, Session.AgentSession>>}

def outcomeName(outcome: Ext.AgentActivityOutcome) -> String:
  match outcome:
    case Ext.OutcomeCompleted{}: "completed"
    case Ext.OutcomeAborted{}: "aborted"
    case Ext.OutcomeError{}: "error"

def sendAll(+api: Ext.ExtensionAPI, sends: List<&2, Send>) -> IO(Unit):
  match sends:
    case Nil{}: IO.pure(Unit, Unit{})
    case SendUser{text, delivery} <> rest:
      do IO<Unit>:
        sent : Result<&2, &2, String, Unit> <- Loader.sendUserMessage(api, Ai.UserText{text}, Ext.SendUserMessageOptions{Some{delivery}, None{}})
        sendAll(api, rest)
    case SendCustom{customType, text, triggerTurn} <> rest:
      do IO<Unit>:
        sent : Result<&2, &2, String, Unit> <- Loader.sendMessage(api, Ext.CustomMessageInput{customType, Ai.UserText{text}, False{}, None{}}, Ext.SendMessageOptions{Some{triggerTurn}, None{}})
        sendAll(api, rest)

def lastUserId(entries: List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>, found: String) -> String:
  match entries:
    case Nil{}: found
    case S.SessionMessageEntry{S.SessionEntryBase{id, _, _}, T.LlmMessage{Ai.User{_}}} <> rest: lastUserId(rest, id)
    case _ <> rest: lastUserId(rest, found)

def branchUserId(found: Maybe<&2, Session.AgentSession>) -> IO(String):
  match found:
    case None{}: IO.pure(String, "missing-user")
    case Some{session}:
      do IO<String>:
        +stored : Session.Session() <- Session.sessionOf(session)
        return lastUserId(Result.default(&2, &2, S.Error, List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>, S.getBranch(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, stored), S.Latest{}), Nil{}), "missing-user")

def messageIds(entries: List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case S.SessionMessageEntry{S.SessionEntryBase{id, _, _}, T.LlmMessage{Ai.User{_}}} <> rest: id <> messageIds(rest)
    case S.SessionMessageEntry{S.SessionEntryBase{id, _, _}, T.LlmMessage{Ai.Assistant{_}}} <> rest: id <> messageIds(rest)
    case S.SessionMessageEntry{S.SessionEntryBase{id, _, _}, T.LlmMessage{Ai.ToolResult{_}}} <> rest: id <> messageIds(rest)
    case _ <> rest: messageIds(rest)

def branchMessageIds(found: Maybe<&2, Session.AgentSession>) -> IO(List<&2, String>):
  match found:
    case None{}: IO.pure(List<&2, String>, Nil{})
    case Some{session}:
      do IO<List<&2, String>>:
        +stored : Session.Session() <- Session.sessionOf(session)
        return messageIds(Result.default(&2, &2, S.Error, List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>, S.getBranch(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, stored), S.Latest{}), Nil{}))

def omitted(+ids: List<&2, String>) -> List<&2, Ext.SessionBoundaryDraft>:
  match ids:
    case Nil{}: Nil{}
    case id <> rest: Ext.ContextEditEntryDraft{id, None{}} <> omitted(rest)

def bookkeeping() -> Ext.SessionBoundaryDraft: Ext.CustomEntryDraft{"bookkeeping", Some{Json.object(Json.field("source", Json.text("test"), Nil{}))}}

def draftsFor(+drafts: Drafts, sessionRef: R.Ref<Maybe<&2, Session.AgentSession>>, +messageEntryId: String, +toolResultIds: List<&2, String>) -> IO(Maybe<&2, List<&2, Ext.SessionBoundaryDraft>>):
  match drafts:
    case Literal{list}: IO.pure(Maybe<&2, List<&2, Ext.SessionBoundaryDraft>>, Some{list})
    case ReplaceUser{instruction}:
      do IO<Maybe<&2, List<&2, Ext.SessionBoundaryDraft>>>:
        found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, sessionRef)
        userId : String <- branchUserId(found)
        return Some{[Ext.ContextEditEntryDraft{userId, Some{S.ContentText{instruction}}}, Ext.ContextEditEntryDraft{messageEntryId, None{}}, bookkeeping()]}
    case OmitTurn{}:
      do IO<Maybe<&2, List<&2, Ext.SessionBoundaryDraft>>>:
        found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, sessionRef)
        userId : String <- branchUserId(found)
        return Some{omitted(userId <> messageEntryId <> toolResultIds)}
    case ReplaceMessage{text}: IO.pure(Maybe<&2, List<&2, Ext.SessionBoundaryDraft>>, Some{[Ext.ContextEditEntryDraft{messageEntryId, Some{S.ContentText{text}}}]})
    case OmitMessage{}: IO.pure(Maybe<&2, List<&2, Ext.SessionBoundaryDraft>>, Some{[Ext.ContextEditEntryDraft{messageEntryId, None{}}]})
    case OmitUser{}:
      do IO<Maybe<&2, List<&2, Ext.SessionBoundaryDraft>>>:
        found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, sessionRef)
        userId : String <- branchUserId(found)
        return Some{[Ext.ContextEditEntryDraft{userId, None{}}]}
    case OmitAll{}:
      do IO<Maybe<&2, List<&2, Ext.SessionBoundaryDraft>>>:
        found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, sessionRef)
        ids : List<&2, String> <- branchMessageIds(found)
        return Some{omitted(ids)}
    case NoDrafts{}: IO.pure(Maybe<&2, List<&2, Ext.SessionBoundaryDraft>>, None{})

def outcomeMatches(only: Maybe<&2, String>, +outcome: String) -> Bool:
  match only:
    case None{}: True{}
    case Some{wanted}: String.eq(wanted, outcome)

def previewTexts(preview: Ext.BoundaryContextPreview) -> List<&2, Rec.Property<V.Value>>:
  match preview:
    case Ext.BoundaryContextPreview{_, contextMessages, _, pending, canContinue}: Json.field("contextMessages", V.ArrayValue{JsonEvent.messages(contextMessages)}, Json.field("pendingMessages", V.ArrayValue{JsonEvent.messages(pending)}, Json.field("canContinue", V.Boolean{canContinue}, Nil{})))

def acted(env: ActionEnv, +event: String, +messageEntryId: String, +toolResultIds: List<&2, String>, +outcome: Ext.AgentActivityOutcome, context: Ext.BoundaryContextPreview) -> IO(Handled(Ext.BoundaryResult)):
  match env:
    case ActionEnv{+api, +fired, Action{+once, +only, +sends, +drafts, +continued}, +sessionRef}:
      do IO<Handled(Ext.BoundaryResult)>:
        print("boundary", Json.field("event", Json.text(event), Json.field("messageEntryId", Json.text(messageEntryId), Json.field("outcome", Json.text(outcomeName(outcome)), previewTexts(context)))))
        already : Bool <- R.read(Bool, fired)
        Bool.pick(Unit -> IO(Handled(Ext.BoundaryResult)), Bool.or(Bool.and(once, already), Bool.not(outcomeMatches(only, outcomeName(outcome)))),
          _ => nothing(Ext.BoundaryResult),
          _ => do IO<Handled(Ext.BoundaryResult)>:
            R.write(Bool, fired, True{})
            sendAll(api, sends)
            list : Maybe<&2, List<&2, Ext.SessionBoundaryDraft>> <- draftsFor(drafts, sessionRef, messageEntryId, toolResultIds)
            return Done{Some{Ext.BoundaryResult{list, continued}}})(Unit{})

def turnEndAction(env: ActionEnv, call: Ext.HandlerCall<Ext.TurnEndEvent>) -> IO(Handled(Ext.BoundaryResult)):
  match call:
    case Ext.HandlerCall{Ext.TurnEndEvent{_, _, _, messageEntryId, toolResultIds, _, _, context, outcome}, _}: acted(env, "turn_end", messageEntryId, toolResultIds, outcome, context)

def settleAction(env: ActionEnv, call: Ext.HandlerCall<Ext.AgentBeforeSettleEvent>) -> IO(Handled(Ext.BoundaryResult)):
  match call:
    case Ext.HandlerCall{Ext.AgentBeforeSettleEvent{_, _, context, outcome}, _}: acted(env, "agent_before_settle", "", Nil{}, outcome, context)

# An agent_end handler that sends once (upstream sendMessage/sendUserMessage
# from agent_end).
type EndEnv is Data:
  EndEnv{api: Ext.ExtensionAPI, fired: R.Ref<Bool>, sends: List<&2, Send>, afterText: Maybe<&2, String>}

def endTexts(messages: List<&2, Session.Message()>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}} <> rest: Session.assistantText(content) <> endTexts(rest)
    case _ <> rest: endTexts(rest)

def containsText(texts: List<&2, String>, +wanted: String) -> Bool:
  match texts:
    case Nil{}: False{}
    case text <> rest: Bool.or(String.eq(text, wanted), containsText(rest, wanted))

def endAction(env: EndEnv, call: Ext.HandlerCall<Ext.AgentEndEvent>) -> IO(Handled(Unit)):
  match env call:
    case EndEnv{+api, +fired, +sends, +after} Ext.HandlerCall{Ext.AgentEndEvent{+messages}, _}:
      do IO<Handled(Unit)>:
        already : Bool <- R.read(Bool, fired)
        +wanted : Bool = Bool.and(Bool.not(already), Maybe.default(&2, Bool, Maybe.map(&2, String, Bool, text => containsText(endTexts(messages), text), after), True{}))
        Bool.pick(Unit -> IO(Unit), wanted, _ => IO.bind(Unit, Unit, R.write(Bool, fired, True{}), _ => sendAll(api, sends)), _ => IO.pure(Unit, Unit{}))(Unit{})
        nothing(Unit)

# `usage` replaces each assistant message's input and total tokens at
# message_end (output 1).
type BoundaryScript is Data:
  BoundaryScript{turnEnd: Maybe<&2, Action>, beforeSettle: Maybe<&2, Action>, agentEnd: List<&2, Send>, agentEndAfter: Maybe<&2, String>, compaction: Maybe<&2, String>, usage: Maybe<&2, U32>}

def subscribeAction(+api: Ext.ExtensionAPI, +ref: R.Ref<Maybe<&2, Session.AgentSession>>, turnEnd: Bool, +action: Maybe<&2, Action>) -> IO(Result<&2, &2, String, Unit>):
  match action:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Some{+chosen}:
      do IO<Result<&2, &2, String, Unit>>:
        +fired : R.Ref<Bool> <- R.new(Bool, False{})
        Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), turnEnd,
          _ => IO.bind(Ext.ExtensionHandler(Ext.TurnEndEvent, Ext.BoundaryResult), Result<&2, &2, String, Unit>, C.create(~ActionEnv, ~Ext.HandlerCall<Ext.TurnEndEvent>, ~Handled(Ext.BoundaryResult), ~turnEndAction, ActionEnv{api, fired, chosen, ref}), handler => subscribe(api, Ext.OnTurnEnd{handler})),
          _ => IO.bind(Ext.ExtensionHandler(Ext.AgentBeforeSettleEvent, Ext.BoundaryResult), Result<&2, &2, String, Unit>, C.create(~ActionEnv, ~Ext.HandlerCall<Ext.AgentBeforeSettleEvent>, ~Handled(Ext.BoundaryResult), ~settleAction, ActionEnv{api, fired, chosen, ref}), handler => subscribe(api, Ext.OnAgentBeforeSettle{handler})))(Unit{})

def subscribeEnd(+api: Ext.ExtensionAPI, sends: List<&2, Send>, after: Maybe<&2, String>) -> IO(Result<&2, &2, String, Unit>):
  match sends:
    case Nil{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case more:
      do IO<Result<&2, &2, String, Unit>>:
        fired : R.Ref<Bool> <- R.new(Bool, False{})
        handler : Ext.ExtensionHandler(Ext.AgentEndEvent, Unit) <- C.create(~EndEnv, ~Ext.HandlerCall<Ext.AgentEndEvent>, ~Handled(Unit), ~endAction, EndEnv{api, fired, more, after})
        subscribe(api, Ext.OnAgentEnd{handler})

def usageOverride(+total: U32, usage: Ai.Usage) -> Ai.Usage:
  match usage:
    case Ai.Usage{_, _, cacheRead, cacheWrite, a, b, _, cost}: Ai.Usage{U32.to_f64(U32.sub(total, 1)), U32.to_f64(1), cacheRead, cacheWrite, a, b, U32.to_f64(total), cost}

def withUsage(+total: U32, message: Session.Message()) -> Maybe<&2, Session.Message()>:
  match message:
    case T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, api, provider, model, a, b, c, d, usage, stop, e, f, g, h, time}}}: Some{T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, api, provider, model, a, b, c, d, usageOverride(total, usage), stop, e, f, g, h, time}}}}
    case _: None{}

def usageEnd(total: U32, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)):
  match call:
    case Ext.HandlerCall{Ext.MessageEndEvent{message}, _}: IO.pure(Handled(Ext.MessageEndEventResult), Done{Some{Ext.MessageEndEventResult{withUsage(total, message)}}})

def subscribeUsage(+api: Ext.ExtensionAPI, usage: Maybe<&2, U32>) -> IO(Result<&2, &2, String, Unit>):
  match usage:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Some{total}:
      do IO<Result<&2, &2, String, Unit>>:
        handler : Ext.ExtensionHandler(Ext.MessageEndEvent, Ext.MessageEndEventResult) <- C.create(~U32, ~Ext.HandlerCall<Ext.MessageEndEvent>, ~Handled(Ext.MessageEndEventResult), ~usageEnd, total)
        subscribe(api, Ext.OnMessageEnd{handler})

def subscribeCompaction(+api: Ext.ExtensionAPI, summary: Maybe<&2, String>) -> IO(Result<&2, &2, String, Unit>):
  match summary:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Some{text}: supplyFactory(text, api)

def scriptFactoryWith(+ref: R.Ref<Maybe<&2, Session.AgentSession>>, script: BoundaryScript, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match script:
    case BoundaryScript{turnEnd, beforeSettle, agentEnd, after, compaction, usage}:
      do IO<Result<&2, &2, String, Unit>>:
        zeroth : Result<&2, &2, String, Unit> <- subscribeUsage(api, usage)
        first : Result<&2, &2, String, Unit> <- subscribeAction(api, ref, True{}, turnEnd)
        second : Result<&2, &2, String, Unit> <- subscribeAction(api, ref, False{}, beforeSettle)
        third : Result<&2, &2, String, Unit> <- subscribeEnd(api, agentEnd, after)
        fourth : Result<&2, &2, String, Unit> <- subscribeCompaction(api, compaction)
        return both(zeroth, both(first, both(second, both(third, fourth))))

def scriptFactory(ref: R.Ref<Maybe<&2, Session.AgentSession>>, script: BoundaryScript, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): scriptFactoryWith(ref, script, api)

type BoundaryEnv is Data:
  BoundaryEnv{ref: R.Ref<Maybe<&2, Session.AgentSession>>, script: BoundaryScript}

def scriptFrom(env: BoundaryEnv, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match env:
    case BoundaryEnv{ref, script}: scriptFactory(ref, script, api)

def noScript() -> BoundaryScript: BoundaryScript{None{}, None{}, Nil{}, None{}, None{}, None{}}

def withTurnEnd(action: Action) -> BoundaryScript: BoundaryScript{Some{action}, None{}, Nil{}, None{}, None{}, None{}}

def withSettle(action: Action) -> BoundaryScript: BoundaryScript{None{}, Some{action}, Nil{}, None{}, None{}, None{}}

def handoff() -> Ext.SessionBoundaryDraft: Ext.CompactionEntryDraft{"exact handoff", None{}, Some{Json.object(Json.field("source", Json.text("test"), Nil{}))}, None{}}

def compactionIdShapes(entries: List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case S.Compaction{S.CompactionEntry{S.SessionEntryBase{id, _, _}, summary, keep, _, _, _, _, _}} <> rest: Json.object(Json.field("id", Json.text(id), Json.field("summary", Json.text(summary), Json.field("firstKeptEntryId", Json.text(keep), Nil{})))) <> compactionIdShapes(rest)
    case S.CustomEntry{_, customType, _} <> rest: Json.object(Json.field("custom", Json.text(customType), Nil{})) <> compactionIdShapes(rest)
    case S.CustomMessageEntry{_, customType, _, _, display} <> rest: Json.object(Json.field("customMessage", Json.text(customType), Json.field("display", V.Boolean{display}, Nil{}))) <> compactionIdShapes(rest)
    case S.ContextEditEntry{_, target, replacement} <> rest: Json.object(Json.field("contextEdit", Json.text(target), Json.field("omitted", V.Boolean{Maybe.is_none(&2, S.ContextEditableContent, replacement)}, Nil{}))) <> compactionIdShapes(rest)
    case S.SessionMessageEntry{S.SessionEntryBase{id, _, _}, T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, stop, _, _, _, _, _}}}} <> rest: Json.object(Json.field("assistant", Json.text(id), Json.field("text", Json.text(Session.assistantText(content)), Json.field("length", V.Boolean{Session.isLengthStop(stop)}, Nil{})))) <> compactionIdShapes(rest)
    case _ <> rest: compactionIdShapes(rest)

def reportSessionEntries(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +stored : Session.Session() <- Session.sessionOf(session)
    print("session_entries", Json.field("entries", V.ArrayValue{compactionIdShapes(S.getEntries(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, stored)))}, Json.field("projected", V.ArrayValue{JsonEvent.messages(Session.sessionMessages(stored))}, Nil{})))

def usageValue(result: Result<&2, &2, S.Error, Maybe<&2, Stats.ContextUsage>>) -> V.Value:
  match result:
    case Done{Some{Stats.ContextUsage{Some{tokens}, _, _}}}: V.Number{tokens}
    case _: V.Null{}

def reportUsage(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    usage : Result<&2, &2, S.Error, Maybe<&2, Stats.ContextUsage>> <- Session.getContextUsage(session)
    print("context_usage", Json.field("tokens", usageValue(usage), Nil{}))

# A boundary scenario: the scripted extension, tools, replies, a model and
# a seed, then one prompt and the session's entries.
def boundaryRun(+dir: String, agentDir: String, tooling: Tooling, setupValue: Reg.Setup, script: BoundaryScript, seed: List<&2, Session.Message()>, +text: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~BoundaryEnv, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~scriptFrom, BoundaryEnv{ref, script})
    +harness : Harness <- createHarnessFull(dir, agentDir, tooling, setupValue, ref, [inline("boundary", factory)], seed, Nil{})
    prompted(sessionOf(harness), text)
    reportSessionEntries(sessionOf(harness))
    Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
    reportUsage(sessionOf(harness))
    count : Nat <- Session.pendingMessageCount(sessionOf(harness))
    print("pending", Json.field("count", V.Number{U32.to_f64(U32.from_nat(count))}, Nil{}))
    cleanup(harness)

def queueSends(+kind: String) -> List<&2, Send>:
  match kind:
    case "steering": [SendUser{"queued steering", Ext.UserSteer{}}]
    case "follow-up": [SendUser{"queued follow-up", Ext.UserFollowUp{}}]
    case _: [SendUser{"queued steering", Ext.UserSteer{}}, SendUser{"queued follow-up", Ext.UserFollowUp{}}]

# "commits pre-settlement drafts but suppresses continuation when aborted
# during the hook": the agent_before_settle handler waits on a gate.
def gatedSettle(env: H.Gate, call: Ext.HandlerCall<Ext.AgentBeforeSettleEvent>) -> IO(Handled(Ext.BoundaryResult)):
  do IO<Handled(Ext.BoundaryResult)>:
    H.holdAt(Some{env})
    return Done{Some{Ext.BoundaryResult{Some{[Ext.CustomEntryDraft{"committed-after-abort", Some{V.Boolean{True{}}}}]}, Some{True{}}}}}

def gatedSettleFactory(gate: H.Gate, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.AgentBeforeSettleEvent, Ext.BoundaryResult) <- C.create(~H.Gate, ~Ext.HandlerCall<Ext.AgentBeforeSettleEvent>, ~Handled(Ext.BoundaryResult), ~gatedSettle, gate)
    subscribe(api, Ext.OnAgentBeforeSettle{handler})

def abortLater(session: Session.AgentSession, done: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    Session.abort(session)
    sent : Bool <- Chan.send(Unit, done, Unit{})
    return Unit{}

def settleAbort(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +prompted : Chan(Unit) <- Chan.new(Unit, 1)
    +aborted : Chan(Unit) <- Chan.new(Unit, 1)
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~H.Gate, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => gatedSettleFactory(environment, api)), H.Gate{started, release})
    +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup([Reg.Text{"first"}, Reg.Text{"must not run"}]), ref, [inline("gated-settle", factory)])
    IO.spawn(Unit, promptInBackground(sessionOf(harness), "start", prompted))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    IO.spawn(Unit, abortLater(sessionOf(harness), aborted))
    IO.sleep(5)
    sent : Bool <- Chan.send(Unit, release, Unit{})
    first : Maybe<&1, Unit> <- Chan.recv(Unit, prompted)
    second : Maybe<&1, Unit> <- Chan.recv(Unit, aborted)
    reportSessionEntries(sessionOf(harness))
    Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))
    cleanup(harness)

# "refreshes canonical context before publishing boundary entry
# notifications": a listener snapshots the session's messages at each
# entry_appended event.
def snapshotMessages(found: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{session}:
      do IO<Unit>:
        current : List<&2, Session.Message()> <- Session.messages(session)
        print("append_snapshot", Json.field("messages", V.ArrayValue{JsonEvent.messages(current)}, Nil{}))

def snapshotOnAppend(env: R.Ref<Maybe<&2, Session.AgentSession>>, event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.EntryAppended{_}:
      do IO<Unit>:
        found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, env)
        snapshotMessages(found)
    case _: IO.pure(Unit, Unit{})

def refreshNotifications(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~BoundaryEnv, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~scriptFrom, BoundaryEnv{ref, withTurnEnd(Action{True{}, None{}, Nil{}, Literal{[Ext.CustomEntryDraft{"metadata", Some{V.Boolean{True{}}}}, Ext.CustomMessageEntryDraft{"visible-context", Ai.UserText{"committed context"}, True{}, None{}}]}, None{}})})
    +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup([Reg.Text{"done"}]), ref, [inline("boundary", factory)])
    +listener : Session.Listener() <- C.create(~R.Ref<Maybe<&2, Session.AgentSession>>, ~Session.AgentSessionEvent, ~Unit, ~snapshotOnAppend, ref)
    Session.subscribe(sessionOf(harness), listener)
    prompted(sessionOf(harness), "start")
    Session.unsubscribe(sessionOf(harness), listener)
    C.dispose(Session.AgentSessionEvent, Unit, listener)
    cleanup(harness)

# "does not treat retained pre-compaction assistant usage as
# post-compaction usage": a compaction that keeps the assistant carrying
# the usage.
def compactKeeping(+session: Session.AgentSession, kept: Result<&2, &2, String, String>) -> IO(Result<&2, &2, String, String>):
  match kept:
    case Fail{error}: IO.pure(Result<&2, &2, String, String>, Fail{error})
    case Done{+id}: Session.appendSessionEntry(session, target => Sessions.appendCompaction(~V.Value, ~Tools.ToolDetails, ~V.Value, ~Session.rawValue, ~Tools.detailsValue, ~Session.rawValue, target, "summary", Some{id}, 10001n, None{}, None{}, None{}))

def retainedUsage(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup(Nil{}))
    +retained : Session.Message() = Reg.assistantAt("retained", Ai.Stop{}, seededUsage(10001), Reg.zero())
    appended : Result<&2, &2, String, String> <- Session.appendSessionEntry(sessionOf(harness), target => Session.recordMessage(target, retained))
    compacted : Result<&2, &2, String, String> <- compactKeeping(sessionOf(harness), appended)
    Session.refreshSessionContext(sessionOf(harness))
    reportUsage(sessionOf(harness))
    cleanup(harness)

def boundaryScenario(+dir: String, agentDir: String, +name: String, +argument: String) -> IO(Unit):
  match name:
    case "handoff": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Text{"discarded response"}, Reg.Text{"continued from handoff"}]), withTurnEnd(Action{True{}, None{}, Nil{}, Literal{[handoff()]}, Some{True{}}}), Nil{}, "discarded prompt")
    case "queue": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Text{"first"}, Reg.Text{"second"}, Reg.Text{"third"}]), withTurnEnd(Action{True{}, None{}, queueSends(argument), Literal{[Ext.CompactionEntryDraft{"exact handoff", None{}, None{}, None{}}]}, Some{True{}}}), Nil{}, "start")
    case "replacement": boundaryRun(dir, agentDir, Builtins{}, Reg.Setup{[Reg.Text{"answered original input"}, Reg.Text{"answered replacement"}], Nil{}, Reg.sizedModel(2000, 100)}, BoundaryScript{Some{Action{True{}, None{}, Nil{}, ReplaceUser{String.repeat("EXACT-REPLACEMENT-INSTRUCTION ", 100n)}, Some{True{}}}}, None{}, Nil{}, None{}, Some{"older history summary"}, None{}}, [Reg.userMsg("older input"), Reg.assistantAt("older answer", Ai.Stop{}, Reg.usageOf(Reg.zero()), Reg.zero())], "original input")
    case "unsent": boundaryRun(dir, agentDir, Builtins{}, Reg.Setup{[Reg.Text{"first"}, Reg.Text{"second"}], Nil{}, Reg.sizedModel(2000, 100)}, BoundaryScript{Some{Action{True{}, None{}, Nil{}, Literal{[Ext.CustomMessageEntryDraft{"next-work", Ai.UserText{String.repeat("EXACT-UNSENT-INSTRUCTION ", 100n)}, False{}, None{}}, bookkeeping()]}, Some{True{}}}}, None{}, Nil{}, None{}, Some{"older history summary"}, None{}}, Nil{}, String.repeat("old input ", 500n))
    case "settle_custom": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Text{"first"}, Reg.Text{"second"}]), withSettle(Action{True{}, None{}, Nil{}, Literal{[Ext.CustomMessageEntryDraft{"test-continuation", Ai.UserText{"continue now"}, False{}, None{}}]}, Some{True{}}}), Nil{}, "start")
    case "settle_pending": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Text{"first"}, Reg.Text{"second"}]), BoundaryScript{None{}, Some{Action{True{}, None{}, Nil{}, NoDrafts{}, Some{True{}}}}, [SendCustom{"agent-end-context", "queued after agent end", False{}}], None{}, None{}, None{}}, Nil{}, "start")
    case "settle_follow_up": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Text{"first"}, Reg.Text{"second"}, Reg.Text{"follow-up response"}]), withSettle(Action{True{}, None{}, [SendUser{"queued follow-up", Ext.UserFollowUp{}}], Literal{[Ext.CustomMessageEntryDraft{"boundary", Ai.UserText{"boundary context"}, False{}, None{}}]}, Some{True{}}}), Nil{}, "start")
    case "invalid_continue": boundaryRun(dir, agentDir, Scripted{[ToolSpec{"noop", Echo{"done"}}]}, setup([Reg.Call{"call_noop", "noop", Json.object(Nil{}), "{}"}, Reg.Text{"must not run"}]), withTurnEnd(Action{False{}, None{}, Nil{}, OmitTurn{}, Some{True{}}}), Nil{}, "start")
    case "error_follow_up": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Failed{"overloaded_error"}, Reg.Text{"retry recovered"}, Reg.Text{"follow-up completed"}]), withTurnEnd(Action{True{}, Some{"error"}, [SendUser{"queued follow-up", Ext.UserFollowUp{}}], NoDrafts{}, None{}}), Nil{}, "start")
    case "overflow_replacement": boundaryRun(dir, agentDir, Builtins{}, Reg.Setup{[Reg.FailedText{"retained error", "prompt is too long"}, Reg.Text{"recovered"}], Nil{}, Reg.sizedModel(1000, 100)}, BoundaryScript{Some{Action{True{}, Some{"error"}, Nil{}, ReplaceMessage{"retained error"}, None{}}}, None{}, Nil{}, None{}, Some{"recovered overflow"}, None{}}, Nil{}, String.repeat("x", 5000n))
    case "length_budget": boundaryRun(dir, agentDir, Builtins{}, Reg.Setup{[Reg.Stopped{Reg.Text{"first partial"}}, Reg.Text{"first recovered"}, Reg.Stopped{Reg.Text{"follow-up partial"}}, Reg.Text{"follow-up recovered"}], Nil{}, Reg.sizedModel(1000, 100)}, BoundaryScript{None{}, None{}, [SendUser{"distinct follow-up", Ext.UserFollowUp{}}], Some{"first recovered"}, Some{"recovered input"}, None{}}, Nil{}, String.repeat("x", 5000n))
    case "length_reset": boundaryRun(dir, agentDir, Scripted{[ToolSpec{"noop", Echo{"done"}}]}, Reg.Setup{[Reg.Stopped{Reg.Text{"first partial"}}, Reg.Call{"call_noop", "noop", Json.object(Nil{}), "{}"}, Reg.Stopped{Reg.Text{"second partial"}}, Reg.Text{"completed second recovery"}], Nil{}, Reg.sizedModel(1000, 100)}, BoundaryScript{None{}, None{}, Nil{}, None{}, Some{"recovered input"}, None{}}, Nil{}, String.repeat("x", 5000n))
    case "length_tool": boundaryRun(dir, agentDir, Scripted{[ToolSpec{"unsafe_truncated_tool", Records{}}]}, setup([Reg.Stopped{Reg.Call{"call_unsafe", "unsafe_truncated_tool", Json.object(Json.field("value", Json.text("partial"), Nil{})), "{\"value\":\"partial\"}"}}, Reg.Text{"completed natural continuation"}]), noScript(), Nil{}, "start")
    case "retry_nonretryable": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Failed{"overloaded_error"}, Reg.Failed{"invalid_api_key"}]), noScript(), Nil{}, "start")
    case "retry_exhausted": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Failed{"overloaded_error"}, Reg.Failed{"overloaded_error"}]), noScript(), Nil{}, "start")
    case "recovery_failed": boundaryRun(dir, agentDir, Builtins{}, Reg.Setup{[Reg.Stopped{Reg.Text{"partial response"}}, Reg.FailedText{"summary failed", "summary failed"}, Reg.Text{"must not retry"}], Nil{}, Reg.sizedModel(1000, 100)}, noScript(), Nil{}, String.repeat("x", 5000n))
    case "settle_persist": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Text{"first"}, Reg.Text{"second"}]), withSettle(Action{True{}, None{}, [SendCustom{"pending-boundary", "persist before continue", False{}}], NoDrafts{}, Some{True{}}}), Nil{}, "start")
    case "settle_system_only": boundaryRun(dir, agentDir, Builtins{}, setup([Reg.Text{"first"}, Reg.Text{"must not run"}]), withSettle(Action{True{}, None{}, [SendUser{"still queued", Ext.UserFollowUp{}}], OmitAll{}, Some{True{}}}), Nil{}, "start")
    case "omitted_usage": boundaryRun(dir, agentDir, Builtins{}, Reg.Setup{[Reg.Text{"short response"}], Nil{}, Reg.sizedModel(10000, 100)}, BoundaryScript{Some{Action{True{}, None{}, Nil{}, OmitMessage{}, None{}}}, None{}, Nil{}, None{}, None{}, Some{9801}}, Nil{}, "small prompt")
    case "edited_usage": boundaryRun(dir, agentDir, Builtins{}, Reg.Setup{[Reg.Text{"done"}], Nil{}, Reg.sizedModel(5000, 100)}, BoundaryScript{Some{Action{True{}, None{}, Nil{}, OmitUser{}, None{}}}, None{}, Nil{}, None{}, None{}, Some{5101}}, Nil{}, "large input that is later omitted")
    case _: IO.die(Unit, 1, "unknown boundary scenario")

# suite/regressions/9789-context-handler-system-messages.test.ts
# ------------------------------------------------------------
type ContextKind is Data:
  SliceFromSummary{}
  PrependUser{}
  PrependSystem{}
  DropBashTool{}
  DropSystem{}
  Unchanged{}

def roleNames(messages: List<&2, Session.Message()>) -> List<&2, V.Value>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: Json.text(roleOf(message)) <> roleNames(rest)

def isSummary(message: Session.Message()) -> Bool:
  match message:
    case T.CustomMessage{Messages.CompactionSummary{_}}: True{}
    case _: False{}

# JavaScript's slice(findIndex(...)): without a summary the index is -1, so
# the slice is the last message.
def lastOnly(messages: List<&2, Session.Message()>) -> List<&2, Session.Message()>:
  match messages:
    case Nil{}: Nil{}
    case message <> Nil{}: [message]
    case _ <> rest: lastOnly(rest)

def summarySlice(messages: List<&2, Session.Message()>) -> Maybe<&2, List<&2, Session.Message()>>:
  match messages:
    case Nil{}: None{}
    case +message <> +rest: Bool.pick(Maybe<&2, List<&2, Session.Message()>>, isSummary(message), Some{message <> rest}, summarySlice(rest))

def fromSummary(+messages: List<&2, Session.Message()>) -> List<&2, Session.Message()>:
  Maybe.default(&2, List<&2, Session.Message()>, summarySlice(messages), lastOnly(messages))

def withoutTool(tools: List<&2, Ai.Tool<V.Value>>, +name: String) -> List<&2, Ai.Tool<V.Value>>:
  match tools:
    case Nil{}: Nil{}
    case Ai.Tool{+toolName, description, parameters, sampling} <> rest:
      +tail = withoutTool(rest, name)
      Bool.pick(List<&2, Ai.Tool<V.Value>>, String.eq(toolName, name), tail, Ai.Tool{toolName, description, parameters, sampling} <> tail)

def dropBash(messages: List<&2, Session.Message()>) -> List<&2, Session.Message()>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{Ai.System{Ai.SystemMessage{content, sections, Some{added}, removed, time}}} <> rest: T.LlmMessage{Ai.System{Ai.SystemMessage{content, sections, Some{withoutTool(added, "bash")}, removed, time}}} <> dropBash(rest)
    case message <> rest: message <> dropBash(rest)

def dropSystem(messages: List<&2, Session.Message()>) -> List<&2, Session.Message()>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{Ai.System{_}} <> rest: dropSystem(rest)
    case message <> rest: message <> dropSystem(rest)

def transformed(kind: ContextKind, +messages: List<&2, Session.Message()>) -> List<&2, Session.Message()>:
  match kind:
    case SliceFromSummary{}: fromSummary(messages)
    case PrependUser{}: T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{[Ai.TextImageText{Ai.TextContent{"injected", None{}}}]}, Reg.zero()}}} <> messages
    case PrependSystem{}: T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"ephemeral reminder"}, None{}, None{}, None{}, Reg.zero()}}} <> messages
    case DropBashTool{}: dropBash(messages)
    case DropSystem{}: dropSystem(messages)
    case Unchanged{}: messages

def contextHandler(kind: ContextKind, call: Ext.HandlerCall<Ext.ContextEvent>) -> IO(Handled(Ext.ContextEventResult)):
  match call:
    case Ext.HandlerCall{Ext.ContextEvent{+messages}, _}:
      do IO<Handled(Ext.ContextEventResult)>:
        print("context_seen", Json.field("roles", V.ArrayValue{roleNames(messages)}, Nil{}))
        return Done{Some{Ext.ContextEventResult{Some{transformed(kind, messages)}}}}

def withSystemHandler(kind: ContextKind, call: Ext.HandlerCall<Ext.ContextWithSystemEvent>) -> IO(Handled(Ext.ContextEventResult)):
  match call:
    case Ext.HandlerCall{Ext.ContextWithSystemEvent{+messages}, _}:
      do IO<Handled(Ext.ContextEventResult)>:
        print("with_system_seen", Json.field("roles", V.ArrayValue{roleNames(messages)}, Nil{}))
        return Done{Some{Ext.ContextEventResult{Some{transformed(kind, messages)}}}}

def subscribeContext(+api: Ext.ExtensionAPI, kind: Maybe<&2, ContextKind>, plain: Bool) -> IO(Result<&2, &2, String, Unit>):
  match kind:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Some{+chosen}:
      Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), plain,
        _ => IO.bind(Ext.ExtensionHandler(Ext.ContextEvent, Ext.ContextEventResult), Result<&2, &2, String, Unit>, C.create(~ContextKind, ~Ext.HandlerCall<Ext.ContextEvent>, ~Handled(Ext.ContextEventResult), ~contextHandler, chosen), handler => subscribe(api, Ext.OnContext{handler})),
        _ => IO.bind(Ext.ExtensionHandler(Ext.ContextWithSystemEvent, Ext.ContextEventResult), Result<&2, &2, String, Unit>, C.create(~ContextKind, ~Ext.HandlerCall<Ext.ContextWithSystemEvent>, ~Handled(Ext.ContextEventResult), ~withSystemHandler, chosen), handler => subscribe(api, Ext.OnContextWithSystem{handler})))(Unit{})

def contextFactoryWith(context: Maybe<&2, ContextKind>, withSystem: Maybe<&2, ContextKind>, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    first : Result<&2, &2, String, Unit> <- subscribeContext(api, withSystem, False{})
    second : Result<&2, &2, String, Unit> <- subscribeContext(api, context, True{})
    return both(first, second)

def contextFactory(context: Maybe<&2, ContextKind>, withSystem: Maybe<&2, ContextKind>, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): contextFactoryWith(context, withSystem, api)

type ContextSpec is Data:
  ContextSpec{context: Maybe<&2, ContextKind>, withSystem: Maybe<&2, ContextKind>}

def contextFrom(spec: ContextSpec, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match spec:
    case ContextSpec{context, withSystem}: contextFactory(context, withSystem, api)

def printError(env: Unit, error: Ext.ExtensionError) -> IO(Unit):
  match error:
    case Ext.ExtensionError{_, event, text, _}: print("extension_error", Json.field("event", Json.text(event), Json.field("error", Json.text(text), Nil{})))

def listenErrors(runner: Maybe<&2, Runner.ExtensionRunner>) -> IO(Unit):
  match runner:
    case None{}: IO.pure(Unit, Unit{})
    case Some{found}:
      do IO<Unit>:
        listener : C.Callback<Ext.ExtensionError, Unit> <- C.create(~Unit, ~Ext.ExtensionError, ~Unit, ~printError, Unit{})
        subscription : Runner.ErrorSubscription <- Runner.onError(found, listener)
        return Unit{}

def reportLoadout(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    active : List<&2, String> <- Session.getActiveToolNames(session)
    prompt : String <- Session.systemPrompt(session)
    current : List<&2, Session.Message()> <- Session.messages(session)
    print("loadout", Json.field("activeTools", V.ArrayValue{Reg.texts(active)}, Json.field("systemPrompt", Json.text(prompt), Json.field("roles", V.ArrayValue{roleNames(current)}, Nil{}))))

def compactSession(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    prompted(session, "first")
    prompted(session, "second")
    result : Result<&2, &2, String, Compaction.CompactionResult> <- Session.compact(session, None{})
    H.reportCompact(result)
    reportLoadout(session)

def contextKindOf(+name: String) -> Maybe<&2, ContextKind>:
  match name:
    case "slice": Some{SliceFromSummary{}}
    case "inject": Some{PrependUser{}}
    case "system_add": Some{PrependSystem{}}
    case "with_system": Some{SliceFromSummary{}}
    case _: None{}

def withSystemKindOf(+name: String) -> Maybe<&2, ContextKind>:
  match name:
    case "with_system": Some{DropBashTool{}}
    case "with_system_drop": Some{DropSystem{}}
    case _: None{}

def contextExtensions(compacting: Bool, context: Maybe<&2, ContextKind>, withSystem: Maybe<&2, ContextKind>) -> IO(List<&2, Ext.InlineExtension>):
  match compacting:
    case True{}:
      do IO<List<&2, Ext.InlineExtension>>:
        compact : Ext.ExtensionFactory() <- C.create(~String, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~supplyFactory, "extension summary")
        current : Ext.ExtensionFactory() <- C.create(~ContextSpec, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~contextFrom, ContextSpec{context, withSystem})
        return [inline("compact-via-hook", compact), inline("context", current)]
    case False{}:
      do IO<List<&2, Ext.InlineExtension>>:
        current : Ext.ExtensionFactory() <- C.create(~ContextSpec, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~contextFrom, ContextSpec{context, withSystem})
        return [inline("context", current)]

def contextScenario(+dir: String, agentDir: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +compacting : Bool = Bool.or(String.eq(name, "slice"), String.eq(name, "with_system"))
    +context : Maybe<&2, ContextKind> = contextKindOf(name)
    +withSystem : Maybe<&2, ContextKind> = withSystemKindOf(name)
    +replies : List<&2, Reg.Reply> = Bool.pick(List<&2, Reg.Reply>, compacting, [Reg.Text{"one"}, Reg.Text{"two"}, Reg.Text{"after compaction"}], [Reg.Text{"done"}])
    extensions : List<&2, Ext.InlineExtension> <- contextExtensions(compacting, context, withSystem)
    +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup(replies), ref, extensions)
    runner : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(sessionOf(harness))
    listenErrors(runner)
    Bool.pick(Unit -> IO(Unit), compacting, _ => compactSession(sessionOf(harness)), _ => IO.pure(Unit, Unit{}))(Unit{})
    print("final_prompt", Nil{})
    prompted(sessionOf(harness), Bool.pick(String, compacting, "third", "hello"))
    reportLoadout(sessionOf(harness))
    cleanup(harness)

# AgentSession.getUserMessagesForForking over a seeded session.
def forkShapes(messages: List<&2, Session.ForkMessage>) -> List<&2, V.Value>:
  match messages:
    case Nil{}: Nil{}
    case Session.ForkMessage{id, text} <> rest: Json.object(Json.field("entryId", Json.text(id), Json.field("text", Json.text(text), Nil{}))) <> forkShapes(rest)

def forkMessagesScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- createHarnessFull(dir, agentDir, Builtins{}, setup(Nil{}), ref, Nil{}, [Reg.userMsg("first"), Reg.assistantAt("reply", Ai.Stop{}, Reg.usageOf(Reg.zero()), Reg.zero()), Reg.userMsg(""), Reg.userMsg("second")], Nil{})
    found : List<&2, Session.ForkMessage> <- Session.getUserMessagesForForking(sessionOf(harness))
    reportSessionEntries(sessionOf(harness))
    print("fork_messages", Json.field("messages", V.ArrayValue{forkShapes(found)}, Nil{}))
    cleanup(harness)

# suite/agent-session-prompt.test.ts
# ----------------------------------
def runCall(+id: String, +name: String, +value: String) -> Ai.ToolCall<V.Value>:
  Ai.ToolCall{id, name, Json.object(Json.field("value", Json.text(value), Nil{})), None{}, None{}}

def tinyPng() -> String: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

def syntheticSource(+path: String, +scope: Skills.SourceScope, baseDir: Maybe<&2, String>) -> Skills.SourceInfo:
  Skills.SourceInfo{path, "local", scope, Skills.TopLevel{}, baseDir}

def reviewTemplate() -> Templates.PromptTemplate:
  Templates.PromptTemplate{"review", "Review template", None{}, "Review this code: $1", syntheticSource("/virtual/review.md", Skills.Temporary{}, None{}), "/virtual/review.md"}

def testSkill(+dir: String) -> Skills.Skill:
  +path = dir ++ "/test-skill.md"
  Skills.Skill{"test", "Test skill", path, dir, syntheticSource(path, Skills.Project{}, Some{dir}), False{}}

def resourceHarness(+dir: String, agentDir: String, setupValue: Reg.Setup, +ref: R.Ref<Maybe<&2, Session.AgentSession>>, extensions: List<&2, Ext.InlineExtension>, resources: Resources) -> IO(Harness):
  createHarnessResources(dir, agentDir, Builtins{}, setupValue, ref, extensions, Nil{}, Nil{}, resources)

def reportFauxRemaining(harness: Harness) -> IO(Unit): Reg.reportRemaining(Reg.repliesOf(harnessFixture(harness)))

# "handles a tool call turn and waits for the follow-up LLM response"
def promptToolTurn(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Scripted{[ToolSpec{"echo", Echo{"echo:"}}]}, setup([echoCall("call_echo", "hello"), Reg.Text{"done"}]))
    prompted(sessionOf(harness), "start")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# "executes multiple tool calls from one response and continues with a
# single follow-up response": the slow tool waits 25 ms.
def promptMultipleTools(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Scripted{[ToolSpec{"slow", Runs{"slow", 25}}, ToolSpec{"fast", Runs{"fast", 0}}]}, setup([Reg.Calls{[runCall("call_slow", "slow", "a"), runCall("call_fast", "fast", "b")]}, Reg.Text{"tool results: 2"}]))
    prompted(sessionOf(harness), "run tools")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# "preserves image attachments in the provider context"
def promptImage(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup([Reg.Text{"ok"}]))
    result : Result<&2, &2, String, Unit> <- Session.promptWith(sessionOf(harness), "describe", Session.PromptOptions{True{}, [Ai.ImageContent{tinyPng(), "image/png"}], None{}, Ext.InteractiveSource{}, None{}})
    H.reportOutcome("prompted", result)
    cleanup(harness)

# "expands skill commands before sending the prompt"
def promptSkill(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(dir ++ "/test-skill.md", "# Test Skill\n\nUse the skill body.")
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Text{"ok"}]), ref, Nil{}, Resources{[testSkill(dir)], Nil{}})
    prompted(sessionOf(harness), "/skill:test explain this")
    cleanup(harness)

# "expands prompt templates before sending the prompt" and "sendUserMessage
# can opt into prompt template expansion"
def promptTemplate(+dir: String, agentDir: String, viaSendUserMessage: Bool) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Text{"ok"}]), ref, Nil{}, Resources{Nil{}, [reviewTemplate()]})
    result : Result<&2, &2, String, Unit> <- Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), viaSendUserMessage, _ => Session.sendUserMessage(sessionOf(harness), Ai.UserText{"/review src/index.ts"}, None{}, True{}), _ => Session.prompt(sessionOf(harness), "/review src/index.ts", Nil{}, None{}))(Unit{})
    H.reportOutcome("prompted", result)
    cleanup(harness)

# "dispatches extension commands without consuming a provider response"
def promptCommand(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +apiRef : R.Ref<Maybe<&2, Ext.ExtensionAPI>> <- R.new(Maybe<&2, Ext.ExtensionAPI>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~R.Ref<Maybe<&2, Ext.ExtensionAPI>>, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => testCommandFactory(environment, api)), apiRef)
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Text{"should stay queued"}]), ref, [inline("testcmd", factory)], noResources())
    prompted(sessionOf(harness), "/testcmd hello world")
    H.reportMessages(sessionOf(harness))
    reportFauxRemaining(harness)
    cleanup(harness)

# "extension sendUserMessage can opt into extension command dispatch": the
# command runs on the delivery's own task; the scenario waits for idle.
def sendCommand(found: Maybe<&2, Ext.ExtensionAPI>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{api}:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Loader.sendUserMessage(api, Ai.UserText{"/testcmd hello world"}, Ext.SendUserMessageOptions{None{}, Some{True{}}})
        H.reportOutcome("sent", result)

def untilCommandRan(fuel: Nat, +ran: R.Ref<Bool>) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        done : Bool <- R.read(Bool, ran)
        Bool.pick(Unit -> IO(Unit), done, _ => IO.pure(Unit, Unit{}), _ => IO.bind(Unit, Unit, IO.sleep(5), _ => untilCommandRan(rest, ran)))(Unit{})

def markCommand(ran: R.Ref<Bool>, call: Ext.CommandCall) -> IO(Result<&2, &2, String, Unit>):
  match call:
    case Ext.CommandCall{args, _}:
      do IO<Result<&2, &2, String, Unit>>:
        print("command_run", Json.field("args", Json.text(args), Nil{}))
        R.write(Bool, ran, True{})
        return Done{Unit{}}

def markingCommandFactory(apiRef: R.Ref<Maybe<&2, Ext.ExtensionAPI>>, ran: R.Ref<Bool>, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    R.write(Maybe<&2, Ext.ExtensionAPI>, apiRef, Some{api})
    handler : Ext.CommandHandler() <- C.create(~R.Ref<Bool>, ~Ext.CommandCall, ~Result<&2, &2, String, Unit>, ~markCommand, ran)
    Loader.registerCommand(api, "testcmd", Ext.CommandOptions{Some{"Test command"}, None{}, handler})

type MarkEnv is Data:
  MarkEnv{apiRef: R.Ref<Maybe<&2, Ext.ExtensionAPI>>, ran: R.Ref<Bool>}

def markingFrom(env: MarkEnv, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match env:
    case MarkEnv{apiRef, ran}: markingCommandFactory(apiRef, ran, api)

def extensionSendCommand(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +apiRef : R.Ref<Maybe<&2, Ext.ExtensionAPI>> <- R.new(Maybe<&2, Ext.ExtensionAPI>, None{})
    +ran : R.Ref<Bool> <- R.new(Bool, False{})
    +factory : Ext.ExtensionFactory() <- C.create(~MarkEnv, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~markingFrom, MarkEnv{apiRef, ran})
    +harness : Harness <- resourceHarness(dir, agentDir, setup(Nil{}), ref, [inline("testcmd", factory)], noResources())
    found : Maybe<&2, Ext.ExtensionAPI> <- R.read(Maybe<&2, Ext.ExtensionAPI>, apiRef)
    sendCommand(found)
    untilCommandRan(1000n, ran)
    H.reportMessages(sessionOf(harness))
    reportFauxRemaining(harness)
    cleanup(harness)

# "sendUserMessage while idle triggers a turn"
def sendUserIdle(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup([Reg.Text{"response"}]))
    result : Result<&2, &2, String, Unit> <- Session.sendUserMessage(sessionOf(harness), Ai.UserText{"from extension"}, None{}, False{})
    H.reportOutcome("sent", result)
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# "throws when prompted during manual compaction": session_before_compact
# waits on a gate, then supplies the compaction.
def heldCompaction(gate: H.Gate, call: Ext.HandlerCall<Ext.SessionBeforeCompactEvent>) -> IO(Handled(Ext.SessionBeforeCompactResult)):
  match gate call:
    case H.Gate{started, release} Ext.HandlerCall{Ext.SessionBeforeCompactEvent{+preparation, _, _, _, _, _}, _}:
      do IO<Handled(Ext.SessionBeforeCompactResult)>:
        sent : Bool <- Chan.send(Unit, started, Unit{})
        released : Maybe<&1, Unit> <- Chan.recv(Unit, release)
        return Done{Some{Ext.SessionBeforeCompactResult{None{}, Some{suppliedCompaction(preparation, "manual compacted")}}}}

def heldCompactionFactory(gate: H.Gate, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionBeforeCompactEvent, Ext.SessionBeforeCompactResult) <- C.create(~H.Gate, ~Ext.HandlerCall<Ext.SessionBeforeCompactEvent>, ~Handled(Ext.SessionBeforeCompactResult), ~heldCompaction, gate)
    subscribe(api, Ext.OnSessionBeforeCompact{handler})

def promptDuringCompaction(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Reg.Compacted) <- Chan.new(Reg.Compacted, 1)
    +factory : Ext.ExtensionFactory() <- C.create(~H.Gate, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => heldCompactionFactory(environment, api)), H.Gate{started, release})
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Text{"one"}, Reg.Text{"two"}]), ref, [inline("held", factory)], noResources())
    prompted(sessionOf(harness), "first")
    prompted(sessionOf(harness), "second")
    IO.spawn(Unit, Reg.compactInBackground(sessionOf(harness), done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    third : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(harness), "third", Nil{}, None{})
    H.reportOutcome("third", third)
    sent : Bool <- Chan.send(Unit, release, Unit{})
    finished : Maybe<&1, Reg.Compacted> <- Chan.recv(Reg.Compacted, done)
    Reg.reportCompacted(finished)
    cleanup(harness)

# Input handlers: `record` prints each input event; `transform` handles
# "ping" and prefixes everything else with "transformed:".
def deliveryName(behavior: Maybe<&2, Ext.UserDelivery>) -> V.Value:
  match behavior:
    case None{}: V.Null{}
    case Some{Ext.UserSteer{}}: Json.text("steer")
    case Some{Ext.UserFollowUp{}}: Json.text("followUp")

def recordInput(env: Unit, call: Ext.HandlerCall<Ext.InputEvent>) -> IO(Handled(Ext.InputEventResult)):
  match call:
    case Ext.HandlerCall{Ext.InputEvent{text, _, _, behavior}, _}:
      do IO<Handled(Ext.InputEventResult)>:
        print("input", Json.field("text", Json.text(text), Json.field("streamingBehavior", deliveryName(behavior), Nil{})))
        return Done{None{}}

def transformInput(env: Unit, call: Ext.HandlerCall<Ext.InputEvent>) -> IO(Handled(Ext.InputEventResult)):
  match call:
    case Ext.HandlerCall{Ext.InputEvent{+text, _, _, _}, _}:
      IO.pure(Handled(Ext.InputEventResult), Done{Some{Bool.pick(Ext.InputEventResult, String.eq(text, "ping"), Ext.InputHandled{}, Ext.InputTransform{"transformed:" ++ text, None{}})}})

def inputFactory(transform: Bool, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.InputEvent, Ext.InputEventResult) <- Bool.pick(Unit -> IO(Ext.ExtensionHandler(Ext.InputEvent, Ext.InputEventResult)), transform, _ => C.create(~Unit, ~Ext.HandlerCall<Ext.InputEvent>, ~Handled(Ext.InputEventResult), ~transformInput, Unit{}), _ => C.create(~Unit, ~Ext.HandlerCall<Ext.InputEvent>, ~Handled(Ext.InputEventResult), ~recordInput, Unit{}))(Unit{})
    subscribe(api, Ext.OnInput{handler})

# "does not report streamingBehavior to input handlers while idle"
def inputIdle(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Bool, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => inputFactory(environment, api)), False{})
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Text{"ok"}]), ref, [inline("input", factory)], noResources())
    result : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(harness), "idle", Nil{}, Some{Session.FollowUp{}})
    H.reportOutcome("prompted", result)
    cleanup(harness)

# "reports streamingBehavior to input handlers while streaming"
def inputStreaming(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +toolStarted : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Unit) <- Chan.new(Unit, 1)
    +factory : Ext.ExtensionFactory() <- C.create(~Bool, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => inputFactory(environment, api)), False{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Scripted{[ToolSpec{"wait", Gated{toolStarted, release}}]}, setup([Reg.Call{"call_wait", "wait", Json.object(Nil{}), "{}"}, Reg.Text{"done"}]), ref, [inline("input", factory)])
    IO.spawn(Unit, promptInBackground(sessionOf(harness), "start", done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, toolStarted)
    queued : Result<&2, &2, String, Unit> <- Session.prompt(sessionOf(harness), "queued", Nil{}, Some{Session.FollowUp{}})
    H.reportOutcome("queued", queued)
    sent : Bool <- Chan.send(Unit, release, Unit{})
    finished : Maybe<&1, Unit> <- Chan.recv(Unit, done)
    cleanup(harness)

# agent-session-model-extension: "allows extension input handlers to
# transform or handle input"
def inputTransform(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Bool, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => inputFactory(environment, api)), True{})
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Text{"done"}]), ref, [inline("input", factory)], noResources())
    prompted(sessionOf(harness), "hello")
    prompted(sessionOf(harness), "ping")
    H.reportMessages(sessionOf(harness))
    reportFauxRemaining(harness)
    cleanup(harness)

# before_agent_start handlers. `StartKind` picks the behavior:
# SwitchModel switches to a model (pi.setModel), Inject adds a custom
# message and forces the prompt, PlanSection adds a plan_mode section on the
# second prompt.
type StartKind is Data:
  SwitchModel{model: Ai.Model<Ai.JsonValue>}
  Inject{}
  PlanSection{turns: R.Ref<Nat>}

type StartEnv is Data:
  StartEnv{api: Ext.ExtensionAPI, kind: StartKind}

def switchModelNow(+api: Ext.ExtensionAPI, model: Ai.Model<Ai.JsonValue>) -> IO(Handled(Ext.BeforeAgentStartEventResult)):
  do IO<Handled(Ext.BeforeAgentStartEventResult)>:
    switched : Result<&2, &2, String, Bool> <- Loader.setModel(api, model)
    print("set_model", Json.field("ok", Json.boolean(Result.default(&2, &2, String, Bool, switched, False{})), Nil{}))
    return Done{None{}}

def withPlanSection(options: Prompt.NormalizedBuildSystemPromptOptions) -> Prompt.NormalizedBuildSystemPromptOptions:
  match options:
    case Prompt.NormalizedBuildSystemPromptOptions{custom, forced, tools, snippets, rules, guidelines, append, sections, cwd, files, skills}:
      Prompt.NormalizedBuildSystemPromptOptions{custom, forced, tools, snippets, rules, guidelines, append, Rec.set(String, sections, "plan_mode", "Plan only."), cwd, files, skills}

def countedTurn(+count: Nat) -> Nat & Nat: (count + 1n, count + 1n)

def planOnSecond(turns: R.Ref<Nat>, options: Prompt.NormalizedBuildSystemPromptOptions) -> IO(Handled(Ext.BeforeAgentStartEventResult)):
  do IO<Handled(Ext.BeforeAgentStartEventResult)>:
    turn : Nat <- R.modify(Nat, Nat, turns, count => countedTurn(count))
    return Done{Bool.pick(Maybe<&2, Ext.BeforeAgentStartEventResult>, Nat.is_eq(turn, 2n), Some{Ext.BeforeAgentStartEventResult{None{}, None{}, Some{withPlanSection(options)}}}, None{})}

def startHandler(env: StartEnv, call: Ext.HandlerCall<Ext.BeforeAgentStartEvent>) -> IO(Handled(Ext.BeforeAgentStartEventResult)):
  match env call:
    case StartEnv{api, SwitchModel{model}} _: switchModelNow(api, model)
    case StartEnv{_, Inject{}} Ext.HandlerCall{Ext.BeforeAgentStartEvent{_, _, systemPrompt, _}, _}:
      IO.pure(Handled(Ext.BeforeAgentStartEventResult), Done{Some{Ext.BeforeAgentStartEventResult{Some{Ext.CustomMessageInput{"before-start", Ai.UserText{"injected"}, True{}, Some{Json.object(Json.field("injected", Json.boolean(True{}), Nil{}))}}}, Some{systemPrompt ++ "\n\nextra instructions"}, None{}}}})
    case StartEnv{_, PlanSection{turns}} Ext.HandlerCall{Ext.BeforeAgentStartEvent{_, _, _, options}, _}: planOnSecond(turns, options)

def startFactory(kind: StartKind, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.BeforeAgentStartEvent, Ext.BeforeAgentStartEventResult) <- C.create(~StartEnv, ~Ext.HandlerCall<Ext.BeforeAgentStartEvent>, ~Handled(Ext.BeforeAgentStartEventResult), ~startHandler, StartEnv{api, kind})
    subscribe(api, Ext.OnBeforeAgentStart{handler})

def reportModel(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    current : Session.AgentState() <- Session.state(session)
    print("model", Json.field("id", Json.text(Maybe.default(&2, String, Maybe.map(&2, Ai.Model<Ai.JsonValue>, String, Ai.modelId, Session.stateModel(current)), "")), Nil{}))

# agent-session-prompt: "uses the model selected by before_agent_start for
# image normalization" (a 1100 px wide PNG, the strict model's 1000 px cap).
def beforeStartImage(+dir: String, agentDir: String, +image: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~StartKind, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => startFactory(environment, api)), SwitchModel{H.strictModel()})
    +harness : Harness <- createHarnessFull(dir, agentDir, Builtins{}, Reg.Setup{[Reg.Text{"done"}], Nil{}, H.wideModel()}, ref, [inline("switch", factory)], Nil{}, [H.strictModel()])
    result : Result<&2, &2, String, Unit> <- Session.promptWith(sessionOf(harness), "inspect", Session.PromptOptions{True{}, [Ai.ImageContent{image, "image/png"}], None{}, Ext.InteractiveSource{}, None{}})
    H.reportOutcome("prompted", result)
    reportModel(sessionOf(harness))
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# agent-session-model-extension: "allows before_agent_start handlers to
# inject custom messages and modify the system prompt"
def beforeStartInject(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~StartKind, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => startFactory(environment, api)), Inject{})
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Text{"done"}]), ref, [inline("inject", factory)], noResources())
    prompted(sessionOf(harness), "hello")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# #9789: "keeps mid-conversation system messages in place when a handler
# leaves the conversation unchanged": before_agent_start adds a plan_mode
# section on the second prompt; the context handler returns its messages.
def planSectionScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +turns : R.Ref<Nat> <- R.new(Nat, 0n)
    plan : Ext.ExtensionFactory() <- C.create(~StartKind, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => startFactory(environment, api)), PlanSection{turns})
    context : Ext.ExtensionFactory() <- C.create(~ContextSpec, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~contextFrom, ContextSpec{Some{Unchanged{}}, None{}})
    +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup([Reg.Text{"one"}, Reg.Text{"two"}]), ref, [inline("plan", plan), inline("context", context)])
    prompted(sessionOf(harness), "first")
    prompted(sessionOf(harness), "second")
    cleanup(harness)

# Extension tools (#6162): `switch_tools` switches the active set to
# `after_switch` when executed.
type SwitchEnv is Data:
  SwitchEnv{api: Ext.ExtensionAPI, kind: String}

def switchExecute(env: SwitchEnv, call: Ext.ToolCallInput) -> IO(Tools.Output()):
  match env:
    case SwitchEnv{api, "switch"}:
      do IO<Tools.Output()>:
        switched : Result<&2, &2, String, Unit> <- Loader.setActiveTools(api, ["after_switch"])
        return textResult("switched", Json.object(Nil{}))
    case SwitchEnv{_, _}: IO.pure(Tools.Output(), textResult("after", Json.object(Nil{})))

def switchTool(+api: Ext.ExtensionAPI, +name: String, +kind: String, +label: String, +description: String, +snippet: String) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    execute : Ext.ToolExecute() <- C.create(~SwitchEnv, ~Ext.ToolCallInput, ~Tools.Output(), ~switchExecute, SwitchEnv{api, kind})
    Loader.registerTool(api, Ext.ToolDefinition{name, label, description, Some{snippet}, Nil{}, emptySchema(), None{}, None{}, execute, Ext.DefaultShell{}, None{}, None{}, None{}})

def registerSwitchTools(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    first : Result<&2, &2, String, Unit> <- switchTool(api, "switch_tools", "switch", "Switch Tools", "Switch the active extension tool set", "Switch to the next extension tool")
    second : Result<&2, &2, String, Unit> <- switchTool(api, "after_switch", "after", "After Switch", "Tool that should be available after switching", "Run after the active tool set changes")
    return both(first, second)

def printSessionPrompt(found: Maybe<&2, Session.AgentSession>) -> IO(Unit):
  match found:
    case None{}: IO.pure(Unit, Unit{})
    case Some{session}:
      do IO<Unit>:
        prompt : String <- Session.systemPrompt(session)
        print("session_prompt", Json.field("prompt", Json.text(prompt), Nil{}))

# A context handler that prints the session's system prompt when each
# request is prepared.
def sessionPromptAt(ref: R.Ref<Maybe<&2, Session.AgentSession>>, call: Ext.HandlerCall<Ext.ContextEvent>) -> IO(Handled(Ext.ContextEventResult)):
  do IO<Handled(Ext.ContextEventResult)>:
    found : Maybe<&2, Session.AgentSession> <- R.read(Maybe<&2, Session.AgentSession>, ref)
    printSessionPrompt(found)
    return Done{None{}}

def overrideStart(env: Unit, call: Ext.HandlerCall<Ext.BeforeAgentStartEvent>) -> IO(Handled(Ext.BeforeAgentStartEventResult)):
  match call:
    case Ext.HandlerCall{Ext.BeforeAgentStartEvent{_, _, systemPrompt, _}, _}:
      IO.pure(Handled(Ext.BeforeAgentStartEventResult), Done{Some{Ext.BeforeAgentStartEventResult{None{}, Some{systemPrompt ++ "\n\nkeep this run override"}, None{}}}})

def switchFactory(ref: R.Ref<Maybe<&2, Session.AgentSession>>, kind: String, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    registered : Result<&2, &2, String, Unit> <- registerSwitchTools(api)
    context : Ext.ExtensionHandler(Ext.ContextEvent, Ext.ContextEventResult) <- C.create(~R.Ref<Maybe<&2, Session.AgentSession>>, ~Ext.HandlerCall<Ext.ContextEvent>, ~Handled(Ext.ContextEventResult), ~sessionPromptAt, ref)
    watched : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnContext{context})
    start : Ext.ExtensionHandler(Ext.BeforeAgentStartEvent, Ext.BeforeAgentStartEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.BeforeAgentStartEvent>, ~Handled(Ext.BeforeAgentStartEventResult), ~overrideStart, Unit{})
    overridden : Result<&2, &2, String, Unit> <- Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), String.eq(kind, "override"), _ => subscribe(api, Ext.OnBeforeAgentStart{start}), _ => IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}}))(Unit{})
    return both(both(registered, watched), overridden)

type SwitchFactoryEnv is Data:
  SwitchFactoryEnv{ref: R.Ref<Maybe<&2, Session.AgentSession>>, kind: String}

def switchFrom(env: SwitchFactoryEnv, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match env:
    case SwitchFactoryEnv{ref, kind}: switchFactory(ref, kind, api)

def textValues(names: List<&2, String>) -> List<&2, V.Value>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: Json.text(name) <> textValues(rest)

def reportActiveTools(+label: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    names : List<&2, String> <- Session.getActiveToolNames(session)
    print("active_tools", Json.field("label", Json.text(label), Json.field("names", V.ArrayValue{textValues(names)}, Nil{})))

# #6162: extension tools switch the active set mid-run.
def switchScenario(+dir: String, agentDir: String, +kind: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~SwitchFactoryEnv, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~switchFrom, SwitchFactoryEnv{ref, kind})
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Call{"call_switch", "switch_tools", Json.object(Nil{}), "{}"}, Reg.Text{"done"}]), ref, [inline("switch", factory)], noResources())
    Session.setActiveToolsByName(sessionOf(harness), ["switch_tools"])
    reportActiveTools("before", sessionOf(harness))
    prompted(sessionOf(harness), "start")
    reportActiveTools("after", sessionOf(harness))
    cleanup(harness)

# agent-session-dynamic-tools: a session_start handler registers a tool
# (with a snippet and a guideline, or hidden without a snippet).
type DynamicEnv is Data:
  DynamicEnv{api: Ext.ExtensionAPI, hidden: Bool}

def dynamicExecute(env: Unit, call: Ext.ToolCallInput) -> IO(Tools.Output()): IO.pure(Tools.Output(), textResult("ok", Json.object(Nil{})))

def dynamicDefinition(hidden: Bool, execute: Ext.ToolExecute()) -> Ext.ToolDefinition:
  match hidden:
    case True{}: Ext.ToolDefinition{"hidden_tool", "Hidden Tool", "Description should not appear in available tools", None{}, Nil{}, emptySchema(), None{}, None{}, execute, Ext.DefaultShell{}, None{}, None{}, None{}}
    case False{}: Ext.ToolDefinition{"dynamic_tool", "Dynamic Tool", "Tool registered from session_start", Some{"Run dynamic test behavior"}, ["Use dynamic_tool when the user asks for dynamic behavior tests."], emptySchema(), None{}, None{}, execute, Ext.DefaultShell{}, None{}, None{}, None{}}

def registerOnStart(env: DynamicEnv, call: Ext.HandlerCall<Ext.SessionStartEvent>) -> IO(Handled(Unit)):
  match env:
    case DynamicEnv{api, hidden}:
      do IO<Handled(Unit)>:
        execute : Ext.ToolExecute() <- C.create(~Unit, ~Ext.ToolCallInput, ~Tools.Output(), ~dynamicExecute, Unit{})
        registered : Result<&2, &2, String, Unit> <- Loader.registerTool(api, dynamicDefinition(hidden, execute))
        return Done{None{}}

def dynamicFactory(hidden: Bool, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionStartEvent, Unit) <- C.create(~DynamicEnv, ~Ext.HandlerCall<Ext.SessionStartEvent>, ~Handled(Unit), ~registerOnStart, DynamicEnv{api, hidden})
    subscribe(api, Ext.OnSessionStart{handler})

def infoNamesOf(infos: List<&2, Session.ToolInfo()>) -> List<&2, V.Value>:
  match infos:
    case Nil{}: Nil{}
    case Ext.ToolInfo{name, _, _, _, _} <> rest: Json.text(name) <> infoNamesOf(rest)
def infoMetadata(infos: List<&2, Session.ToolInfo()>) -> List<&2, V.Value>:
  match infos:
    case Nil{}: Nil{}
    case Ext.ToolInfo{name,_,_,guidelines,Skills.SourceInfo{path,source,_,_,_}} <> rest:
      Json.object(Json.field("name",Json.text(name),Json.field("source",Json.text(source),Json.field("path",Json.text(path),Json.field("promptGuidelines",V.ArrayValue{textValues(guidelines)},Nil{}))))) <> infoMetadata(rest)

def reportTools(+label: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +all : List<&2, Session.ToolInfo()> <- Session.getAllTools(session)
    active : List<&2, String> <- Session.getActiveToolNames(session)
    prompt : String <- Session.systemPrompt(session)
    print("tools", Json.field("label", Json.text(label), Json.field("all", V.ArrayValue{infoNamesOf(all)}, Json.field("metadata",V.ArrayValue{infoMetadata(all)},Json.field("active", V.ArrayValue{textValues(active)}, Json.field("systemPrompt", Json.text(prompt), Nil{}))))))

def dynamicScenario(+dir: String, agentDir: String, hidden: Bool) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Bool, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(environment => api => dynamicFactory(environment, api)), hidden)
    +harness : Harness <- resourceHarness(dir, agentDir, setup(Nil{}), ref, [inline("dynamic", factory)], noResources())
    reportTools("before_bind", sessionOf(harness))
    Session.bindExtensions(sessionOf(harness), Ext.SessionStartEvent{Ext.StartupStart{}, None{}})
    reportTools("after_bind", sessionOf(harness))
    cleanup(harness)

def bashEnvValue(variables: Shell.Environment(),+name: String) -> String:
  match variables:
    case Nil{}: "<missing>"
    case Shell.Variable{key,value} <> rest: Bool.pick(String,String.eq(key,name),value,bashEnvValue(rest,name))
def bashEnvFields(+variables: Shell.Environment()) -> List<&2,Rec.Property<V.Value>>:
  [Rec.Property{"PI_SESSION_ID",Json.text(bashEnvValue(variables,"PI_SESSION_ID"))},Rec.Property{"PI_SESSION_FILE",Json.text(bashEnvValue(variables,"PI_SESSION_FILE"))},Rec.Property{"PI_PROVIDER",Json.text(bashEnvValue(variables,"PI_PROVIDER"))},Rec.Property{"PI_MODEL",Json.text(bashEnvValue(variables,"PI_MODEL"))},Rec.Property{"PI_REASONING_LEVEL",Json.text(bashEnvValue(variables,"PI_REASONING_LEVEL"))}]
def bashSpawnHook(label: String, context: Bash.BashSpawnContext) -> IO(Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>):
  match context:
    case Bash.BashSpawnContext{command,cwd,+env}:
      do IO<Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>>:
        print("bash_spawn",Rec.Property{"label",Json.text(label)} <> bashEnvFields(env))
        return Done{Bash.BashSpawnContext{command,cwd,env}}
def bashDefinitionName(definition: Ext.ToolDefinition,name: String,label: String) -> Ext.ToolDefinition:
  match definition:
    case Ext.ToolDefinition{_,_,description,snippet,guidelines,parameters,sampling,mode,execute,shell,call,result,prepare}: Ext.ToolDefinition{name,label,description,snippet,guidelines,parameters,sampling,mode,execute,shell,call,result,prepare}
def bashDefinitionExecute(definition: Ext.ToolDefinition) -> Ext.ToolExecute():
  match definition:
    case Ext.ToolDefinition{_,_,_,_,_,_,_,_,execute,_,_,_,_}: execute
def bashFactory(first: Ext.ToolDefinition,second: Ext.ToolDefinition,+api: Ext.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    a : Result<&2,&2,String,Unit> <- Loader.registerTool(api,first)
    b : Result<&2,&2,String,Unit> <- Loader.registerTool(api,second)
    return both(a,b)
type BashFactoryEnv is Data:
  BashFactoryEnv{first: Ext.ToolDefinition, second: Ext.ToolDefinition}
def bashFrom(env: BashFactoryEnv, api: Ext.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>):
  match env:
    case BashFactoryEnv{first, second}: bashFactory(first, second, api)
def activeToolName(tool: Tools.Tool()) -> String:
  match tool: case T.AgentTool{name,_,_,_,_,_,_,_,_}: name
def namedTool(tools: List<&2,Tools.Tool()>,+name: String) -> Maybe<&2,Tools.Tool()>:
  match tools:
    case Nil{}: None{}
    case +tool <> rest: Bool.pick(Maybe<&2,Tools.Tool()>,String.eq(activeToolName(tool),name),Some{tool},namedTool(rest,name))
def activeToolIn(state: Session.AgentState(),name: String) -> Maybe<&2,Tools.Tool()>:
  match state:
    case T.AgentState{_,_,tools,_,_,_,_,_}: namedTool(tools,name)
def activeBash(session: Session.AgentSession,name: String) -> IO(Maybe<&2,Tools.Tool()>):
  do IO<Maybe<&2,Tools.Tool()>>:
    state : Session.AgentState() <- Session.state(session)
    return activeToolIn(state,name)
def reportBashResult(name: String,result: Tools.Output()) -> IO(Unit):
  match result:
    case Done{_}: print("bash_result",Json.field("name",Json.text(name),Json.field("ok",V.Boolean{True{}},Nil{})))
    case Fail{error}: print("bash_result",Json.field("name",Json.text(name),Json.field("error",Json.text(Tools.errorMessage(error)),Nil{})))
def prefersJsonSchema(sampling: Maybe<&2,Ai.ToolConstrainedSampling>) -> Bool:
  match sampling:
    case Some{Ai.SamplingConfigured{Ai.JsonSchemaSampling{Ai.Prefer{}}}}: True{}
    case _: False{}
def bashResult(+name: String,tool: Maybe<&2,Tools.Tool()>) -> IO(Unit):
  match tool:
    case None{}: print("bash_result",Json.field("name",Json.text(name),Json.field("error",Json.text("missing tool"),Nil{})))
    case Some{T.AgentTool{_,_,_,sampling,_,_,execute,_,_}}:
      do IO<Unit>:
        print("bash_sampling",Json.field("name",Json.text(name),Json.field("preferJsonSchema",V.Boolean{prefersJsonSchema(sampling)},Nil{})))
        result : Tools.Output() <- C.call(Tools.Input(),Tools.Output(),execute,T.ToolExecutionInput{"bash-definition",Json.object(Json.field("command",Json.text("printf ok"),Nil{})),None{},None{}})
        reportBashResult(name,result)
def bashDefinitionScenario(+dir: String,agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +firstHook : C.Callback<Bash.BashSpawnContext,Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>> <- C.create(~String,~Bash.BashSpawnContext,~Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>,~bashSpawnHook,"exposed")
    +secondHook : C.Callback<Bash.BashSpawnContext,Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>> <- C.create(~String,~Bash.BashSpawnContext,~Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>,~bashSpawnHook,"hidden")
    +first : Ext.ToolDefinition <- Loader.createBashToolDefinition(dir,Bash.BashToolOptions{None{},None{},None{},None{},Some{firstHook}})
    +second : Ext.ToolDefinition <- Loader.createBashToolDefinition(dir,Bash.BashToolOptions{None{},None{},None{},Some{False{}},Some{secondHook}})
    +firstExec : Ext.ToolExecute() = bashDefinitionExecute(first)
    +secondExec : Ext.ToolExecute() = bashDefinitionExecute(second)
    +ref : R.Ref<Maybe<&2,Session.AgentSession>> <- R.new(Maybe<&2,Session.AgentSession>,None{})
    +factory : Ext.ExtensionFactory() <- C.create(~BashFactoryEnv, ~Ext.ExtensionAPI, ~Result<&2,&2,String,Unit>, ~bashFrom, BashFactoryEnv{first,bashDefinitionName(second,"bash_without_session_env","bash without session env")})
    +harness : Harness <- resourceHarness(dir,agentDir,setup(Nil{}),ref,[inline("bash-hook",factory)],noResources())
    +session : Session.AgentSession = sessionOf(harness)
    +record : Session.Session() <- Session.sessionOf(session)
    print("bash_expected",Json.field("PI_SESSION_ID",Json.text(Sessions.getSessionId(V.Value,Tools.ToolDetails,V.Value,record)),Json.field("PI_SESSION_FILE",Json.text("<missing>"),Json.field("PI_PROVIDER",Json.text("faux"),Json.field("PI_MODEL",Json.text("faux-model"),Json.field("PI_REASONING_LEVEL",Json.text("off"),Nil{}))))))
    firstTool : Maybe<&2,Tools.Tool()> <- activeBash(session,"bash")
    bashResult("bash",firstTool)
    secondTool : Maybe<&2,Tools.Tool()> <- activeBash(session,"bash_without_session_env")
    bashResult("bash_without_session_env",secondTool)
    cleanup(harness)
    C.dispose(Ext.ToolCallInput,Tools.Output(),firstExec)
    C.dispose(Ext.ToolCallInput,Tools.Output(),secondExec)
    C.dispose(Bash.BashSpawnContext,Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>,firstHook)
    C.dispose(Bash.BashSpawnContext,Result<&2,&2,Bash.OperationError,Bash.BashSpawnContext>,secondHook)

# #2753: reload applies prompt settings changed after startup. The harness
# builds its loadout without discovery, so a first reload loads the
# discovered templates as startup does.
def templateNames(templates: List<&2, Templates.PromptTemplate>) -> List<&2, V.Value>:
  match templates:
    case Nil{}: Nil{}
    case Templates.PromptTemplate{name, _, _, _, _, _} <> rest: Json.text(name) <> templateNames(rest)

def reportTemplates(+label: String, +session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    templates : List<&2, Templates.PromptTemplate> <- Session.promptTemplates(session)
    print("templates", Json.field("label", Json.text(label), Json.field("names", V.ArrayValue{templateNames(templates)}, Nil{})))

def reloadSettingsScenario(+dir: String, +agentDir: String) -> IO(Unit):
  do IO<Unit>:
    written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(agentDir ++ "/prompts/test.md", "Echo test prompt\n")
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : Harness <- resourceHarness(dir, agentDir, setup(Nil{}), ref, Nil{}, DiscoveredPrompts{})
    first : Result<&2, &2, String, Unit> <- Session.reload(sessionOf(harness), None{})
    H.reportOutcome("reload", first)
    reportTemplates("startup", sessionOf(harness))
    changed : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(agentDir ++ "/settings.json", "{\n  \"prompts\": [\n    \"-prompts/test.md\"\n  ]\n}\n")
    second : Result<&2, &2, String, Unit> <- Session.reload(sessionOf(harness), None{})
    H.reportOutcome("reload", second)
    reportTemplates("reloaded", sessionOf(harness))
    cleanup(harness)

# compaction-extensions.test.ts over the faux provider (upstream runs it
# live): an extension records session_before_compact (its preparation and
# branch) and session_compact, and cancels, supplies a compaction (with the
# preparation's or its own tokensBefore) or throws.
type CompactMode is Data:
  CompactMode{label: String, mode: String}

def compactEntryFields(entry: S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>) -> List<&2, Rec.Property<V.Value>>:
  match entry:
    case S.Compaction{S.CompactionEntry{_, summary, _, tokens, _, _, _, _}}: Json.field("entryType", Json.text("compaction"), Json.field("summary", Json.text(summary), Json.field("tokensBefore", V.Number{U32.to_f64(U32.from_nat(tokens))}, Nil{})))
    case _: Json.field("entryType", Json.text("other"), Nil{})

def preparationShape(preparation: Compaction.CompactionPreparation<V.Value, Tools.ToolDetails, V.Value>, branch: Nat) -> List<&2, Rec.Property<V.Value>>:
  match preparation:
    case Compaction.CompactionPreparation{firstKept, summarize, prefix, split, tokens, _, _, _}:
      Json.field("firstKeptEntryId", Json.text(firstKept), Json.field("messagesToSummarize", V.Number{U32.to_f64(U32.from_nat(List.length(&2, Session.Message(), summarize)))}, Json.field("turnPrefixMessages", V.Number{U32.to_f64(U32.from_nat(List.length(&2, Session.Message(), prefix)))}, Json.field("isSplitTurn", V.Boolean{split}, Json.field("tokensBefore", V.Number{tokens}, Json.field("branchEntries", V.Number{U32.to_f64(U32.from_nat(branch))}, Nil{}))))))

def withTokens(result: Compaction.CompactionResult, +tokens: F64) -> Compaction.CompactionResult:
  match result:
    case Compaction.CompactionResult{summary, kept, _, after, usage, details}: Compaction.CompactionResult{summary, kept, tokens, after, usage, details}

def beforeCompactReply(+mode: String, preparation: Compaction.CompactionPreparation<V.Value, Tools.ToolDetails, V.Value>) -> Handled(Ext.SessionBeforeCompactResult):
  match mode:
    case "cancel": Done{Some{Ext.SessionBeforeCompactResult{Some{True{}}, None{}}}}
    case "supply": Done{Some{Ext.SessionBeforeCompactResult{None{}, Some{suppliedCompaction(preparation, "Custom summary from extension")}}}}
    case "supply999": Done{Some{Ext.SessionBeforeCompactResult{None{}, Some{withTokens(suppliedCompaction(preparation, "Custom summary with modified values"), U32.to_f64(999))}}}}
    case "throw": Fail{"Extension intentionally throws"}
    case _: Done{None{}}

def beforeCompactRecorded(env: CompactMode, call: Ext.HandlerCall<Ext.SessionBeforeCompactEvent>) -> IO(Handled(Ext.SessionBeforeCompactResult)):
  match env call:
    case CompactMode{label, mode} Ext.HandlerCall{Ext.SessionBeforeCompactEvent{+preparation, branch, _, _, _, _}, _}:
      do IO<Handled(Ext.SessionBeforeCompactResult)>:
        print("before_compact", Json.field("extension", Json.text(label), preparationShape(preparation, List.length(&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>, branch))))
        return beforeCompactReply(mode, preparation)

def compactRecorded(label: String, call: Ext.HandlerCall<Ext.SessionCompactEvent>) -> IO(Handled(Unit)):
  match call:
    case Ext.HandlerCall{Ext.SessionCompactEvent{entry, fromExtension, _, _}, _}:
      do IO<Handled(Unit)>:
        print("compact", Json.field("extension", Json.text(label), Json.field("fromExtension", V.Boolean{fromExtension}, compactEntryFields(entry))))
        return Done{None{}}

def compactFactory(+label: String, mode: String, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    before : Ext.ExtensionHandler(Ext.SessionBeforeCompactEvent, Ext.SessionBeforeCompactResult) <- C.create(~CompactMode, ~Ext.HandlerCall<Ext.SessionBeforeCompactEvent>, ~Handled(Ext.SessionBeforeCompactResult), ~beforeCompactRecorded, CompactMode{label, mode})
    after : Ext.ExtensionHandler(Ext.SessionCompactEvent, Unit) <- C.create(~String, ~Ext.HandlerCall<Ext.SessionCompactEvent>, ~Handled(Unit), ~compactRecorded, label)
    first : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnSessionBeforeCompact{before})
    second : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnSessionCompact{after})
    return both(first, second)

def compactFrom(spec: CompactMode, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match spec:
    case CompactMode{label, mode}: compactFactory(label, mode, api)

def compactExtensions(+mode: String) -> IO(List<&2, Ext.InlineExtension>):
  match mode:
    case "ordered":
      do IO<List<&2, Ext.InlineExtension>>:
        first : Ext.ExtensionFactory() <- C.create(~CompactMode, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~compactFrom, CompactMode{"extension1", "none"})
        second : Ext.ExtensionFactory() <- C.create(~CompactMode, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~compactFrom, CompactMode{"extension2", "none"})
        return [inline("extension1", first), inline("extension2", second)]
    case other:
      do IO<List<&2, Ext.InlineExtension>>:
        +factory : Ext.ExtensionFactory() <- C.create(~CompactMode, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~compactFrom, CompactMode{"test-extension", other})
        return [inline("test-extension", factory)]

def compactionExtensionsScenario(+dir: String, agentDir: String, +mode: String, +prompts: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    extensions : List<&2, Ext.InlineExtension> <- compactExtensions(mode)
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Text{"4"}, Reg.Text{"6"}, Reg.Text{"history summary"}, Reg.Text{"prefix summary"}]), ref, extensions, noResources())
    prompted(sessionOf(harness), "What is 2+2? Reply with just the number.")
    Bool.pick(Unit -> IO(Unit), String.eq(prompts, "two"), _ => prompted(sessionOf(harness), "What is 3+3? Reply with just the number."), _ => IO.pure(Unit, Unit{}))(Unit{})
    result : Result<&2, &2, String, Compaction.CompactionResult> <- Session.compact(sessionOf(harness), None{})
    H.reportCompact(result)
    reportEntries("entries", sessionOf(harness))
    cleanup(harness)

# trigger-compact-extension.test.ts: the example in a session whose turns
# report 110k, 120k, 95k and 105k context tokens (message_end usage); only the
# last turn crosses the threshold and compacts through ctx.compact.
def assistantMessage(message: Session.Message()) -> Bool: Maybe.is_some(&2, Session.Message(), withUsage(0, message))

def usageApplied(totals: R.Ref<List<&2, U32>>, remaining: List<&2, U32>, message: Session.Message()) -> IO(Handled(Ext.MessageEndEventResult)):
  match remaining:
    case Nil{}: IO.pure(Handled(Ext.MessageEndEventResult), Done{None{}})
    case total <> rest:
      do IO<Handled(Ext.MessageEndEventResult)>:
        R.write(List<&2, U32>, totals, rest)
        return Done{Some{Ext.MessageEndEventResult{withUsage(total, message)}}}

# Each assistant message takes the next total.
def usageStep(totals: R.Ref<List<&2, U32>>, remaining: List<&2, U32>, +message: Session.Message()) -> IO(Handled(Ext.MessageEndEventResult)):
  Bool.pick(Unit -> IO(Handled(Ext.MessageEndEventResult)), assistantMessage(message), _ => usageApplied(totals, remaining, message), _ => IO.pure(Handled(Ext.MessageEndEventResult), Done{None{}}))(Unit{})

def nextUsageWith(+totals: R.Ref<List<&2, U32>>, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)):
  match call:
    case Ext.HandlerCall{Ext.MessageEndEvent{message}, _}:
      do IO<Handled(Ext.MessageEndEventResult)>:
        remaining : List<&2, U32> <- R.read(List<&2, U32>, totals)
        usageStep(totals, remaining, message)

def nextUsage(totals: R.Ref<List<&2, U32>>, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)): nextUsageWith(totals, call)

def usageTokensJson(usage: Maybe<&2, Ctx.ContextUsage>) -> V.Value:
  match usage:
    case Some{Ctx.ContextUsage{Some{tokens}, _, _}}: V.Number{tokens}
    case _: V.Null{}

def turnUsage(unit: Unit, call: Ext.HandlerCall<Ext.TurnEndEvent>) -> IO(Handled(Ext.BoundaryResult)):
  match call:
    case Ext.HandlerCall{_, ctx}:
      do IO<Handled(Ext.BoundaryResult)>:
        usage : Maybe<&2, Ctx.ContextUsage> <- Ctx.getContextUsage(ctx)
        print("turn_usage", Json.field("tokens", usageTokensJson(usage), Nil{}))
        return Done{None{}}

def compactSeen(done: Chan(Unit), call: Ext.HandlerCall<Ext.SessionCompactEvent>) -> IO(Handled(Unit)):
  match call:
    case Ext.HandlerCall{Ext.SessionCompactEvent{entry, fromExtension, _, _}, _}:
      do IO<Handled(Unit)>:
        print("compact", Json.field("fromExtension", V.Boolean{fromExtension}, compactEntryFields(entry)))
        sent : Bool <- Chan.send(Unit, done, Unit{})
        return Done{None{}}

def compactFailedSeen(done: Chan(Unit), call: Ext.HandlerCall<Ext.SessionCompactFailedEvent>) -> IO(Handled(Unit)):
  match call:
    case Ext.HandlerCall{Ext.SessionCompactFailedEvent{_, message, _, _, _}, _}:
      do IO<Handled(Unit)>:
        print("compact_failed", Json.field("errorMessage", Maybe.default(&2, V.Value, Maybe.map(&2, String, V.Value, Json.text, message), V.Null{}), Nil{}))
        sent : Bool <- Chan.send(Unit, done, Unit{})
        return Done{None{}}

def usageObserver(totals: R.Ref<List<&2, U32>>, +done: Chan(Unit), +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    ending : Ext.ExtensionHandler(Ext.MessageEndEvent, Ext.MessageEndEventResult) <- C.create(~R.Ref<List<&2, U32>>, ~Ext.HandlerCall<Ext.MessageEndEvent>, ~Handled(Ext.MessageEndEventResult), ~nextUsage, totals)
    turns : Ext.ExtensionHandler(Ext.TurnEndEvent, Ext.BoundaryResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.TurnEndEvent>, ~Handled(Ext.BoundaryResult), ~turnUsage, Unit{})
    compacted : Ext.ExtensionHandler(Ext.SessionCompactEvent, Unit) <- C.create(~Chan(Unit), ~Ext.HandlerCall<Ext.SessionCompactEvent>, ~Handled(Unit), ~compactSeen, done)
    failed : Ext.ExtensionHandler(Ext.SessionCompactFailedEvent, Unit) <- C.create(~Chan(Unit), ~Ext.HandlerCall<Ext.SessionCompactFailedEvent>, ~Handled(Unit), ~compactFailedSeen, done)
    first : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnMessageEnd{ending})
    second : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnTurnEnd{turns})
    third : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnSessionCompact{compacted})
    fourth : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnSessionCompactFailed{failed})
    return both(first, both(second, both(third, fourth)))

type UsageEnv is Data:
  UsageEnv{totals: R.Ref<List<&2, U32>>, done: Chan(Unit)}

def usageFrom(env: UsageEnv, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match env:
    case UsageEnv{totals, done}: usageObserver(totals, done, api)

def triggerCompactScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +totals : R.Ref<List<&2, U32>> <- R.new(List<&2, U32>, [110000, 120000, 95000, 105000])
    +done : Chan(Unit) <- Chan.new(Unit, 1)
    trigger : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => TriggerCompact.triggerCompact(api)), Unit{})
    observer : Ext.ExtensionFactory() <- C.create(~UsageEnv, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~usageFrom, UsageEnv{totals, done})
    +harness : Harness <- resourceHarness(dir, agentDir, setup([Reg.Text{"one"}, Reg.Text{"two"}, Reg.Text{"three"}, Reg.Text{"four"}, Reg.Text{"compacted summary"}, Reg.Text{"turn prefix"}]), ref, [inline("trigger-compact", trigger), inline("observer", observer)], noResources())
    prompted(sessionOf(harness), "first")
    prompted(sessionOf(harness), "second")
    prompted(sessionOf(harness), "third")
    print("prompts_done", Nil{})
    prompted(sessionOf(harness), "fourth")
    compacted : Maybe<&1, Unit> <- Chan.recv(Unit, done)
    Session.waitForIdle(sessionOf(harness))
    reportEntries("entries", sessionOf(harness))
    cleanup(harness)

# branch-summary-extensions.test.ts: session_before_tree supplies the
# summary with usage; the entry and the session totals carry it.
def tenths(+count: U32) -> F64: F.divide(U32.to_f64(count), U32.to_f64(10))

def extensionSummaryUsage() -> Ai.Usage:
  Ai.Usage{U32.to_f64(10), U32.to_f64(20), U32.to_f64(30), U32.to_f64(40), None{}, None{}, U32.to_f64(100), Ai.UsageCost{tenths(1), tenths(2), tenths(3), tenths(4), U32.to_f64(1)}}

def supplySummary(env: Unit, call: Ext.HandlerCall<Ext.SessionBeforeTreeEvent>) -> IO(Handled(Ext.SessionBeforeTreeResult)):
  IO.pure(Handled(Ext.SessionBeforeTreeResult), Done{Some{Ext.SessionBeforeTreeResult{None{}, Some{Ext.BranchSummaryOverride{"Summary provided by extension", None{}, Some{extensionSummaryUsage()}}}, None{}, None{}, None{}}}})

def summaryFactory(api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.ExtensionHandler(Ext.SessionBeforeTreeEvent, Ext.SessionBeforeTreeResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.SessionBeforeTreeEvent>, ~Handled(Ext.SessionBeforeTreeResult), ~supplySummary, Unit{})
    subscribe(api, Ext.OnSessionBeforeTree{handler})

def usageJson(usage: Maybe<&2, Ai.Usage>) -> V.Value:
  match usage:
    case None{}: V.Null{}
    case Some{Ai.Usage{input, output, read, write, _, _, total, Ai.UsageCost{ci, co, cr, cw, ct}}}: Json.object(Json.field("input", V.Number{input}, Json.field("output", V.Number{output}, Json.field("cacheRead", V.Number{read}, Json.field("cacheWrite", V.Number{write}, Json.field("totalTokens", V.Number{total}, Json.field("cost", Json.object(Json.field("input", V.Number{ci}, Json.field("output", V.Number{co}, Json.field("cacheRead", V.Number{cr}, Json.field("cacheWrite", V.Number{cw}, Json.field("total", V.Number{ct}, Nil{})))))), Nil{})))))))

def summaryEntryJson(result: Result<&2, &2, String, Session.TreeNavigation>) -> V.Value:
  match result:
    case Done{Session.TreeNavigated{_, _, Some{S.BranchSummaryEntry{S.SessionEntryBase{_, parent, _}, fromId, summary, _, usage, fromHook}}}}:
      Json.object(Json.field("type", Json.text("branch_summary"), Json.field("parentId", Maybe.default(&2, V.Value, Maybe.map(&2, String, V.Value, Json.text, parent), V.Null{}), Json.field("fromId", Json.text(fromId), Json.field("fromHook", Maybe.default(&2, V.Value, Maybe.map(&2, Bool, V.Value, flag => V.Boolean{flag}, fromHook), V.Null{}), Json.field("summary", Json.text(summary), Json.field("usage", usageJson(usage), Nil{})))))))
    case _: V.Null{}

def totalsJson(stats: Result<&2, &2, S.Error, Stats.Stats>) -> V.Value:
  match stats:
    case Done{Stats.Stats{_, _, Stats.Totals{_, _, _, _, _, input, output, read, write, cost}, _}}: Json.object(Json.field("input", V.Number{input}, Json.field("output", V.Number{output}, Json.field("cacheRead", V.Number{read}, Json.field("cacheWrite", V.Number{write}, Json.field("cost", V.Number{cost}, Nil{}))))))
    case Fail{_}: V.Null{}

def branchSummaryExtensionScenario(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => summaryFactory(api)), Unit{})
    +harness : Harness <- createHarnessFull(dir, agentDir, Builtins{}, setup(Nil{}), ref, [inline("summary", factory)], [Reg.userMsg("first branch"), Reg.assistantAt("first reply", Ai.Stop{}, Reg.totalUsage(1, 1), Reg.zero()), Reg.userMsg("abandoned branch work"), Reg.assistantAt("abandoned reply", Ai.Stop{}, Reg.totalUsage(1, 1), Reg.zero())], Nil{})
    +target : String <- firstEntryId(sessionOf(harness))
    source : Maybe<&2, String> <- currentLeaf(sessionOf(harness))
    result : Result<&2, &2, String, Session.TreeNavigation> <- Session.navigateTreeWith(sessionOf(harness), target, Session.NavigateTreeOptions{True{}, None{}, None{}, None{}})
    stats : Result<&2, &2, S.Error, Stats.Stats> <- Session.getSessionStats(sessionOf(harness))
    print("summary_entry", Json.field("sourceId", Maybe.default(&2, V.Value, Maybe.map(&2, String, V.Value, Json.text, source), V.Null{}), Json.field("entry", summaryEntryJson(result), Json.field("totals", totalsJson(stats), Nil{}))))
    cleanup(harness)

# agent-session-model-extension: inspect live options, tool hooks and context.
def printPromptOptions(options: Prompt.BuildSystemPromptOptions) -> IO(Unit):
  match options:
    case Prompt.BuildSystemPromptOptions{_, _, tools, _, _, _, _, _, cwd, _, _}:
      print("prompt_options", Json.field("cwd", Json.text(cwd), Json.field("selectedTools", V.ArrayValue{textValues(Maybe.default(&2, List<&2, String>, tools, Nil{}))}, Nil{})))

def inspectPromptOptions(_: Unit, call: Ext.CommandCall) -> IO(Result<&2, &2, String, Unit>):
  match call:
    case Ext.CommandCall{_, command}:
      do IO<Result<&2, &2, String, Unit>>:
        options : Prompt.BuildSystemPromptOptions <- Ctx.getSystemPromptOptions(Ctx.commandContext(command))
        printPromptOptions(options)
        return Done{Unit{}}

def promptOptionsFactory(_: Unit, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.CommandHandler() <- C.create(~Unit, ~Ext.CommandCall, ~Result<&2, &2, String, Unit>, ~inspectPromptOptions, Unit{})
    Loader.registerCommand(api, "inspect-options", Ext.CommandOptions{Some{"Inspect prompt options"}, None{}, handler})

def livePromptOptions(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~promptOptionsFactory, Unit{})
    +harness : Harness <- resourceHarness(dir, agentDir, setup(Nil{}), ref, [inline("inspect-options", factory)], noResources())
    prompted(sessionOf(harness), "/inspect-options")
    prompted(sessionOf(harness), "/inspect-options")
    Session.setActiveToolsByName(sessionOf(harness), ["read"])
    prompted(sessionOf(harness), "/inspect-options")
    cleanup(harness)

def denyTool(_: Unit, _: Ext.HandlerCall<Ext.ToolCallEvent>) -> IO(Handled(Ext.ToolCallEventResult)):
  IO.pure(Handled(Ext.ToolCallEventResult), Done{Some{Ext.ToolCallEventResult{Some{True{}}, Some{"Blocked by test"}, None{}}}})

def toolUsage(+start: U32, +total: U32) -> Ai.Usage:
  Ai.Usage{F.fromU32(start), F.fromU32(U32.add(start, 1)), F.fromU32(U32.add(start, 2)), F.fromU32(U32.add(start, 3)), None{}, None{}, F.fromU32(total), Ai.UsageCost{F.divide(F.fromU32(start), F.fromU32(10)), F.divide(F.fromU32(U32.add(start, 1)), F.fromU32(10)), F.divide(F.fromU32(U32.add(start, 2)), F.fromU32(10)), F.divide(F.fromU32(U32.add(start, 3)), F.fromU32(10)), F.divide(F.fromU32(total), F.fromU32(10))}}

def patchResult(_: Unit, call: Ext.HandlerCall<Ext.ToolResultEvent>) -> IO(Handled(Ext.ToolResultEventResult)):
  match call:
    case Ext.HandlerCall{Ext.ToolResultEvent{_, _, _, _, _, _, usage}, _}:
      do IO<Handled(Ext.ToolResultEventResult)>:
        print("observed_tool_usage", Json.field("usage", usageJson(usage), Nil{}))
        return Done{Some{Ext.ToolResultEventResult{Some{[Ai.TextImageText{Ai.TextContent{"patched result", None{}}}]}, Some{Tools.RawDetails{Json.object(Json.field("patched", Json.boolean(True{}), Nil{}))}}, None{}, Some{toolUsage(5, 26)}}}}

def rewrittenUsers(messages: List<&2, Session.Message()>) -> List<&2, Session.Message()>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{Ai.User{Ai.UserMessage{_, timestamp}}} <> rest: T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{[Ai.TextImageText{Ai.TextContent{"rewritten", None{}}}]}, timestamp}}} <> rewrittenUsers(rest)
    case message <> rest: message <> rewrittenUsers(rest)

def rewriteContext(_: Unit, call: Ext.HandlerCall<Ext.ContextEvent>) -> IO(Handled(Ext.ContextEventResult)):
  match call:
    case Ext.HandlerCall{Ext.ContextEvent{messages}, _}: IO.pure(Handled(Ext.ContextEventResult), Done{Some{Ext.ContextEventResult{Some{rewrittenUsers(messages)}}}})

type ModelHook is Data:
  BlockTool{}
  PatchToolResult{}
  RewriteUserContext{}

def modelHookFactory(kind: ModelHook, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match kind:
    case BlockTool{}:
      do IO<Result<&2, &2, String, Unit>>:
        handler : Ext.ExtensionHandler(Ext.ToolCallEvent, Ext.ToolCallEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ToolCallEvent>, ~Handled(Ext.ToolCallEventResult), ~denyTool, Unit{})
        subscribe(api, Ext.OnToolCall{handler})
    case PatchToolResult{}:
      do IO<Result<&2, &2, String, Unit>>:
        handler : Ext.ExtensionHandler(Ext.ToolResultEvent, Ext.ToolResultEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ToolResultEvent>, ~Handled(Ext.ToolResultEventResult), ~patchResult, Unit{})
        subscribe(api, Ext.OnToolResult{handler})
    case RewriteUserContext{}:
      do IO<Result<&2, &2, String, Unit>>:
        handler : Ext.ExtensionHandler(Ext.ContextEvent, Ext.ContextEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ContextEvent>, ~Handled(Ext.ContextEventResult), ~rewriteContext, Unit{})
        subscribe(api, Ext.OnContext{handler})

def hookTools(kind: ModelHook) -> Tooling:
  match kind:
    case BlockTool{}: Scripted{[ToolSpec{"echo", Throws{"tool should have been blocked"}}]}
    case PatchToolResult{}: Scripted{[ToolSpec{"echo", UsageEcho{toolUsage(1, 10)}}]}
    case RewriteUserContext{}: Builtins{}

def hookReplies(kind: ModelHook) -> Reg.Setup:
  match kind:
    case RewriteUserContext{}: setup([Reg.Text{"done"}])
    case _: setup([echoCall("call_echo", "hello"), Reg.LastToolResult{}])

def modelHooks(+dir: String, agentDir: String, +kind: ModelHook) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~ModelHook, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~modelHookFactory, kind)
    +harness : Harness <- createHarnessWith(dir, agentDir, hookTools(kind), hookReplies(kind), ref, [inline("model-hooks", factory)])
    prompted(sessionOf(harness), "original")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

def promptScenario(+dir: String, agentDir: String, +name: String) -> IO(Unit):
  match name:
    case "tool_turn": promptToolTurn(dir, agentDir)
    case "multiple_tools": promptMultipleTools(dir, agentDir)
    case "image": promptImage(dir, agentDir)
    case "skill": promptSkill(dir, agentDir)
    case "template": promptTemplate(dir, agentDir, False{})
    case "send_user_template": promptTemplate(dir, agentDir, True{})
    case "command": promptCommand(dir, agentDir)
    case "extension_send_command": extensionSendCommand(dir, agentDir)
    case "send_user_idle": sendUserIdle(dir, agentDir)
    case "during_compaction": promptDuringCompaction(dir, agentDir)
    case "input_idle": inputIdle(dir, agentDir)
    case "input_streaming": inputStreaming(dir, agentDir)
    case "input_transform": inputTransform(dir, agentDir)
    case "live_prompt_options": livePromptOptions(dir, agentDir)
    case "model_tool_block": modelHooks(dir, agentDir, BlockTool{})
    case "model_tool_result": modelHooks(dir, agentDir, PatchToolResult{})
    case "model_context_rewrite": modelHooks(dir, agentDir, RewriteUserContext{})
    case "before_start_inject": beforeStartInject(dir, agentDir)
    case "plan_section": planSectionScenario(dir, agentDir)
    case "switch_tools": switchScenario(dir, agentDir, "plain")
    case "dynamic_tool": dynamicScenario(dir, agentDir, False{})
    case "hidden_tool": dynamicScenario(dir, agentDir, True{})
    case "bash_definition": bashDefinitionScenario(dir, agentDir)
    case "switch_tools_override": switchScenario(dir, agentDir, "override")
    case _: IO.die(Unit, 1, "unknown prompt scenario")

# suite/agent-session-queue.test.ts: block the wait tool so delivery boundaries
# are observed without timing assumptions. Queue mode laws cover selection;
# these cases cover its integration with input, extension and session events.
def queueSource(source: Ext.InputSource) -> String:
  match source:
    case Ext.RpcSource{}: "rpc"
    case Ext.InteractiveSource{}: "interactive"
    case _: "extension"

def queueInput(env: Unit, call: Ext.HandlerCall<Ext.InputEvent>) -> IO(Handled(Ext.InputEventResult)):
  match call:
    case Ext.HandlerCall{Ext.InputEvent{+text, _, source, behavior}, _}:
      do IO<Handled(Ext.InputEventResult)>:
        print("input", Json.field("text", Json.text(text), Json.field("source", Json.text(queueSource(source)), Json.field("streamingBehavior", deliveryName(behavior), Nil{}))))
        return Done{Some{Bool.pick(Ext.InputEventResult, String.starts_with(text, "handle"), Ext.InputHandled{}, Ext.InputTransform{"transformed: " ++ text, None{}})}}

def queueFactory(apiRef: R.Ref<Maybe<&2, Ext.ExtensionAPI>>, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    registered : Result<&2, &2, String, Unit> <- testCommandFactory(apiRef, api)
    handler : Ext.ExtensionHandler(Ext.InputEvent, Ext.InputEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.InputEvent>, ~Handled(Ext.InputEventResult), ~queueInput, Unit{})
    subscribe(api, Ext.OnInput{handler})

def observeQueueInput(env: Unit, call: Ext.HandlerCall<Ext.InputEvent>) -> IO(Handled(Ext.InputEventResult)):
  match call:
    case Ext.HandlerCall{Ext.InputEvent{text, _, source, behavior}, _}:
      do IO<Handled(Ext.InputEventResult)>:
        print("input", Json.field("text", Json.text(text), Json.field("source", Json.text(queueSource(source)), Json.field("streamingBehavior", deliveryName(behavior), Nil{}))))
        return Done{None{}}

def sourceFactory(apiRef: R.Ref<Maybe<&2, Ext.ExtensionAPI>>, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    registered : Result<&2, &2, String, Unit> <- testCommandFactory(apiRef, api)
    handler : Ext.ExtensionHandler(Ext.InputEvent, Ext.InputEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.InputEvent>, ~Handled(Ext.InputEventResult), ~observeQueueInput, Unit{})
    subscribe(api, Ext.OnInput{handler})

def queueScenarioFactory(+name: String, apiRef: R.Ref<Maybe<&2, Ext.ExtensionAPI>>) -> IO(Ext.ExtensionFactory()):
  match name:
    case "input": C.create(~R.Ref<Maybe<&2, Ext.ExtensionAPI>>, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(ref => api => queueFactory(ref, api)), apiRef)
    case "extension-steer": C.create(~R.Ref<Maybe<&2, Ext.ExtensionAPI>>, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(ref => api => sourceFactory(ref, api)), apiRef)
    case _: C.create(~R.Ref<Maybe<&2, Ext.ExtensionAPI>>, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(ref => api => testCommandFactory(ref, api)), apiRef)

def reportPending(+session: Session.AgentSession, label: String) -> IO(Unit):
  do IO<Unit>:
    pending : Nat <- Session.pendingMessageCount(session)
    print("pending", Json.field("label", Json.text(label), Json.field("count", Json.natural(pending), Nil{})))

def pendingStarted(session: Session.AgentSession, text: Maybe<&2, String>) -> IO(Unit):
  match text:
    case Some{value}: reportPending(session, value)
    case None{}: IO.pure(Unit, Unit{})

def queueStart(session: Session.AgentSession, event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.AgentEvent{T.MessageStart{message}}: pendingStarted(session, Session.userText(message))
    case _: IO.pure(Unit, Unit{})

def queueDelivery(+session: Session.AgentSession, +behavior: Session.StreamingBehavior, +text: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, Unit> <- Session.queueFrom(session, behavior, text, Nil{}, Ext.RpcSource{})
    H.reportOutcome("queued", result)

def queueExtension(found: Maybe<&2, Ext.ExtensionAPI>, behavior: Ext.UserDelivery, text: String) -> IO(Unit):
  match found:
    case None{}: IO.die(Unit, 1, "queue extension missing")
    case Some{api}:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Loader.sendUserMessage(api, Ai.UserText{text}, Ext.SendUserMessageOptions{Some{behavior}, None{}})
        H.reportOutcome("queued", result)

def queueActions(+session: Session.AgentSession, api: Maybe<&2, Ext.ExtensionAPI>, +name: String, +behavior: Session.StreamingBehavior) -> IO(Unit):
  match name:
    case "input":
      do IO<Unit>:
        queueDelivery(session, Session.Steer{}, "steer me")
        queueDelivery(session, Session.Steer{}, "handle steer")
        queueDelivery(session, Session.FollowUp{}, "follow me")
        queueDelivery(session, Session.FollowUp{}, "handle follow")
    case "reject":
      do IO<Unit>:
        queueDelivery(session, Session.Steer{}, "/testcmd queued")
        queueDelivery(session, Session.FollowUp{}, "/testcmd queued")
    case "extension-steer": queueExtension(api, Ext.UserSteer{}, "steer now")
    case "extension-follow": queueDelivery(session, Session.FollowUp{}, "after current run")
    case "custom-steer":
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(session, Ext.CustomMessageInput{"queue-test", Ai.UserText{"steer custom"}, True{}, Some{Json.object(Json.field("value", Json.natural(1n), Nil{}))}}, Ext.SendMessageOptions{None{}, Some{Ext.DeliverSteer{}}})
        H.reportOutcome("queued", result)
    case "custom-follow":
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(session, Ext.CustomMessageInput{"queue-test", Ai.UserText{"follow-up custom"}, True{}, Some{Json.object(Json.field("value", Json.natural(1n), Nil{}))}}, Ext.SendMessageOptions{None{}, Some{Ext.DeliverFollowUp{}}})
        H.reportOutcome("queued", result)
    case "pending": queueDelivery(session, behavior, "queued")
    case _:
      do IO<Unit>:
        queueDelivery(session, behavior, Bool.pick(String, String.starts_with(name, "mode-steer"), "steer 1", "follow-up 1"))
        queueDelivery(session, behavior, Bool.pick(String, String.starts_with(name, "mode-steer"), "steer 2", "follow-up 2"))

def queueReplies(+name: String, +follow: Bool, all: Bool) -> List<&2, Reg.Reply>:
  +next = Bool.pick(List<&2, Reg.Reply>, all, [Reg.Text{"batched response"}], [Reg.Text{"handled 1"}, Reg.Text{"handled 2"}])
  +replies = Bool.pick(List<&2, Reg.Reply>, String.starts_with(name, "mode-"), next, [Reg.Text{"done"}])
  Reg.Call{"call_wait", "wait", Json.object(Nil{}), "{}"} <> Bool.pick(List<&2, Reg.Reply>, follow || String.eq(name, "input"), Reg.Text{"original turn complete"} <> replies, replies)

def queueScenario(+dir: String, agentDir: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +apiRef : R.Ref<Maybe<&2, Ext.ExtensionAPI>> <- R.new(Maybe<&2, Ext.ExtensionAPI>, None{})
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Unit) <- Chan.new(Unit, 1)
    +follow : Bool = String.starts_with(name, "mode-follow") || String.ends_with(name, "follow")
    +all : Bool = String.ends_with(name, "all")
    +factory : Ext.ExtensionFactory() <- queueScenarioFactory(name, apiRef)
    +harness : Harness <- createHarnessWith(dir, agentDir, Scripted{[ToolSpec{"wait", Gated{started, release}}]}, setup(queueReplies(name, follow, all)), ref, [inline("queue", factory)])
    +session : Session.AgentSession = sessionOf(harness)
    mode : Result<&2, &2, String, Unit> <- Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), follow, _ => Session.setFollowUpMode(session, Bool.pick(T.QueueMode, all, T.All{}, T.OneAtATime{})), _ => Session.setSteeringMode(session, Bool.pick(T.QueueMode, all, T.All{}, T.OneAtATime{})))(Unit{})
    +listener : Session.Listener() <- C.create(~Session.AgentSession, ~Session.AgentSessionEvent, ~Unit, ~queueStart, session)
    Session.subscribe(session, listener)
    IO.spawn(Unit, promptInBackground(session, "start", done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    api : Maybe<&2, Ext.ExtensionAPI> <- R.read(Maybe<&2, Ext.ExtensionAPI>, apiRef)
    queueActions(session, api, name, Bool.pick(Session.StreamingBehavior, follow, Session.FollowUp{}, Session.Steer{}))
    steering : List<&2, String> <- Session.getSteeringMessages(session)
    following : List<&2, String> <- Session.getFollowUpMessages(session)
    H.observe(Unit{}, Session.QueueUpdate{steering, following})
    reportPending(session, "before_release")
    print("release", Nil{})
    sent : Bool <- Chan.send(Unit, release, Unit{})
    finished : Maybe<&1, Unit> <- Chan.recv(Unit, done)
    reportPending(session, "after_run")
    H.reportMessages(session)
    Session.unsubscribe(session, listener)
    C.dispose(Session.AgentSessionEvent, Unit, listener)
    cleanup(harness)
    retired : Maybe<&2, Ext.ExtensionAPI> <- R.dispose(Maybe<&2, Ext.ExtensionAPI>, apiRef)
    Chan.close(Unit, started)
    Chan.close(Unit, release)
    Chan.close(Unit, done)

# nextTurn custom content is not queued as a user message; it is flushed
# between the next prompt and its provider request.
def nextTurnCustom(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Scripted{Nil{}}, setup([Reg.Text{"done"}]))
    sent : Result<&2, &2, String, Unit> <- Session.sendCustomMessage(sessionOf(harness), Ext.CustomMessageInput{"next-turn", Ai.UserText{"carry this"}, True{}, Some{Json.object(Nil{})}}, Ext.SendMessageOptions{None{}, Some{Ext.DeliverNextTurn{}}})
    H.reportOutcome("queued", sent)
    prompted(sessionOf(harness), "normal")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

# agent-session-retry-events: the existing public observer prints each event
# after extension dispatch, so interleaving these markers captures both paths.
def extensionObserved(+kind: String, message: Session.Message()) -> IO(Unit):
  print("extension_event", Json.field("event", Json.text(kind), Json.field("role", Json.text(roleOf(message)), Nil{})))

def observedStart(_: Unit, call: Ext.HandlerCall<Ext.MessageStartEvent>) -> IO(Handled(Unit)):
  match call:
    case Ext.HandlerCall{Ext.MessageStartEvent{message}, _}:
      do IO<Handled(Unit)>:
        extensionObserved("message_start", message)
        return Done{None{}}

def observedEnd(_: Unit, call: Ext.HandlerCall<Ext.MessageEndEvent>) -> IO(Handled(Ext.MessageEndEventResult)):
  match call:
    case Ext.HandlerCall{Ext.MessageEndEvent{message}, _}:
      do IO<Handled(Ext.MessageEndEventResult)>:
        extensionObserved("message_end", message)
        return Done{None{}}

def observedFactory(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    start : Ext.ExtensionHandler(Ext.MessageStartEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.MessageStartEvent>, ~Handled(Unit), ~observedStart, Unit{})
    finish : Ext.ExtensionHandler(Ext.MessageEndEvent, Ext.MessageEndEventResult) <- C.create(~Unit, ~Ext.HandlerCall<Ext.MessageEndEvent>, ~Handled(Ext.MessageEndEventResult), ~observedEnd, Unit{})
    started : Result<&2, &2, String, Unit> <- subscribe(api, Ext.OnMessageStart{start})
    subscribe(api, Ext.OnMessageEnd{finish})

def retryDelayed(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => slowEndFactory(api)), Unit{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup([Reg.Failed{"overloaded_error"}, Reg.Text{"recovered"}]), ref, [inline("slow-retry", factory)])
    prompted(sessionOf(harness), "test")
    H.reportRetrying(sessionOf(harness))
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

def retryTools(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Scripted{[ToolSpec{"echo", Echo{"echo:"}}]}, setup([Reg.Failed{"overloaded_error"}, echoCall("call_echo", "hello"), Reg.Text{"final answer"}, Reg.Text{"follow-up answer"}]))
    prompted(sessionOf(harness), "test")
    H.reportStreaming(sessionOf(harness))
    print("recovered", Nil{})
    prompted(sessionOf(harness), "follow-up")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

def retryNetworkError(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup([Reg.Failed{"Provider finish_reason: network_error"}, Reg.Text{"recovered"}]))
    prompted(sessionOf(harness), "test")
    H.reportRetrying(sessionOf(harness))
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

def observedPrompt(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => observedFactory(api)), Unit{})
    +harness : Harness <- createHarnessWith(dir, agentDir, Builtins{}, setup([Reg.Text{"hello"}]), ref, [inline("observe", factory)])
    prompted(sessionOf(harness), "hi")
    cleanup(harness)

def mixedDeltas(+dir: String, agentDir: String) -> IO(Unit):
  do IO<Unit>:
    +harness : Harness <- createHarness(dir, agentDir, Scripted{[ToolSpec{"echo", Echo{"echo:"}}]}, setup([Reg.Mixed{"plan", "answer", Ai.ToolCall{"call_echo", "echo", Json.object(Json.field("text", Json.text("hello"), Nil{})), None{}, None{}}}, Reg.Text{"done"}]))
    prompted(sessionOf(harness), "hi")
    H.reportMessages(sessionOf(harness))
    cleanup(harness)

def retryEvents(+dir: String, agentDir: String, kind: String) -> IO(Unit):
  match kind:
    case "delayed": retryDelayed(dir, agentDir)
    case "tools": retryTools(dir, agentDir)
    case "network": retryNetworkError(dir, agentDir)
    case "observe": observedPrompt(dir, agentDir)
    case "deltas": mixedDeltas(dir, agentDir)
    case "error":
      do IO<Unit>:
        +harness : Harness <- createHarness(dir, agentDir, Builtins{}, setup([Reg.Failed{"broken"}]))
        prompted(sessionOf(harness), "hi")
        cleanup(harness)
    case _: IO.die(Unit, 1, "unknown retry/event scenario")

def run(args: List<String>) -> IO(Unit):
  match args:
    case "retry_events" <> dir <> agentDir <> kind <> Nil{}: retryEvents(dir, agentDir, kind)
    case "queue" <> dir <> agentDir <> name <> Nil{}: queueScenario(dir, agentDir, name)
    case "next_turn_custom" <> dir <> agentDir <> Nil{}: nextTurnCustom(dir, agentDir)
    case "custom_order" <> dir <> agentDir <> Nil{}: customOrder(dir, agentDir)
    case "bash_recorded" <> dir <> agentDir <> Nil{}: bashRecorded(dir, agentDir)
    case "bash_abort" <> dir <> agentDir <> Nil{}: bashAbort(dir, agentDir)
    case "bash_abort_all" <> dir <> agentDir <> Nil{}: bashAbortAll(dir, agentDir)
    case "aborted_assistant" <> dir <> agentDir <> Nil{}: abortedAssistant(dir, agentDir)
    case "custom_during_tool" <> dir <> agentDir <> second <> Nil{}: customDuringTool(dir, agentDir, second)
    case "message_end_cost" <> dir <> agentDir <> Nil{}: messageEndCost(dir, agentDir)
    case "settled_order" <> dir <> agentDir <> Nil{}: settledOrder(dir, agentDir)
    case "tool_call_settled" <> dir <> agentDir <> Nil{}: toolCallSettled(dir, agentDir)
    case "blocked_terminate" <> dir <> agentDir <> Nil{}: blockedTerminate(dir, agentDir)
    case "preflight_abort" <> dir <> agentDir <> Nil{}: preflightAbort(dir, agentDir)
    case "settled_retry" <> dir <> agentDir <> Nil{}: settledAfterRetry(dir, agentDir)
    case "settled_follow_up" <> dir <> agentDir <> Nil{}: settledAfterFollowUp(dir, agentDir)
    case "command_waits_for_idle" <> dir <> agentDir <> Nil{}: commandWaitsForIdle(dir, agentDir)
    case "tree_cancel_compacting" <> dir <> agentDir <> Nil{}: treeCancelCompacting(dir, agentDir)
    case "tree_waiting" <> dir <> agentDir <> Nil{}: treeWaiting(dir, agentDir)
    case "entry_messages" <> line <> Nil{}: entryMessages(line)
    case "lax_content" <> dir <> agentDir <> kind <> Nil{}: laxContent(dir, agentDir, kind)
    case "queued_slash_follow_up" <> dir <> agentDir <> Nil{}: queuedSlashFollowUp(dir, agentDir)
    case "boundary" <> dir <> agentDir <> name <> argument <> Nil{}: boundaryScenario(dir, agentDir, name, argument)
    case "settle_abort" <> dir <> agentDir <> Nil{}: settleAbort(dir, agentDir)
    case "refresh_notifications" <> dir <> agentDir <> Nil{}: refreshNotifications(dir, agentDir)
    case "retained_usage" <> dir <> agentDir <> Nil{}: retainedUsage(dir, agentDir)
    case "context" <> dir <> agentDir <> name <> Nil{}: contextScenario(dir, agentDir, name)
    case "fork_messages" <> dir <> agentDir <> Nil{}: forkMessagesScenario(dir, agentDir)
    case "prompt" <> dir <> agentDir <> name <> Nil{}: promptScenario(dir, agentDir, name)
    case "branch_summary_extension" <> dir <> agentDir <> Nil{}: branchSummaryExtensionScenario(dir, agentDir)
    case "compaction_extensions" <> dir <> agentDir <> mode <> prompts <> Nil{}: compactionExtensionsScenario(dir, agentDir, mode, prompts)
    case "trigger_compact" <> dir <> agentDir <> Nil{}: triggerCompactScenario(dir, agentDir)
    case "reload_settings" <> dir <> agentDir <> Nil{}: reloadSettingsScenario(dir, agentDir)
    case "before_start_image" <> dir <> agentDir <> image <> Nil{}: beforeStartImage(dir, agentDir, image)
    case "compaction_override" <> dir <> agentDir <> path <> Nil{}: compactionOverride(dir, agentDir, path)
    case "compaction_budget" <> dir <> agentDir <> path <> Nil{}: compactionBudget(dir, agentDir, path)
    case "compaction_model_switch" <> dir <> agentDir <> Nil{}: compactionModelSwitch(dir, agentDir)
    case _: IO.die(Unit, 1, "usage: suite-harness <scenario> <dir> <agentDir> [arguments]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
