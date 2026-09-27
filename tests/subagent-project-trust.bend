import Base
import ../packages/ai/src/utils/message-json.bend as Json
import ../packages/ai/src/types.bend as Ai
import ../packages/agent/src/types.bend as T
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/coding-agent/src/modes/json-event.bend as JsonEvent
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/posix-path.bend as Path
import ../packages/runtime/src/ref.bend as R
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/examples/extensions/subagent/index.bend as Subagent
import ./agent-session.bend as H
import ./regressions.bend as Reg
import ./suite-harness.bend as SH

# Port of pi-mono test/suite/regressions/8261-subagent-project-trust.test.ts:
# the subagent example extension runs in a harness session (upstream
# createHarness({ extensionFactories: [subagentExtension] })) whose project
# has `.pi/agents/project-agent.md`. The session is bound with a TUI UI
# context whose confirm counts its calls and declines; the faux model calls
# `subagent` for the project agent (agentScope "project", a missing cwd) and
# then answers "done". tests/subagent_project_trust_check.py asserts on the
# printed confirmation count and tool result.
#
# Upstream mocks the package's getAgentDir to "/missing-user-agent-dir" and
# parseFrontmatter to fixed fields; the native extension is created over that
# explicit agent directory, and the real frontmatter parser reads the agent
# file, whose frontmatter holds the same fields.

def agentFile() -> String: "---\nname: project-agent\ndescription: Project test agent\n---\n\nHandle the delegated task.\n"

# upstream's confirm mock: vi.fn(async () => options.confirmResult ?? false)
def countConfirm(calls: R.Ref<Nat>, request: Ctx.ConfirmRequest) -> IO(Bool):
  do IO<Bool>:
    R.modify(Nat, Unit, calls, count => (count + 1n, Unit{}))
    return False{}

def noSelection(unit: Unit, request: Ctx.SelectRequest) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, None{})
def noInput(unit: Unit, request: Ctx.InputRequest) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, None{})
def ignoredNotification(unit: Unit, notification: Ctx.Notification) -> IO(Unit): IO.pure(Unit, Unit{})
def ignoredStatus(unit: Unit, update: Ctx.StatusUpdate) -> IO(Unit): IO.pure(Unit, Unit{})
def ignoredCustom(unit: Unit, factory: Ctx.CustomFactory()) -> IO(Unit): IO.pure(Unit, Unit{})
def noEditor(unit: Unit, request: Ctx.EditorRequest) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, None{})
def ignoredWidget(unit: Unit, update: Ctx.WidgetUpdate) -> IO(Unit): IO.pure(Unit, Unit{})
def ignoredText(unit: Unit, text: String) -> IO(Unit): IO.pure(Unit, Unit{})
def emptyEditor(unit: Unit, input: Unit) -> IO(String): IO.pure(String, "")

# upstream `{ confirm } as unknown as ExtensionUIContext`: the other methods
# do nothing (the scenario never calls them).
def confirmUI(calls: R.Ref<Nat>) -> IO(Ctx.ExtensionUIContext):
  do IO<Ctx.ExtensionUIContext>:
    select : C.Callback<Ctx.SelectRequest, Maybe<&2, String>> <- C.create(~Unit, ~Ctx.SelectRequest, ~Maybe<&2, String>, ~noSelection, Unit{})
    confirm : C.Callback<Ctx.ConfirmRequest, Bool> <- C.create(~R.Ref<Nat>, ~Ctx.ConfirmRequest, ~Bool, ~countConfirm, calls)
    input : C.Callback<Ctx.InputRequest, Maybe<&2, String>> <- C.create(~Unit, ~Ctx.InputRequest, ~Maybe<&2, String>, ~noInput, Unit{})
    notify : C.Callback<Ctx.Notification, Unit> <- C.create(~Unit, ~Ctx.Notification, ~Unit, ~ignoredNotification, Unit{})
    status : C.Callback<Ctx.StatusUpdate, Unit> <- C.create(~Unit, ~Ctx.StatusUpdate, ~Unit, ~ignoredStatus, Unit{})
    custom : C.Callback<Ctx.CustomFactory(), Unit> <- C.create(~Unit, ~Ctx.CustomFactory(), ~Unit, ~ignoredCustom, Unit{})
    editor : C.Callback<Ctx.EditorRequest, Maybe<&2, String>> <- C.create(~Unit, ~Ctx.EditorRequest, ~Maybe<&2, String>, ~noEditor, Unit{})
    widget : C.Callback<Ctx.WidgetUpdate, Unit> <- C.create(~Unit, ~Ctx.WidgetUpdate, ~Unit, ~ignoredWidget, Unit{})
    title : C.Callback<String, Unit> <- C.create(~Unit, ~String, ~Unit, ~ignoredText, Unit{})
    text : C.Callback<String, Unit> <- C.create(~Unit, ~String, ~Unit, ~ignoredText, Unit{})
    paste : C.Callback<String, Unit> <- C.create(~Unit, ~String, ~Unit, ~ignoredText, Unit{})
    current : C.Callback<Unit, String> <- C.create(~Unit, ~Unit, ~String, ~emptyEditor, Unit{})
    return Ctx.ExtensionUIContext{select, confirm, input, notify, status, custom, editor, widget, title, text, paste, current, None{}}

# harness.settingsManager.setProjectTrusted(trusted)
def setProjectTrusted(+session: Session.AgentSession, +dir: String, +agentDir: String, +trusted: Bool) -> IO(Unit):
  do IO<Unit>:
    current : Settings.SettingsManager <- Session.getSettings(session)
    next : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.setProjectTrusted(~Settings.FileSettingsStorage, ~Settings.fileWithLock, Settings.fileStorage(dir, agentDir), trusted, current)
    R.write(Settings.SettingsManager, Session.settingsOf(session), H.settingsOf(next))

# harness.session.bindExtensions({ uiContext: { confirm }, mode: "tui" })
def bindUI(runner: Maybe<&2, Runner.ExtensionRunner>, ui: Ctx.ExtensionUIContext) -> IO(Unit):
  match runner:
    case None{}: IO.die(Unit, 1, "the subagent extension did not load")
    case Some{found}: Runner.setUIContext(found, Some{ui}, Ctx.TuiMode{})

def subagentCall(+dir: String) -> Reg.Reply:
  +cwd = Path.join(dir, "missing-cwd")
  Reg.Call{"call_subagent", "subagent", Json.object(Json.field("agent", Json.text("project-agent"), Json.field("task", Json.text("Test project trust"), Json.field("agentScope", Json.text("project"), Json.field("cwd", Json.text(cwd), Nil{}))))), "{\"agent\":\"project-agent\",\"task\":\"Test project trust\",\"agentScope\":\"project\",\"cwd\":" ++ Decode.quote(cwd) ++ "}"}

def failedWrite(result: Result<&2, &2, FS.Error, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{error}: IO.die(Unit, 1, FS.errorMessage(error))

def runProjectAgent(+dir: String, +agentDir: String, +trusted: Bool) -> IO(Unit):
  do IO<Unit>:
    +agentsDir : String = Path.join(Path.join(dir, ".pi"), "agents")
    made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(agentsDir)
    failedWrite(made)
    written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(Path.join(agentsDir, "project-agent.md"), agentFile())
    failedWrite(written)
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : SH.Harness <- SH.createHarnessWith(dir, agentDir, SH.Builtins{}, SH.setup([subagentCall(dir), Reg.Text{"done"}]), ref, [SH.inline("subagent", api => Subagent.subagentExtensionWith("/missing-user-agent-dir", api))])
    setProjectTrusted(SH.sessionOf(harness), dir, agentDir, trusted)
    +calls : R.Ref<Nat> <- R.new(Nat, 0n)
    ui : Ctx.ExtensionUIContext <- confirmUI(calls)
    runner : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(SH.sessionOf(harness))
    bindUI(runner, ui)
    Session.bindExtensions(SH.sessionOf(harness), Ext.SessionStartEvent{Ext.StartupStart{}, None{}})
    SH.prompted(SH.sessionOf(harness), "Delegate this task")
    count : Nat <- R.read(Nat, calls)
    IO.print("{\"type\":\"confirm_calls\",\"count\":" ++ Nat.show(count) ++ "}")
    H.reportMessages(SH.sessionOf(harness))
    SH.cleanup(harness)

# Native supplement: the subagent process
# ---------------------------------------
# Upstream's regression never reaches a subagent process. These scenarios run
# the three modes end to end on the native lanes: the extension spawns the
# running executable (this test binary, as upstream spawns process.execPath),
# which answers `--mode json -p ...` as a fake pi: a non-JSON line, a blank
# line, an unrelated event and, unterminated, one assistant message_end whose
# text echoes its arguments and system prompt. A task containing "fail" writes to
# stderr and exits with code 3.

def argAfter(args: List<&2, String>, +flag: String) -> String:
  match args:
    case Nil{}: ""
    case _ <> Nil{}: ""
    case first <> +second <> rest: Bool.pick(String, String.eq(first, flag), second, argAfter(second <> rest, flag))

def lastArg(args: List<&2, String>) -> String:
  match args:
    case Nil{}: ""
    case last <> Nil{}: last
    case _ <> rest: lastArg(rest)

def promptText(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match result:
    case Fail{_}: "(none)"
    case Done{bytes}: Utf8.decodeBuffer(bytes)

def fakeAssistant(+text: String) -> V.Value:
  JsonEvent.message(T.LlmMessage{Ai.Assistant{Ai.AssistantMessage{[Ai.AssistantText{Ai.TextContent{text, None{}}}], "faux-api", "faux", "sub-faux", None{}, None{}, None{}, None{}, Ai.Usage{U32.to_f64(10), U32.to_f64(5), U32.to_f64(1), U32.to_f64(2), None{}, None{}, U32.to_f64(18), Ai.UsageCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), F64.div(U32.to_f64(1), U32.to_f64(4))}}, Ai.Stop{}, None{}, None{}, None{}, None{}, U32.to_f64(0)}}})

def fakeMessageEnd(+text: String) -> String:
  H.line(Json.object(Json.field("type", Json.text("message_end"), Json.field("message", fakeAssistant(text), Nil{}))))

def fakeOutput(+args: List<&2, String>, +prompt: String, +task: String) -> IO(Unit):
  do IO<Unit>:
    IO.print("starting fake pi")
    IO.print("")
    IO.print("{\"type\":\"agent_start\"}")
    IO.write(fakeMessageEnd("echo " ++ task ++ " | args " ++ String.join(args, " ") ++ " | prompt " ++ prompt))

def fakeRun(+args: List<&2, String>, +prompt: String) -> IO(Unit):
  +task = lastArg(args)
  Bool.pick(Unit -> IO(Unit), String.contains(task, "fail"),
    _ => IO.die(Unit, 3, "boom"),
    _ => fakeOutput(args, prompt, task))(Unit{})

def promptOf(+promptFile: String) -> IO(Result<&2, &2, FS.Error, List<&2, U32>>):
  Bool.pick(Unit -> IO(Result<&2, &2, FS.Error, List<&2, U32>>), String.is_empty(promptFile), _ => IO.pure(Result<&2, &2, FS.Error, List<&2, U32>>, Fail{FS.System{2, "none"}}), _ => FS.readFile(promptFile))(Unit{})

def fakePi(+args: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    content : Result<&2, &2, FS.Error, List<&2, U32>> <- promptOf(argAfter(args, "--append-system-prompt"))
    fakeRun(args, promptText(content))

def workerFile() -> String: "---\nname: worker\ndescription: Worker agent\ntools: read, bash\nmodel: sub-model\n---\n\nYou are the worker.\n"
def plainFile() -> String: "---\nname: plain\ndescription: Plain agent\ntools: [read]\n---\n"

def textItem(+agent: String, +task: String) -> V.Value:
  Json.object(Json.field("agent", Json.text(agent), Json.field("task", Json.text(task), Nil{})))

def runArguments(kind: String) -> V.Value:
  match kind:
    case "single": Json.object(Json.field("agent", Json.text("worker"), Json.field("task", Json.text("hello"), Nil{})))
    case "inherit": Json.object(Json.field("agent", Json.text("plain"), Json.field("task", Json.text("inherit"), Nil{})))
    case "failed": Json.object(Json.field("agent", Json.text("worker"), Json.field("task", Json.text("please fail"), Nil{})))
    case "chain": Json.object(Json.field("chain", V.ArrayValue{[textItem("worker", "first"), textItem("plain", "second after <{previous}>")]}, Nil{}))
    case "parallel": Json.object(Json.field("tasks", V.ArrayValue{[textItem("worker", "one"), textItem("plain", "two"), textItem("nobody", "three"), textItem("worker", "fail four")]}, Nil{}))
    case _: Json.object(Nil{})

def runSubagent(+dir: String, +agentDir: String, +kind: String) -> IO(Unit):
  do IO<Unit>:
    +agentsDir : String = Path.join(agentDir, "agents")
    made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(agentsDir)
    failedWrite(made)
    worker : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(Path.join(agentsDir, "worker.md"), workerFile())
    failedWrite(worker)
    plain : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(Path.join(agentsDir, "plain.md"), plainFile())
    failedWrite(plain)
    +arguments : V.Value = runArguments(kind)
    +ref : R.Ref<Maybe<&2, Session.AgentSession>> <- R.new(Maybe<&2, Session.AgentSession>, None{})
    +harness : SH.Harness <- SH.createHarnessWith(dir, agentDir, SH.Builtins{}, SH.setup([Reg.Call{"call_subagent", "subagent", arguments, H.line(arguments)}, Reg.Text{"done"}]), ref, [SH.inline("subagent", api => Subagent.subagentExtensionWith(agentDir, api))])
    Session.bindExtensions(SH.sessionOf(harness), Ext.SessionStartEvent{Ext.StartupStart{}, None{}})
    SH.prompted(SH.sessionOf(harness), "Delegate this task")
    H.reportMessages(SH.sessionOf(harness))
    SH.cleanup(harness)

def fromArgs(args: List<String>) -> List<&2, String>:
  match args:
    case Nil{}: Nil{}
    case first <> rest: first <> fromArgs(rest)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "trusted" <> dir <> agentDir <> Nil{}: runProjectAgent(dir, agentDir, True{})
    case "untrusted" <> dir <> agentDir <> Nil{}: runProjectAgent(dir, agentDir, False{})
    case "run" <> dir <> agentDir <> kind <> Nil{}: runSubagent(dir, agentDir, kind)
    case "--mode" <> "json" <> rest: fakePi(fromArgs(rest))
    case _: IO.die(Unit, 1, "usage: subagent-project-trust trusted|untrusted <dir> <agentDir>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
