import Base
import ../../../src/core/extensions/types.bend as Ext
import ../../../src/core/extensions/context.bend as Ctx
import ../../../src/core/extensions/loader.bend as Loader
import ../../../src/core/session-manager.bend as S
import ../../../src/core/session-persistence.bend as Sessions
import ../../../src/core/messages.bend as Messages
import ../../../src/core/tools/index.bend as Tools
import ../../../src/modes/interactive/theme/theme.bend as Theme
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/utils/message-json.bend as Json
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/record.bend as Rec
import ../../../../runtime/src/ref.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/text.bend as Text
import ./utils.bend as Utils

# pi v0.87.1 examples/extensions/plan-mode/index.ts: read-only exploration.
# /plan (or ctrl+alt+p) toggles plan mode, which swaps the built-in write
# tools for read-only ones and restricts bash to allowlisted commands; the
# numbered steps under a "Plan:" header become a todo list whose [DONE:n]
# markers are tracked while the plan executes. The extension's state lives in
# one reference its handlers share (upstream's closure variables).

# Tools
# -----

def planModeTools() -> List<&2, String>: ["read", "bash", "grep", "find", "ls", "questionnaire"]
def normalModeTools() -> List<&2, String>: ["read", "bash", "edit", "write"]

def containsName(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: String.eq(first, name) || containsName(rest, name)

def planModeDisabled(+name: String) -> Bool: String.eq(name, "edit") || String.eq(name, "write")

def planManaged(+name: String) -> Bool: containsName(List.append(&2, String, planModeTools(), normalModeTools()), name)

def withoutDisabled(names: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case +name <> +rest: Bool.pick(List<&2, String>, planModeDisabled(name), withoutDisabled(rest), name <> withoutDisabled(rest))

def unmanaged(names: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case +name <> +rest: Bool.pick(List<&2, String>, planManaged(name), unmanaged(rest), name <> unmanaged(rest))

# [...new Set(names)]: the first occurrence of each name, in order.
def uniqueToolNames(names: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: seen
    case +name <> rest: uniqueToolNames(rest, Bool.pick(List<&2, String>, containsName(seen, name), seen, List.append(&2, String, seen, [name])))

def getPlanModeTools(active: List<&2, String>) -> List<&2, String>:
  uniqueToolNames(List.append(&2, String, withoutDisabled(active), planModeTools()), Nil{})

def getNormalModeTools(active: List<&2, String>) -> List<&2, String>:
  uniqueToolNames(List.append(&2, String, normalModeTools(), unmanaged(active)), Nil{})

# State
# -----

type PlanModeState is Data:
  PlanModeState{enabled: Bool, executing: Bool, todos: List<&2, Utils.TodoItem>, toolsBeforePlanMode: Maybe<&2, List<&2, String>>}

type PlanMode is Data:
  PlanMode{api: Ext.ExtensionAPI, state: R.Ref<PlanModeState>}

def apiOf(env: PlanMode) -> Ext.ExtensionAPI:
  match env:
    case PlanMode{api, _}: api

def stateOf(env: PlanMode) -> IO(PlanModeState):
  match env:
    case PlanMode{_, state}: R.read(PlanModeState, state)

def writeState(env: PlanMode, next: PlanModeState) -> IO(Unit):
  match env:
    case PlanMode{_, state}: R.write(PlanModeState, state, next)

def enabledOf(state: PlanModeState) -> Bool:
  match state:
    case PlanModeState{enabled, _, _, _}: enabled

def executingOf(state: PlanModeState) -> Bool:
  match state:
    case PlanModeState{_, executing, _, _}: executing

def todosOf(state: PlanModeState) -> List<&2, Utils.TodoItem>:
  match state:
    case PlanModeState{_, _, todos, _}: todos

def beforeOf(state: PlanModeState) -> Maybe<&2, List<&2, String>>:
  match state:
    case PlanModeState{_, _, _, before}: before

def withTodos(state: PlanModeState, todos: List<&2, Utils.TodoItem>) -> PlanModeState:
  match state:
    case PlanModeState{enabled, executing, _, before}: PlanModeState{enabled, executing, todos, before}

def withBefore(state: PlanModeState, before: Maybe<&2, List<&2, String>>) -> PlanModeState:
  match state:
    case PlanModeState{enabled, executing, todos, _}: PlanModeState{enabled, executing, todos, before}

def withEnabled(state: PlanModeState, enabled: Bool) -> PlanModeState:
  match state:
    case PlanModeState{_, executing, todos, before}: PlanModeState{enabled, executing, todos, before}

def withExecuting(state: PlanModeState, executing: Bool) -> PlanModeState:
  match state:
    case PlanModeState{enabled, _, todos, before}: PlanModeState{enabled, executing, todos, before}

def isCompleted(item: Utils.TodoItem) -> Bool:
  match item:
    case Utils.TodoItem{_, _, completed}: completed

def itemText(item: Utils.TodoItem) -> String:
  match item:
    case Utils.TodoItem{_, text, _}: text

def completedCount(items: List<&2, Utils.TodoItem>) -> Nat:
  match items:
    case Nil{}: 0n
    case +item <> +rest: Bool.pick(Nat, isCompleted(item), 1n + completedCount(rest), completedCount(rest))

def allCompleted(items: List<&2, Utils.TodoItem>) -> Bool:
  match items:
    case Nil{}: True{}
    case item <> rest: isCompleted(item) && allCompleted(rest)

def hasTodos(state: PlanModeState) -> Bool: Bool.not(List.is_empty(&2, Utils.TodoItem, todosOf(state)))

# Results
# -------
# Upstream's API calls throw when the runtime is not bound; a failed call
# fails the handler with its message.

def Outcome() -> Data: Result<&2, &2, String, Unit>

def done() -> IO(Outcome()): IO.pure(Outcome(), Done{Unit{}})

def andThen(first: Outcome(), next: Unit -> IO(Outcome())) -> IO(Outcome()):
  match first:
    case Fail{error}: IO.pure(Outcome(), Fail{error})
    case Done{_}: next(Unit{})

def unit(-A: Data, result: Result<&2, &2, String, A>) -> Outcome():
  match result:
    case Fail{error}: Fail{error}
    case Done{_}: Done{Unit{}}

# Status and widget
# -----------------

# upstream theme.fg; without a theme the text stays unstyled.
def fg(theme: Maybe<&2, Theme.Theme>, +key: String, +text: String) -> String:
  match theme:
    case None{}: text
    case Some{found}: Theme.fg(found, key, text)

def todoLine(+theme: Maybe<&2, Theme.Theme>, item: Utils.TodoItem) -> String:
  match item:
    case Utils.TodoItem{_, text, True{}}: fg(theme, "success", "\u{2611} ") ++ fg(theme, "muted", Theme.strikethrough(text))
    case Utils.TodoItem{_, text, False{}}: fg(theme, "muted", "\u{2610} ") ++ text

def todoLines(+theme: Maybe<&2, Theme.Theme>, items: List<&2, Utils.TodoItem>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: todoLine(theme, item) <> todoLines(theme, rest)

def progressText(+theme: Maybe<&2, Theme.Theme>, +todos: List<&2, Utils.TodoItem>) -> String:
  fg(theme, "accent", "\u{1f4cb} " ++ Nat.show(completedCount(todos)) ++ "/" ++ Nat.show(List.length(&2, Utils.TodoItem, todos)))

def statusText(+theme: Maybe<&2, Theme.Theme>, +state: PlanModeState) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, executingOf(state) && hasTodos(state), Some{progressText(theme, todosOf(state))}, Bool.pick(Maybe<&2, String>, enabledOf(state), Some{fg(theme, "warning", "\u{23f8} plan")}, None{}))

def widgetContent(+theme: Maybe<&2, Theme.Theme>, +state: PlanModeState) -> Maybe<&2, Ctx.WidgetContent>:
  Bool.pick(Maybe<&2, Ctx.WidgetContent>, executingOf(state) && hasTodos(state), Some{Ctx.WidgetLines{todoLines(theme, todosOf(state))}}, None{})

def updateStatus(+env: PlanMode, +ctx: Ctx.ExtensionContext) -> IO(Unit):
  do IO<Unit>:
    +state : PlanModeState <- stateOf(env)
    +theme : Maybe<&2, Theme.Theme> <- Ctx.theme(ctx)
    Ctx.setStatus(ctx, "plan-mode", statusText(theme, state))
    Ctx.setWidget(ctx, "plan-todos", widgetContent(theme, state), None{})

# Tool switching
# --------------

def activated(+env: PlanMode, +state: PlanModeState, active: Result<&2, &2, String, List<&2, String>>) -> IO(Outcome()):
  match active:
    case Fail{error}: IO.pure(Outcome(), Fail{error})
    case Done{+names}:
      do IO<Outcome()>:
        writeState(env, withBefore(state, Some{names}))
        Loader.setActiveTools(apiOf(env), getPlanModeTools(names))

def enabledFrom(+env: PlanMode, +state: PlanModeState, before: Maybe<&2, List<&2, String>>) -> IO(Outcome()):
  match before:
    case Some{names}: Loader.setActiveTools(apiOf(env), getPlanModeTools(names))
    case None{}:
      do IO<Outcome()>:
        active : Result<&2, &2, String, List<&2, String>> <- Loader.getActiveTools(apiOf(env))
        activated(env, state, active)

def enablePlanModeTools(+env: PlanMode) -> IO(Outcome()):
  do IO<Outcome()>:
    +state : PlanModeState <- stateOf(env)
    enabledFrom(env, state, beforeOf(state))

def normalTools(+env: PlanMode, before: Maybe<&2, List<&2, String>>) -> IO(Result<&2, &2, String, List<&2, String>>):
  match before:
    case Some{names}: IO.pure(Result<&2, &2, String, List<&2, String>>, Done{names})
    case None{}:
      do IO<Result<&2, &2, String, List<&2, String>>>:
        active : Result<&2, &2, String, List<&2, String>> <- Loader.getActiveTools(apiOf(env))
        return Result.map(&2, &2, String, List<&2, String>, List<&2, String>, getNormalModeTools, active)

def restoredTools(+env: PlanMode, names: Result<&2, &2, String, List<&2, String>>) -> IO(Outcome()):
  match names:
    case Fail{error}: IO.pure(Outcome(), Fail{error})
    case Done{tools}:
      do IO<Outcome()>:
        set : Outcome() <- Loader.setActiveTools(apiOf(env), tools)
        +current : PlanModeState <- stateOf(env)
        writeState(env, withBefore(current, None{}))
        return set

def restoreNormalModeTools(+env: PlanMode) -> IO(Outcome()):
  do IO<Outcome()>:
    +state : PlanModeState <- stateOf(env)
    names : Result<&2, &2, String, List<&2, String>> <- normalTools(env, beforeOf(state))
    restoredTools(env, names)

# Persistence
# -----------

def todoValue(item: Utils.TodoItem) -> V.Value:
  match item:
    case Utils.TodoItem{step, text, completed}: Json.object(Json.field("step", Json.natural(step), Json.field("text", Json.text(text), Json.field("completed", Json.boolean(completed), Nil{}))))

def todoValues(items: List<&2, Utils.TodoItem>) -> List<&2, V.Value>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: todoValue(item) <> todoValues(rest)

def texts(names: List<&2, String>) -> List<&2, V.Value>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: Json.text(name) <> texts(rest)

# upstream PlanModeState as stored: toolsBeforePlanMode is left out while
# undefined (JSON.stringify).
def stateValue(state: PlanModeState) -> V.Value:
  match state:
    case PlanModeState{enabled, executing, todos, before}:
      Json.object(Json.field("enabled", Json.boolean(enabled), Json.field("todos", V.ArrayValue{todoValues(todos)}, Json.field("executing", Json.boolean(executing), Json.optional("toolsBeforePlanMode", Maybe.map(&2, List<&2, String>, V.Value, names => V.ArrayValue{texts(names)}, before), Nil{})))))

def persistState(+env: PlanMode) -> IO(Outcome()):
  do IO<Outcome()>:
    state : PlanModeState <- stateOf(env)
    Loader.appendEntry(apiOf(env), "plan-mode", Some{stateValue(state)})

# Toggling
# --------

def toggled(state: PlanModeState) -> PlanModeState:
  match state:
    case PlanModeState{enabled, _, _, before}: PlanModeState{Bool.not(enabled), False{}, Nil{}, before}

def switchTools(+env: PlanMode, +ctx: Ctx.ExtensionContext, enabled: Bool) -> IO(Outcome()):
  match enabled:
    case True{}:
      do IO<Outcome()>:
        switched : Outcome() <- enablePlanModeTools(env)
        Ctx.notify(ctx, "Plan mode enabled. Built-in write tools disabled.", Ctx.InfoNotice{})
        return switched
    case False{}:
      do IO<Outcome()>:
        switched : Outcome() <- restoreNormalModeTools(env)
        Ctx.notify(ctx, "Plan mode disabled. Full access restored.", Ctx.InfoNotice{})
        return switched

def updatedAndPersisted(+env: PlanMode, +ctx: Ctx.ExtensionContext) -> IO(Outcome()):
  do IO<Outcome()>:
    updateStatus(env, ctx)
    persistState(env)

def togglePlanMode(+env: PlanMode, +ctx: Ctx.ExtensionContext) -> IO(Outcome()):
  do IO<Outcome()>:
    +state : PlanModeState <- stateOf(env)
    +next : PlanModeState = toggled(state)
    writeState(env, next)
    switched : Outcome() <- switchTools(env, ctx, enabledOf(next))
    andThen(switched, _ => updatedAndPersisted(env, ctx))

# Commands and shortcut
# ---------------------

def onPlan(env: PlanMode, call: Ext.CommandCall) -> IO(Outcome()):
  match call:
    case Ext.CommandCall{_, ctx}: togglePlanMode(env, Ctx.commandContext(ctx))

def todoListLine(item: Utils.TodoItem, +index: Nat) -> String:
  match item:
    case Utils.TodoItem{_, text, completed}: Nat.show(index) ++ ". " ++ Bool.pick(String, completed, "\u{2713}", "\u{25cb}") ++ " " ++ text

def todoListLines(items: List<&2, Utils.TodoItem>, +index: Nat) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: todoListLine(item, index) <> todoListLines(rest, index + 1n)

def showTodos(+ctx: Ctx.ExtensionContext, todos: List<&2, Utils.TodoItem>) -> IO(Unit):
  match todos:
    case Nil{}: Ctx.notify(ctx, "No todos. Create a plan first with /plan", Ctx.InfoNotice{})
    case items: Ctx.notify(ctx, "Plan Progress:\n" ++ String.join(todoListLines(items, 1n), "\n"), Ctx.InfoNotice{})

def onTodos(env: PlanMode, call: Ext.CommandCall) -> IO(Outcome()):
  match call:
    case Ext.CommandCall{_, ctx}:
      do IO<Outcome()>:
        state : PlanModeState <- stateOf(env)
        showTodos(Ctx.commandContext(ctx), todosOf(state))
        done()

def onShortcut(env: PlanMode, ctx: Ctx.ExtensionContext) -> IO(Outcome()): togglePlanMode(env, ctx)

# tool_call: block destructive bash commands
# -----------------------------------------

def textOr(value: Maybe<&2, V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""

def commandOf(input: V.Value) -> String:
  match input:
    case V.ObjectValue{record}: textOr(Rec.get(V.Value, record, "command"))
    case _: ""

def blocked(+command: String) -> Maybe<&2, Ext.ToolCallEventResult>:
  Bool.pick(Maybe<&2, Ext.ToolCallEventResult>, Utils.isSafeCommand(command), None{}, Some{Ext.ToolCallEventResult{Some{True{}}, Some{"Plan mode: command blocked (not allowlisted). Use /plan to disable plan mode first.\nCommand: " ++ command}, None{}}})

def onToolCall(env: PlanMode, call: Ext.HandlerCall<Ext.ToolCallEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ext.ToolCallEventResult>>):
  match call:
    case Ext.HandlerCall{Ext.ToolCallEvent{_, +toolName, input}, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Ext.ToolCallEventResult>>>:
        state : PlanModeState <- stateOf(env)
        return Done{Bool.pick(Maybe<&2, Ext.ToolCallEventResult>, enabledOf(state) && String.eq(toolName, "bash"), blocked(commandOf(input)), None{})}

# context: filter stale plan mode context outside plan mode
# ---------------------------------------------------------

def mentionsPlanMode(blocks: List<&2, Ai.TextImageContent>) -> Bool:
  match blocks:
    case Nil{}: False{}
    case Ai.TextImageText{Ai.TextContent{text, _}} <> rest: String.contains(text, "[PLAN MODE ACTIVE]") || mentionsPlanMode(rest)
    case _ <> rest: mentionsPlanMode(rest)

def keptMessage(message: Ext.AgentMessage()) -> Bool:
  match message:
    case Agent.CustomMessage{Messages.Custom{Messages.CustomMessage{customType, _, _, _, _}}}: Bool.not(String.eq(customType, "plan-mode-context"))
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, _}}}: Bool.not(String.contains(text, "[PLAN MODE ACTIVE]"))
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{blocks}, _}}}: Bool.not(mentionsPlanMode(blocks))
    case _: True{}

def keptMessages(messages: List<&2, Ext.AgentMessage()>) -> List<&2, Ext.AgentMessage()>:
  match messages:
    case Nil{}: Nil{}
    case +message <> +rest: Bool.pick(List<&2, Ext.AgentMessage()>, keptMessage(message), message <> keptMessages(rest), keptMessages(rest))

def onContext(env: PlanMode, call: Ext.HandlerCall<Ext.ContextEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ext.ContextEventResult>>):
  match call:
    case Ext.HandlerCall{Ext.ContextEvent{messages}, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Ext.ContextEventResult>>>:
        state : PlanModeState <- stateOf(env)
        return Done{Bool.pick(Maybe<&2, Ext.ContextEventResult>, enabledOf(state), None{}, Some{Ext.ContextEventResult{Some{keptMessages(messages)}}})}

# before_agent_start: inject plan or execution context
# ---------------------------------------------------

def planModeContext() -> String:
  "[PLAN MODE ACTIVE]\nYou are in plan mode - a read-only exploration mode for safe code analysis.\n\nRestrictions:\n- Built-in edit and write tools are disabled\n- Other currently active tools remain available\n- Bash is restricted to an allowlist of read-only commands\n\nAsk clarifying questions using the questionnaire tool.\nUse brave-search skill via bash for web research.\n\nCreate a detailed numbered plan under a \"Plan:\" header:\n\nPlan:\n1. First step description\n2. Second step description\n...\n\nDo NOT attempt to make changes - just describe what you would do."

def stepLine(item: Utils.TodoItem) -> String:
  match item:
    case Utils.TodoItem{step, text, _}: Nat.show(step) ++ ". " ++ text

def remainingLines(items: List<&2, Utils.TodoItem>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case +item <> +rest: Bool.pick(List<&2, String>, isCompleted(item), remainingLines(rest), stepLine(item) <> remainingLines(rest))

def stepLines(items: List<&2, Utils.TodoItem>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: stepLine(item) <> stepLines(rest)

def contextMessage(+customType: String, +content: String) -> Maybe<&2, Ext.BeforeAgentStartEventResult>:
  Some{Ext.BeforeAgentStartEventResult{Some{Ext.CustomMessageInput{customType, Ai.UserText{content}, False{}, None{}}}, None{}, None{}}}

def executionContext(+state: PlanModeState) -> Maybe<&2, Ext.BeforeAgentStartEventResult>:
  Bool.pick(Maybe<&2, Ext.BeforeAgentStartEventResult>, executingOf(state) && hasTodos(state), contextMessage("plan-execution-context", "[EXECUTING PLAN - Full tool access enabled]\n\nRemaining steps:\n" ++ String.join(remainingLines(todosOf(state)), "\n") ++ "\n\nExecute each step in order.\nAfter completing a step, include a [DONE:n] tag in your response."), None{})

def startContext(+state: PlanModeState) -> Maybe<&2, Ext.BeforeAgentStartEventResult>:
  Bool.pick(Maybe<&2, Ext.BeforeAgentStartEventResult>, enabledOf(state), contextMessage("plan-mode-context", planModeContext()), executionContext(state))

def onBeforeAgentStart(env: PlanMode, call: Ext.HandlerCall<Ext.BeforeAgentStartEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ext.BeforeAgentStartEventResult>>):
  do IO<Result<&2, &2, String, Maybe<&2, Ext.BeforeAgentStartEventResult>>>:
    state : PlanModeState <- stateOf(env)
    return Done{startContext(state)}

# turn_end: track progress
# ------------------------

def textBlocks(content: List<&2, Ai.AssistantContent<V.Value>>) -> List<&2, String>:
  match content:
    case Nil{}: Nil{}
    case Ai.AssistantText{Ai.TextContent{text, _}} <> rest: text <> textBlocks(rest)
    case _ <> rest: textBlocks(rest)

# upstream getTextContent of an assistant message (isAssistantMessage).
def assistantText(message: Ext.AgentMessage()) -> Maybe<&2, String>:
  match message:
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}}: Some{String.join(textBlocks(content), "\n")}
    case _: None{}

def markedProgress(+env: PlanMode, +ctx: Ctx.ExtensionContext, state: PlanModeState, marked: List<&2, Utils.TodoItem> & Nat) -> IO(Outcome()):
  match marked:
    case (todos, count):
      do IO<Outcome()>:
        writeState(env, withTodos(state, todos))
        Bool.pick(Unit -> IO(Unit), Nat.is_gt(count, 0n), _ => updateStatus(env, ctx), _ => IO.pure(Unit, Unit{}))(Unit{})
        persistState(env)

def tracked(+env: PlanMode, +ctx: Ctx.ExtensionContext, +state: PlanModeState, text: Maybe<&2, String>) -> IO(Outcome()):
  match text:
    case None{}: done()
    case Some{found}: markedProgress(env, ctx, state, Utils.markCompletedSteps(found, todosOf(state)))

def handleTurnEnd(+env: PlanMode, call: Ext.HandlerCall<Ext.TurnEndEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ext.BoundaryResult>>):
  match call:
    case Ext.HandlerCall{Ext.TurnEndEvent{_, message, _, _, _, _, _, _, _}, ctx}:
      do IO<Result<&2, &2, String, Maybe<&2, Ext.BoundaryResult>>>:
        +state : PlanModeState <- stateOf(env)
        outcome : Outcome() <- Bool.pick(Unit -> IO(Outcome()), executingOf(state) && hasTodos(state), _ => tracked(env, ctx, state, assistantText(message)), _ => done())(Unit{})
        return Result.map(&2, &2, String, Unit, Maybe<&2, Ext.BoundaryResult>, _ => None{}, outcome)

def onTurnEnd(env: PlanMode, call: Ext.HandlerCall<Ext.TurnEndEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ext.BoundaryResult>>): handleTurnEnd(env, call)

# agent_end: plan completion and the plan mode prompt
# ---------------------------------------------------

def struck(items: List<&2, Utils.TodoItem>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: ("~~" ++ itemText(item) ++ "~~") <> struck(rest)

def clearedExecution(+env: PlanMode, +ctx: Ctx.ExtensionContext) -> IO(Outcome()):
  do IO<Outcome()>:
    +state : PlanModeState <- stateOf(env)
    writeState(env, withTodos(withExecuting(state, False{}), Nil{}))
    updatedAndPersisted(env, ctx)

def completePlan(+env: PlanMode, +ctx: Ctx.ExtensionContext, +state: PlanModeState) -> IO(Outcome()):
  do IO<Outcome()>:
    sent : Outcome() <- Loader.sendMessage(apiOf(env), Ext.CustomMessageInput{"plan-complete", Ai.UserText{"**Plan Complete!** \u{2713}\n\n" ++ String.join(struck(todosOf(state)), "\n")}, True{}, None{}}, Ext.SendMessageOptions{Some{False{}}, None{}})
    andThen(sent, _ => clearedExecution(env, ctx))

def orLater(later: Maybe<&2, String>, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match later:
    case None{}: found
    case Some{text}: Some{text}

def lastAssistantText(messages: List<&2, Ext.AgentMessage()>, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match messages:
    case Nil{}: found
    case message <> rest: lastAssistantText(rest, orLater(assistantText(message), found))

def extracted(+state: PlanModeState, text: Maybe<&2, String>) -> PlanModeState:
  match text:
    case None{}: state
    case Some{+found}:
      +items = Utils.extractTodoItems(found)
      Bool.pick(PlanModeState, List.is_empty(&2, Utils.TodoItem, items), state, withTodos(state, items))

def checkboxLines(items: List<&2, Utils.TodoItem>, +index: Nat) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: (Nat.show(index) ++ ". \u{2610} " ++ itemText(item)) <> checkboxLines(rest, index + 1n)

def planTodoListMessage(+todos: List<&2, Utils.TodoItem>) -> Ext.CustomMessageInput:
  Ext.CustomMessageInput{"plan-todo-list", Ai.UserText{"**Plan Steps (" ++ Nat.show(List.length(&2, Utils.TodoItem, todos)) ++ "):**\n\n" ++ String.join(checkboxLines(todos, 1n), "\n")}, True{}, None{}}

def followUp() -> Ext.SendMessageOptions: Ext.SendMessageOptions{None{}, Some{Ext.DeliverFollowUp{}}}

def executeMessage(+todos: List<&2, Utils.TodoItem>, first: Utils.TodoItem) -> String:
  "Execute the plan.\n\nRemaining steps:\n" ++ String.join(stepLines(todos), "\n") ++ "\n\nStart with: " ++ itemText(first) ++ "\nAfter completing a step, include a [DONE:n] tag in your response."

def executionMessages(+env: PlanMode, +todos: List<&2, Utils.TodoItem>, first: Utils.TodoItem) -> IO(Outcome()):
  do IO<Outcome()>:
    listed : Outcome() <- Loader.sendMessage(apiOf(env), planTodoListMessage(todos), followUp())
    andThen(listed, _ => Loader.sendMessage(apiOf(env), Ext.CustomMessageInput{"plan-mode-execute", Ai.UserText{executeMessage(todos, first)}, True{}, None{}}, Ext.SendMessageOptions{Some{True{}}, Some{Ext.DeliverFollowUp{}}}))

def executionStarted(+env: PlanMode, +ctx: Ctx.ExtensionContext, +todos: List<&2, Utils.TodoItem>, first: Utils.TodoItem) -> IO(Outcome()):
  do IO<Outcome()>:
    persisted : Outcome() <- updatedAndPersisted(env, ctx)
    andThen(persisted, _ => executionMessages(env, todos, first))

def executePlan(+env: PlanMode, +ctx: Ctx.ExtensionContext, +todos: List<&2, Utils.TodoItem>) -> IO(Outcome()):
  match todos:
    case Nil{}: done()
    case first <> _:
      do IO<Outcome()>:
        +state : PlanModeState <- stateOf(env)
        writeState(env, withExecuting(withEnabled(state, False{}), True{}))
        restored : Outcome() <- restoreNormalModeTools(env)
        andThen(restored, _ => executionStarted(env, ctx, todos, first))

def refinedWith(+env: PlanMode, +todos: List<&2, Utils.TodoItem>, +trimmed: String) -> IO(Outcome()):
  do IO<Outcome()>:
    listed : Outcome() <- Loader.sendMessage(apiOf(env), planTodoListMessage(todos), followUp())
    andThen(listed, _ => Loader.sendUserMessage(apiOf(env), Ai.UserText{trimmed}, Ext.SendUserMessageOptions{Some{Ext.UserFollowUp{}}, None{}}))

def refined(+env: PlanMode, +todos: List<&2, Utils.TodoItem>, refinement: Maybe<&2, String>) -> IO(Outcome()):
  match refinement:
    case None{}: done()
    case Some{text}:
      +trimmed = Text.trim(text)
      Bool.pick(Unit -> IO(Outcome()), String.is_empty(trimmed), _ => done(), _ => refinedWith(env, todos, trimmed))(Unit{})

def refinePlan(+env: PlanMode, +ctx: Ctx.ExtensionContext, +todos: List<&2, Utils.TodoItem>) -> IO(Outcome()):
  do IO<Outcome()>:
    refinement : Maybe<&2, String> <- Ctx.editor(ctx, "Refine the plan:", Some{""})
    refined(env, todos, refinement)

def chosen(+env: PlanMode, +ctx: Ctx.ExtensionContext, +todos: List<&2, Utils.TodoItem>, choice: Maybe<&2, String>) -> IO(Outcome()):
  match choice:
    case None{}: done()
    case Some{+text}:
      Bool.pick(Unit -> IO(Outcome()), String.starts_with(text, "Execute"), _ => executePlan(env, ctx, todos), _ => Bool.pick(Unit -> IO(Outcome()), String.eq(text, "Refine the plan"), _ => refinePlan(env, ctx, todos), _ => done())(Unit{}))(Unit{})

def selectNext(+env: PlanMode, +ctx: Ctx.ExtensionContext, +todos: List<&2, Utils.TodoItem>) -> IO(Outcome()):
  do IO<Outcome()>:
    choice : Maybe<&2, String> <- Ctx.select(ctx, "Plan mode - what next?", ["Execute the plan (track progress)", "Stay in plan mode", "Refine the plan"], Ctx.dialogOptions())
    chosen(env, ctx, todos, choice)

def promptWithTodos(+env: PlanMode, +ctx: Ctx.ExtensionContext, todos: List<&2, Utils.TodoItem>) -> IO(Outcome()):
  match todos:
    case Nil{}: done()
    case +items:
      do IO<Outcome()>:
        persisted : Outcome() <- persistState(env)
        andThen(persisted, _ => selectNext(env, ctx, items))

def promptForPlan(+env: PlanMode, +ctx: Ctx.ExtensionContext, messages: List<&2, Ext.AgentMessage()>) -> IO(Outcome()):
  do IO<Outcome()>:
    +state : PlanModeState <- stateOf(env)
    +next : PlanModeState = extracted(state, lastAssistantText(messages, None{}))
    writeState(env, next)
    promptWithTodos(env, ctx, todosOf(next))

def promptIfUI(+env: PlanMode, +ctx: Ctx.ExtensionContext, messages: List<&2, Ext.AgentMessage()>) -> IO(Outcome()):
  do IO<Outcome()>:
    shown : Bool <- Ctx.hasUI(ctx)
    Bool.pick(Unit -> IO(Outcome()), shown, _ => promptForPlan(env, ctx, messages), _ => done())(Unit{})

def planPrompt(+env: PlanMode, +ctx: Ctx.ExtensionContext, +state: PlanModeState, messages: List<&2, Ext.AgentMessage()>) -> IO(Outcome()):
  Bool.pick(Unit -> IO(Outcome()), enabledOf(state), _ => promptIfUI(env, ctx, messages), _ => done())(Unit{})

def executionEnded(+env: PlanMode, +ctx: Ctx.ExtensionContext, +state: PlanModeState) -> IO(Outcome()):
  Bool.pick(Unit -> IO(Outcome()), allCompleted(todosOf(state)), _ => completePlan(env, ctx, state), _ => done())(Unit{})

def agentEnded(+env: PlanMode, +ctx: Ctx.ExtensionContext, +state: PlanModeState, messages: List<&2, Ext.AgentMessage()>) -> IO(Outcome()):
  Bool.pick(Unit -> IO(Outcome()), executingOf(state) && hasTodos(state), _ => executionEnded(env, ctx, state), _ => planPrompt(env, ctx, state, messages))(Unit{})

def handleAgentEnd(+env: PlanMode, call: Ext.HandlerCall<Ext.AgentEndEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  match call:
    case Ext.HandlerCall{Ext.AgentEndEvent{messages}, ctx}:
      do IO<Result<&2, &2, String, Maybe<&2, Unit>>>:
        +state : PlanModeState <- stateOf(env)
        outcome : Outcome() <- agentEnded(env, ctx, state, messages)
        return Result.map(&2, &2, String, Unit, Maybe<&2, Unit>, _ => None{}, outcome)

def onAgentEnd(env: PlanMode, call: Ext.HandlerCall<Ext.AgentEndEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>): handleAgentEnd(env, call)

# session_start: restore state
# ----------------------------

def Entry() -> Data: S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>

def entriesOf(manager: Maybe<&2, Ctx.ReadonlySessionManager()>) -> List<&2, Entry()>:
  match manager:
    case None{}: Nil{}
    case Some{session}: S.getEntries(V.Value, Tools.ToolDetails, V.Value, Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, session))

# The last custom entry of type "plan-mode" (upstream filters and pops).
def lastPlanModeEntry(entries: List<&2, Entry()>, found: Maybe<&2, Maybe<&2, V.Value>>) -> Maybe<&2, Maybe<&2, V.Value>>:
  match entries:
    case Nil{}: found
    case S.CustomEntry{_, customType, data} <> rest: lastPlanModeEntry(rest, Bool.pick(Maybe<&2, Maybe<&2, V.Value>>, String.eq(customType, "plan-mode"), Some{data}, found))
    case _ <> rest: lastPlanModeEntry(rest, found)

def fieldOf(data: V.Value, key: String) -> Maybe<&2, V.Value>:
  match data:
    case V.ObjectValue{record}: Rec.get(V.Value, record, key)
    case _: None{}

def boolOr(value: Maybe<&2, V.Value>, fallback: Bool) -> Bool:
  match value:
    case Some{V.Boolean{flag}}: flag
    case _: fallback

def todoFrom(step: Maybe<&2, V.Value>, text: Maybe<&2, V.Value>, completed: Maybe<&2, V.Value>) -> Maybe<&2, Utils.TodoItem>:
  match step text completed:
    case Some{V.Number{number}} Some{V.Text{value}} Some{V.Boolean{flag}}: Some{Utils.TodoItem{U32.to_nat(F64.to_u32(number)), value, flag}}
    case _ _ _: None{}

def decodedTodo(+value: V.Value) -> Maybe<&2, Utils.TodoItem>:
  todoFrom(fieldOf(value, "step"), fieldOf(value, "text"), fieldOf(value, "completed"))

def prependTodo(item: Maybe<&2, Utils.TodoItem>, rest: List<&2, Utils.TodoItem>) -> List<&2, Utils.TodoItem>:
  match item:
    case None{}: rest
    case Some{found}: found <> rest

def decodedTodos(values: List<&2, V.Value>) -> List<&2, Utils.TodoItem>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: prependTodo(decodedTodo(value), decodedTodos(rest))

def todosOr(value: Maybe<&2, V.Value>, fallback: List<&2, Utils.TodoItem>) -> List<&2, Utils.TodoItem>:
  match value:
    case Some{V.ArrayValue{values}}: decodedTodos(values)
    case _: fallback

def decodedNames(values: List<&2, V.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case V.Text{name} <> rest: name <> decodedNames(rest)
    case _ <> rest: decodedNames(rest)

def namesOr(value: Maybe<&2, V.Value>, fallback: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{decodedNames(values)}
    case _: fallback

# `data.x ?? current` for each stored field.
def restored(state: PlanModeState, +data: V.Value) -> PlanModeState:
  match state:
    case PlanModeState{enabled, executing, todos, before}: PlanModeState{boolOr(fieldOf(data, "enabled"), enabled), boolOr(fieldOf(data, "executing"), executing), todosOr(fieldOf(data, "todos"), todos), namesOr(fieldOf(data, "toolsBeforePlanMode"), before)}

def restoredFrom(state: PlanModeState, entry: Maybe<&2, Maybe<&2, V.Value>>) -> PlanModeState:
  match entry:
    case Some{Some{data}}: restored(state, data)
    case _: state

def entryCustomType(entry: Entry()) -> Maybe<&2, String>:
  match entry:
    case S.CustomEntry{_, customType, _}: Some{customType}
    case S.CustomMessageEntry{_, customType, _, _, _}: Some{customType}
    case _: None{}

def isExecuteType(customType: Maybe<&2, String>) -> Bool:
  match customType:
    case Some{found}: String.eq(found, "plan-mode-execute")
    case None{}: False{}

def isExecuteMarker(entry: Entry()) -> Bool: isExecuteType(entryCustomType(entry))

# The entries after the last "plan-mode-execute" (all of them without one).
def afterLastExecute(entries: List<&2, Entry()>, +after: List<&2, Entry()>) -> List<&2, Entry()>:
  match entries:
    case Nil{}: after
    case +entry <> rest: afterLastExecute(rest, Bool.pick(List<&2, Entry()>, isExecuteMarker(entry), Nil{}, List.append(&2, Entry(), after, [entry])))

def prependText(text: Maybe<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match text:
    case None{}: rest
    case Some{found}: found <> rest

def assistantTexts(entries: List<&2, Entry()>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case S.SessionMessageEntry{_, message} <> rest: prependText(assistantText(message), assistantTexts(rest))
    case _ <> rest: assistantTexts(rest)

# On resume, the messages after the current execution started mark its
# completed steps.
def markedTodos(state: PlanModeState, marked: List<&2, Utils.TodoItem> & Nat) -> PlanModeState:
  match marked:
    case (todos, _): withTodos(state, todos)

def rescanned(+state: PlanModeState, entries: List<&2, Entry()>) -> PlanModeState:
  markedTodos(state, Utils.markCompletedSteps(String.join(assistantTexts(afterLastExecute(entries, Nil{})), "\n"), todosOf(state)))

def resumed(+state: PlanModeState, resume: Bool, entries: List<&2, Entry()>) -> PlanModeState:
  Bool.pick(PlanModeState, resume && executingOf(state) && hasTodos(state), rescanned(state, entries), state)

def flagged(state: PlanModeState, flag: Result<&2, &2, String, Maybe<&2, Ext.FlagValue>>) -> PlanModeState:
  match flag:
    case Done{Some{Ext.FlagBoolean{True{}}}}: withEnabled(state, True{})
    case _: state

def handleSessionStart(+env: PlanMode, call: Ext.HandlerCall<Ext.SessionStartEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  match call:
    case Ext.HandlerCall{_, +ctx}:
      do IO<Result<&2, &2, String, Maybe<&2, Unit>>>:
        flag : Result<&2, &2, String, Maybe<&2, Ext.FlagValue>> <- Loader.getFlag(apiOf(env), "plan")
        manager : Maybe<&2, Ctx.ReadonlySessionManager()> <- Ctx.sessionManager(ctx)
        +entries : List<&2, Entry()> = entriesOf(manager)
        +entry : Maybe<&2, Maybe<&2, V.Value>> = lastPlanModeEntry(entries, None{})
        +state : PlanModeState <- stateOf(env)
        +next : PlanModeState = resumed(restoredFrom(flagged(state, flag), entry), Maybe.is_some(&2, Maybe<&2, V.Value>, entry), entries)
        writeState(env, next)
        enabledTools : Outcome() <- Bool.pick(Unit -> IO(Outcome()), enabledOf(next), _ => enablePlanModeTools(env), _ => done())(Unit{})
        updateStatus(env, ctx)
        return Result.map(&2, &2, String, Unit, Maybe<&2, Unit>, _ => None{}, enabledTools)

def onSessionStart(env: PlanMode, call: Ext.HandlerCall<Ext.SessionStartEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>): handleSessionStart(env, call)

# Registration
# ------------

def subscribed(first: Outcome(), second: Result<&2, &2, String, Loader.Unsubscribe>) -> Outcome():
  match first:
    case Fail{error}: Fail{error}
    case Done{_}: unit(Loader.Unsubscribe, second)

def both(first: Outcome(), second: Outcome()) -> Outcome():
  match first:
    case Fail{error}: Fail{error}
    case Done{_}: second

def registerCommands(+env: PlanMode) -> IO(Outcome()):
  do IO<Outcome()>:
    plan : Ext.CommandHandler() <- C.create(~PlanMode, ~Ext.CommandCall, ~Outcome(), ~onPlan, env)
    first : Outcome() <- Loader.registerCommand(apiOf(env), "plan", Ext.CommandOptions{Some{"Toggle plan mode (read-only exploration)"}, None{}, plan})
    todos : Ext.CommandHandler() <- C.create(~PlanMode, ~Ext.CommandCall, ~Outcome(), ~onTodos, env)
    second : Outcome() <- Loader.registerCommand(apiOf(env), "todos", Ext.CommandOptions{Some{"Show current plan todo list"}, None{}, todos})
    shortcut : Ext.ShortcutHandler() <- C.create(~PlanMode, ~Ctx.ExtensionContext, ~Outcome(), ~onShortcut, env)
    third : Outcome() <- Loader.registerShortcut(apiOf(env), "ctrl+alt+p", Ext.ShortcutOptions{Some{"Toggle plan mode"}, shortcut})
    return both(first, both(second, third))

def subscribeHandlers(+env: PlanMode) -> IO(Outcome()):
  do IO<Outcome()>:
    toolCall : Ext.ExtensionHandler(Ext.ToolCallEvent, Ext.ToolCallEventResult) <- C.create(~PlanMode, ~Ext.HandlerCall<Ext.ToolCallEvent>, ~Result<&2, &2, String, Maybe<&2, Ext.ToolCallEventResult>>, ~onToolCall, env)
    a : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(apiOf(env), Ext.OnToolCall{toolCall})
    context : Ext.ExtensionHandler(Ext.ContextEvent, Ext.ContextEventResult) <- C.create(~PlanMode, ~Ext.HandlerCall<Ext.ContextEvent>, ~Result<&2, &2, String, Maybe<&2, Ext.ContextEventResult>>, ~onContext, env)
    b : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(apiOf(env), Ext.OnContext{context})
    start : Ext.ExtensionHandler(Ext.BeforeAgentStartEvent, Ext.BeforeAgentStartEventResult) <- C.create(~PlanMode, ~Ext.HandlerCall<Ext.BeforeAgentStartEvent>, ~Result<&2, &2, String, Maybe<&2, Ext.BeforeAgentStartEventResult>>, ~onBeforeAgentStart, env)
    c : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(apiOf(env), Ext.OnBeforeAgentStart{start})
    turn : Ext.ExtensionHandler(Ext.TurnEndEvent, Ext.BoundaryResult) <- C.create(~PlanMode, ~Ext.HandlerCall<Ext.TurnEndEvent>, ~Result<&2, &2, String, Maybe<&2, Ext.BoundaryResult>>, ~onTurnEnd, env)
    d : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(apiOf(env), Ext.OnTurnEnd{turn})
    ended : Ext.ExtensionHandler(Ext.AgentEndEvent, Unit) <- C.create(~PlanMode, ~Ext.HandlerCall<Ext.AgentEndEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~onAgentEnd, env)
    e : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(apiOf(env), Ext.OnAgentEnd{ended})
    session : Ext.ExtensionHandler(Ext.SessionStartEvent, Unit) <- C.create(~PlanMode, ~Ext.HandlerCall<Ext.SessionStartEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~onSessionStart, env)
    f : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(apiOf(env), Ext.OnSessionStart{session})
    return subscribed(subscribed(subscribed(subscribed(subscribed(subscribed(Done{Unit{}}, a), b), c), d), e), f)

def registered(+api: Ext.ExtensionAPI) -> IO(Outcome()):
  do IO<Outcome()>:
    flag : Outcome() <- Loader.registerFlag(api, "plan", Ext.FlagOptions{Some{"Start in plan mode (read-only exploration)"}, Ext.BooleanFlag{}, Some{Ext.FlagBoolean{False{}}}})
    state : R.Ref<PlanModeState> <- R.new(PlanModeState, PlanModeState{False{}, False{}, Nil{}, None{}})
    +env : PlanMode = PlanMode{api, state}
    commands : Outcome() <- registerCommands(env)
    handlers : Outcome() <- subscribeHandlers(env)
    return both(flag, both(commands, handlers))

# upstream default export planModeExtension(pi).
def planModeExtension(api: Ext.ExtensionAPI) -> IO(Outcome()): registered(api)
