import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/agent/src/agent.bend as AgentCore
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/f64.bend as F
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ../packages/coding-agent/src/core/extensions/types.bend as T
import ../packages/coding-agent/examples/extensions/plan-mode/index.bend as PlanMode
import ./model-runtime-fixture.bend as Fixture

# upstream test/plan-mode-extension.test.ts: the plan-mode example loaded
# into a runner. Upstream calls the factory with a mocked ExtensionAPI and
# context; here the extension registers through the real API, and the
# runner is bound to recording actions: the tool and message actions
# (upstream's vi.fn mocks), a UI whose select and editor answer the test's
# choice and text, whose theme is absent (upstream's identity theme), and a
# session whose entries are empty. Commands run through their registered
# handlers and agent_end through the runner's dispatch.

def check(ok: Bool, +name: String, +detail: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ "\n  " ++ detail))(Unit{})

def Outcome() -> Data: Result<&2, &2, String, Unit>

# What the actions and UI recorded (upstream's mocks).
type Recorded is Data:
  Recorded{activeTools: List<&2, String>, setActiveTools: List<&2, List<&2, String>>, sendMessage: List<&2, T.SendMessage>, sendUserMessage: List<&2, T.SendUserMessage>, appendEntry: List<&2, T.AppendEntry>, selects: Nat}

type Options is Data:
  Options{activeTools: List<&2, String>, selectChoice: Maybe<&2, String>, editorText: Maybe<&2, String>}

def defaults() -> Options: Options{["read", "bash", "edit", "write"], None{}, None{}}

type Env is Data:
  Env{recorded: R.Ref<Recorded>, options: Options}

def recordedOf(env: Env) -> R.Ref<Recorded>:
  match env:
    case Env{recorded, _}: recorded

def activeOf(recorded: Recorded) -> List<&2, String>:
  match recorded:
    case Recorded{active, _, _, _, _, _}: active

def setCallsOf(recorded: Recorded) -> List<&2, List<&2, String>>:
  match recorded:
    case Recorded{_, calls, _, _, _, _}: calls

def sentOf(recorded: Recorded) -> List<&2, T.SendMessage>:
  match recorded:
    case Recorded{_, _, sent, _, _, _}: sent

def sentUserOf(recorded: Recorded) -> List<&2, T.SendUserMessage>:
  match recorded:
    case Recorded{_, _, _, sent, _, _}: sent

def selectsOf(recorded: Recorded) -> Nat:
  match recorded:
    case Recorded{_, _, _, _, _, selects}: selects

# Actions
# -------

def withSent(request: T.SendMessage, recorded: Recorded) -> Recorded & Unit:
  match recorded:
    case Recorded{a, s, sent, u, e, n}: (Recorded{a, s, List.append(&2, T.SendMessage, sent, [request]), u, e, n}, Unit{})

def withSentUser(request: T.SendUserMessage, recorded: Recorded) -> Recorded & Unit:
  match recorded:
    case Recorded{a, s, m, sent, e, n}: (Recorded{a, s, m, List.append(&2, T.SendUserMessage, sent, [request]), e, n}, Unit{})

def withAppended(request: T.AppendEntry, recorded: Recorded) -> Recorded & Unit:
  match recorded:
    case Recorded{a, s, m, u, entries, n}: (Recorded{a, s, m, u, List.append(&2, T.AppendEntry, entries, [request]), n}, Unit{})

def withActive(+names: List<&2, String>, recorded: Recorded) -> Recorded & Unit:
  match recorded:
    case Recorded{_, calls, m, u, e, n}: (Recorded{names, List.append(&2, List<&2, String>, calls, [names]), m, u, e, n}, Unit{})

def withSelect(recorded: Recorded) -> Recorded & Unit:
  match recorded:
    case Recorded{a, s, m, u, e, n}: (Recorded{a, s, m, u, e, n + 1n}, Unit{})

def recordSend(env: Env, request: T.SendMessage) -> IO(Unit):
  R.modify(Recorded, Unit, recordedOf(env), recorded => withSent(request, recorded))

def recordSendUser(env: Env, request: T.SendUserMessage) -> IO(Unit):
  R.modify(Recorded, Unit, recordedOf(env), recorded => withSentUser(request, recorded))

def recordAppend(env: Env, request: T.AppendEntry) -> IO(Unit):
  R.modify(Recorded, Unit, recordedOf(env), recorded => withAppended(request, recorded))

def noModel(env: Env, model: Ai.Model<Ai.JsonValue>) -> IO(Bool): IO.pure(Bool, False{})

def getActive(env: Env, unit: Unit) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    recorded : Recorded <- R.read(Recorded, recordedOf(env))
    return activeOf(recorded)

def noToolInfo(env: Env, unit: Unit) -> IO(List<&2, T.ToolInfo>): IO.pure(List<&2, T.ToolInfo>, Nil{})

def setActive(env: Env, names: List<&2, String>) -> IO(Unit):
  R.modify(Recorded, Unit, recordedOf(env), recorded => withActive(names, recorded))

def noRefresh(env: Env, unit: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def actions(+env: Env) -> IO(T.ExtensionActions):
  do IO<T.ExtensionActions>:
    send : C.Callback<T.SendMessage, Unit> <- C.create(~Env, ~T.SendMessage, ~Unit, ~recordSend, env)
    sendUser : C.Callback<T.SendUserMessage, Unit> <- C.create(~Env, ~T.SendUserMessage, ~Unit, ~recordSendUser, env)
    model : C.Callback<Ai.Model<Ai.JsonValue>, Bool> <- C.create(~Env, ~Ai.Model<Ai.JsonValue>, ~Bool, ~noModel, env)
    active : C.Callback<Unit, List<&2, String>> <- C.create(~Env, ~Unit, ~List<&2, String>, ~getActive, env)
    all : C.Callback<Unit, List<&2, T.ToolInfo>> <- C.create(~Env, ~Unit, ~List<&2, T.ToolInfo>, ~noToolInfo, env)
    set : C.Callback<List<&2, String>, Unit> <- C.create(~Env, ~List<&2, String>, ~Unit, ~setActive, env)
    refresh : C.Callback<Unit, Unit> <- C.create(~Env, ~Unit, ~Unit, ~noRefresh, env)
    append : C.Callback<T.AppendEntry, Unit> <- C.create(~Env, ~T.AppendEntry, ~Unit, ~recordAppend, env)
    return T.ExtensionActions{send, sendUser, model, T.ToolActions{active, all, set, refresh}, append}

# Context (upstream: isIdle false, no pending messages, empty entries)
# ------------------------------------------------------------------

def stateOf(unit: Unit, input: Unit) -> IO(Ctx.SessionState):
  IO.pure(Ctx.SessionState, Ctx.SessionState{None{}, Nil{}, Ai.Off{}, "session", None{}, False{}, True{}, False{}, None{}})

def nothing(unit: Unit, input: Unit) -> IO(Unit): IO.pure(Unit, Unit{})
def noUsage(unit: Unit, input: Unit) -> IO(Maybe<&2, Ctx.ContextUsage>): IO.pure(Maybe<&2, Ctx.ContextUsage>, None{})
def ignoreCompact(unit: Unit, options: Ctx.CompactOptions) -> IO(Unit): Ctx.disposeCompactOptions(options)
def noPrompt(unit: Unit, input: Unit) -> IO(String): IO.pure(String, "")

def requiredSession(result: Sessions.Outcome(Session.Session())) -> IO(Session.Session()):
  match result:
    case Done{session}: IO.pure(Session.Session(), session)
    case Fail{error}: IO.die(Session.Session(), 1, Sessions.message(error))

def emptySession(unit: Unit, input: Unit) -> IO(Ctx.ReadonlySessionManager()):
  do IO<Ctx.ReadonlySessionManager()>:
    ids : Uuid.Generator <- Uuid.generator()
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(ids, "/tmp/pi-plan-mode-test", Sessions.noOptions())
    requiredSession(created)

def contextActions() -> IO(Ctx.ExtensionContextActions):
  do IO<Ctx.ExtensionContextActions>:
    state : C.Callback<Unit, Ctx.SessionState> <- C.create(~Unit, ~Unit, ~Ctx.SessionState, ~stateOf, Unit{})
    abort : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~nothing, Unit{})
    shutdown : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~nothing, Unit{})
    usage : C.Callback<Unit, Maybe<&2, Ctx.ContextUsage>> <- C.create(~Unit, ~Unit, ~Maybe<&2, Ctx.ContextUsage>, ~noUsage, Unit{})
    compact : C.Callback<Ctx.CompactOptions, Unit> <- C.create(~Unit, ~Ctx.CompactOptions, ~Unit, ~ignoreCompact, Unit{})
    prompt : C.Callback<Unit, String> <- C.create(~Unit, ~Unit, ~String, ~noPrompt, Unit{})
    manager : C.Callback<Unit, Ctx.ReadonlySessionManager()> <- C.create(~Unit, ~Unit, ~Ctx.ReadonlySessionManager(), ~emptySession, Unit{})
    return Ctx.ExtensionContextActions{state, abort, shutdown, usage, compact, prompt, manager}

# UI
# --

def choiceOf(env: Env) -> Maybe<&2, String>:
  match env:
    case Env{_, Options{_, choice, _}}: choice

def editorTextOf(env: Env) -> Maybe<&2, String>:
  match env:
    case Env{_, Options{_, _, text}}: text

def selected(env: Env, request: Ctx.SelectRequest) -> IO(Maybe<&2, String>):
  match env:
    case Env{recorded, Options{_, choice, _}}:
      do IO<Maybe<&2, String>>:
        R.modify(Recorded, Unit, recorded, withSelect)
        return choice

def noConfirmation(env: Env, request: Ctx.ConfirmRequest) -> IO(Bool): IO.pure(Bool, False{})
def noInput(env: Env, request: Ctx.InputRequest) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, None{})
def ignoredNotification(env: Env, notification: Ctx.Notification) -> IO(Unit): IO.pure(Unit, Unit{})
def ignoredStatus(env: Env, update: Ctx.StatusUpdate) -> IO(Unit): IO.pure(Unit, Unit{})
def ignoredCustom(env: Env, factory: Ctx.CustomFactory()) -> IO(Unit): IO.pure(Unit, Unit{})
def edited(env: Env, request: Ctx.EditorRequest) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, editorTextOf(env))
def ignoredWidget(env: Env, update: Ctx.WidgetUpdate) -> IO(Unit): IO.pure(Unit, Unit{})
def ignoredText(env: Env, text: String) -> IO(Unit): IO.pure(Unit, Unit{})
def emptyEditor(env: Env, input: Unit) -> IO(String): IO.pure(String, "")

def ui(+env: Env) -> IO(Ctx.ExtensionUIContext):
  do IO<Ctx.ExtensionUIContext>:
    select : C.Callback<Ctx.SelectRequest, Maybe<&2, String>> <- C.create(~Env, ~Ctx.SelectRequest, ~Maybe<&2, String>, ~selected, env)
    confirm : C.Callback<Ctx.ConfirmRequest, Bool> <- C.create(~Env, ~Ctx.ConfirmRequest, ~Bool, ~noConfirmation, env)
    input : C.Callback<Ctx.InputRequest, Maybe<&2, String>> <- C.create(~Env, ~Ctx.InputRequest, ~Maybe<&2, String>, ~noInput, env)
    notify : C.Callback<Ctx.Notification, Unit> <- C.create(~Env, ~Ctx.Notification, ~Unit, ~ignoredNotification, env)
    status : C.Callback<Ctx.StatusUpdate, Unit> <- C.create(~Env, ~Ctx.StatusUpdate, ~Unit, ~ignoredStatus, env)
    custom : C.Callback<Ctx.CustomFactory(), Unit> <- C.create(~Env, ~Ctx.CustomFactory(), ~Unit, ~ignoredCustom, env)
    editor : C.Callback<Ctx.EditorRequest, Maybe<&2, String>> <- C.create(~Env, ~Ctx.EditorRequest, ~Maybe<&2, String>, ~edited, env)
    widget : C.Callback<Ctx.WidgetUpdate, Unit> <- C.create(~Env, ~Ctx.WidgetUpdate, ~Unit, ~ignoredWidget, env)
    title : C.Callback<String, Unit> <- C.create(~Env, ~String, ~Unit, ~ignoredText, env)
    text : C.Callback<String, Unit> <- C.create(~Env, ~String, ~Unit, ~ignoredText, env)
    paste : C.Callback<String, Unit> <- C.create(~Env, ~String, ~Unit, ~ignoredText, env)
    current : C.Callback<Unit, String> <- C.create(~Env, ~Unit, ~String, ~emptyEditor, env)
    return Ctx.ExtensionUIContext{select, confirm, input, notify, status, custom, editor, widget, title, text, paste, current, None{}}

# Setup (upstream setup())
# ------------------------

type Setup is Data:
  Setup{runner: Runner.ExtensionRunner, recorded: R.Ref<Recorded>}

def printedError(unit: Unit, error: T.ExtensionError) -> IO(Unit):
  match error:
    case T.ExtensionError{path, event, message, _}: IO.print("extension error " ++ path ++ " " ++ event ++ ": " ++ message)

def setup(options: Options) -> IO(Setup):
  match options:
    case Options{+active, choice, text}:
      do IO<Setup>:
        +recorded : R.Ref<Recorded> <- R.new(Recorded, Recorded{active, Nil{}, Nil{}, Nil{}, Nil{}, 0n})
        +env : Env = Env{recorded, Options{active, choice, text}}
        +runtime : T.ExtensionRuntime() <- Loader.createExtensionRuntime()
        +factory : T.ExtensionFactory() <- C.create(~Unit, ~T.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => PlanMode.planModeExtension(api)), Unit{})
        errors : List<&2, T.LoadError> <- Loader.loadExtensionFactories(runtime, [T.InlineExtension{"plan-mode", factory, False{}}])
        Loader.disposeInlineExtensions([T.InlineExtension{"plan-mode", factory, False{}}])
        models : Models.ModelRuntime <- Fixture.create(Nil{})
        +runner : Runner.ExtensionRunner <- Runner.create(runtime, "/tmp/pi-plan-mode-test", models)
        bound : T.ExtensionActions <- actions(env)
        Loader.bindActions(runtime, Some{bound})
        context : Ctx.ExtensionContextActions <- contextActions()
        Runner.bindCore(runner, Some{context}, None{})
        dialogs : Ctx.ExtensionUIContext <- ui(env)
        Runner.setUIContext(runner, Some{dialogs}, Ctx.TuiMode{})
        listener : C.Callback<T.ExtensionError, Unit> <- C.create(~Unit, ~T.ExtensionError, ~Unit, ~printedError, Unit{})
        subscription : Runner.ErrorSubscription <- Runner.onError(runner, listener)
        return Setup{runner, recorded}

def runnerOf(setup: Setup) -> Runner.ExtensionRunner:
  match setup:
    case Setup{runner, _}: runner

def recorded(setup: Setup) -> IO(Recorded):
  match setup:
    case Setup{_, value}: R.read(Recorded, value)

def commandSucceeded(+name: String, result: Outcome()) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{error}: IO.die(Unit, 1, "FAIL command " ++ name ++ " failed: " ++ error)

def ranCommand(+name: String, +runner: Runner.ExtensionRunner, command: Maybe<&2, T.ResolvedCommand>) -> IO(Unit):
  match command:
    case None{}: IO.die(Unit, 1, "FAIL Missing command: " ++ name)
    case Some{T.ResolvedCommand{_, _, _, _, _, handler}}:
      IO.bind(Outcome(), Unit, C.call(T.CommandCall, Outcome(), handler, T.CommandCall{"", Runner.createCommandContext(runner)}), result => commandSucceeded(name, result))

def runCommand(+setup: Setup, +name: String) -> IO(Unit):
  do IO<Unit>:
    command : Maybe<&2, T.ResolvedCommand> <- Runner.getCommand(runnerOf(setup), name)
    ranCommand(name, runnerOf(setup), command)

def assistantMessage(text: String) -> T.AgentMessage():
  Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}, "anthropic-messages", "anthropic", "mock", None{}, None{}, None{}, None{}, AgentCore.emptyUsage(), Ai.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(0)}}}

def triggerAgentEnd(+setup: Setup, text: String) -> IO(Unit):
  Runner.emit(runnerOf(setup), T.AgentEnd{T.AgentEndEvent{[assistantMessage(text)]}})

# Assertions
# ----------

def names(values: List<&2, String>) -> String: "[" ++ String.join(values, ",") ++ "]"

def sameNames(left: List<&2, String>, right: List<&2, String>) -> Bool: String.eq(names(left), names(right))

def lastCall(calls: List<&2, List<&2, String>>) -> List<&2, String>:
  match calls:
    case Nil{}: Nil{}
    case [only]: only
    case _ <> rest: lastCall(rest)

def userText(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{text}: text
    case Ai.UserBlocks{_}: "[blocks]"

def deliveryName(options: T.SendUserMessageOptions) -> String:
  match options:
    case T.SendUserMessageOptions{Some{T.UserFollowUp{}}, None{}}: "{deliverAs: followUp}"
    case T.SendUserMessageOptions{Some{T.UserSteer{}}, None{}}: "{deliverAs: steer}"
    case _: "{other}"

def shownUser(calls: List<&2, T.SendUserMessage>) -> String:
  match calls:
    case Nil{}: ""
    case T.SendUserMessage{content, options} <> rest: "(" ++ userText(content) ++ " " ++ deliveryName(options) ++ ")" ++ shownUser(rest)

def optionsName(options: T.SendMessageOptions) -> String:
  match options:
    case T.SendMessageOptions{Some{True{}}, Some{T.DeliverFollowUp{}}}: "{triggerTurn: true, deliverAs: followUp}"
    case T.SendMessageOptions{None{}, Some{T.DeliverFollowUp{}}}: "{deliverAs: followUp}"
    case T.SendMessageOptions{Some{False{}}, None{}}: "{triggerTurn: false}"
    case _: "{other}"

def shownSent(calls: List<&2, T.SendMessage>) -> String:
  match calls:
    case Nil{}: ""
    case T.SendMessage{T.CustomMessageInput{customType, _, _, _}, options} <> rest: "(" ++ customType ++ " " ++ optionsName(options) ++ ")" ++ shownSent(rest)

# upstream expect(sendMessage).toHaveBeenCalledWith(objectContaining({
# customType }), options): some call matches.
def calledWith(calls: List<&2, T.SendMessage>, +customType: String, +options: String) -> Bool:
  match calls:
    case Nil{}: False{}
    case T.SendMessage{T.CustomMessageInput{found, _, _, _}, sent} <> rest: (String.eq(found, customType) && String.eq(optionsName(sent), options)) || calledWith(rest, customType, options)

# Tests
# -----

def preservesCustomActiveTools() -> IO(Unit):
  do IO<Unit>:
    +setup : Setup <- setup(Options{["read", "bash", "edit", "write", "echo_tool"], None{}, None{}})
    runCommand(setup, "plan")
    +first : Recorded <- recorded(setup)
    +planTools : List<&2, String> = ["read", "bash", "echo_tool", "grep", "find", "ls", "questionnaire"]
    runCommand(setup, "plan")
    +second : Recorded <- recorded(setup)
    +normalTools : List<&2, String> = ["read", "bash", "edit", "write", "echo_tool"]
    check(sameNames(activeOf(first), planTools) && sameNames(lastCall(setCallsOf(first)), planTools) && sameNames(activeOf(second), normalTools) && sameNames(lastCall(setCallsOf(second)), normalTools), "preserves custom active tools while toggling plan mode", names(activeOf(first)) ++ " " ++ names(lastCall(setCallsOf(first))) ++ " " ++ names(activeOf(second)) ++ " " ++ names(lastCall(setCallsOf(second))))

def doesNotPromptWithoutPlan() -> IO(Unit):
  do IO<Unit>:
    +setup : Setup <- setup(defaults())
    runCommand(setup, "plan")
    triggerAgentEnd(setup, "This file defines the command-line argument parser.")
    +state : Recorded <- recorded(setup)
    check(Nat.is_eq(selectsOf(state), 0n) && List.is_empty(&2, T.SendMessage, sentOf(state)), "does not prompt when the assistant response contains no plan", Nat.show(selectsOf(state)) ++ " selects, sent " ++ shownSent(sentOf(state)))

def queuesPlanRefinement() -> IO(Unit):
  do IO<Unit>:
    +setup : Setup <- setup(Options{["read", "bash", "edit", "write"], Some{"Refine the plan"}, Some{"Add a regression test."}})
    runCommand(setup, "plan")
    triggerAgentEnd(setup, "Plan:\n1. Inspect the current implementation\n2. Add a regression test")
    +state : Recorded <- recorded(setup)
    +shown : String = shownUser(sentUserOf(state))
    check(String.eq(shown, "(Add a regression test. {deliverAs: followUp})"), "queues plan refinement as a follow-up user message", shown)

def queuesPlanExecution() -> IO(Unit):
  do IO<Unit>:
    +setup : Setup <- setup(Options{["read", "bash", "edit", "write", "echo_tool"], Some{"Execute the plan (track progress)"}, None{}})
    runCommand(setup, "plan")
    triggerAgentEnd(setup, "Plan:\n1. Inspect the current implementation\n2. Add a regression test")
    +state : Recorded <- recorded(setup)
    check(sameNames(activeOf(state), ["read", "bash", "edit", "write", "echo_tool"]) && calledWith(sentOf(state), "plan-mode-execute", "{triggerTurn: true, deliverAs: followUp}"), "queues plan execution as a follow-up custom message", names(activeOf(state)) ++ " " ++ shownSent(sentOf(state)))

def main() -> IO(Unit):
  do IO<Unit>:
    preservesCustomActiveTools()
    doesNotPromptWithoutPlan()
    queuesPlanRefinement()
    queuesPlanExecution()
