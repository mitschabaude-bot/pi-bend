import Base
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/ref.bend as R
import ../../../../tui/src/component.bend as Component
import ../model-runtime.bend as Models

# upstream ExtensionContext and ExtensionCommandContext (core/extensions/
# types.ts). The context is a handle on its runner: like upstream's getters,
# each accessor reads the mode, UI and session the runner is bound to when it
# is called. This module is separate from types.bend so that the built-in
# tools, which receive the context, do not depend on extension registrations.

type ExtensionMode is Data:
  TuiMode{}
  RpcMode{}
  JsonMode{}
  PrintMode{}

def modeName(mode: ExtensionMode) -> String:
  match mode:
    case TuiMode{}: "tui"
    case RpcMode{}: "rpc"
    case JsonMode{}: "json"
    case PrintMode{}: "print"

# UI (upstream ExtensionUIContext)
# --------------------------------

type NotifyType is Data:
  InfoNotice{}
  WarningNotice{}
  ErrorNotice{}

def notifyTypeName(kind: NotifyType) -> String:
  match kind:
    case InfoNotice{}: "info"
    case WarningNotice{}: "warning"
    case ErrorNotice{}: "error"

type Notification is Data:
  Notification{message: String, kind: NotifyType}

type StatusUpdate is Data:
  StatusUpdate{key: String, text: Maybe<&2, String>}

type SelectRequest is Data:
  SelectRequest{title: String, options: List<&2, String>}

type ConfirmRequest is Data:
  ConfirmRequest{title: String, message: String}

type InputRequest is Data:
  InputRequest{title: String, placeholder: Maybe<&2, String>}

# upstream custom(factory): the factory builds the component and receives the
# `done` callback that closes it. Upstream's generic result travels through
# the extension's own state here: `custom` answers when `done` was called.
def CustomDone() -> Data: C.Callback<Unit, Unit>
def CustomFactory() -> Data: C.Callback<CustomDone(), Component.Component>

# The dialog-capable UI a mode binds. Print and JSON modes bind none
# (upstream noOpUIContext); the accessors below then answer as it does.
type ExtensionUIContext is Data:
  ExtensionUIContext{select: C.Callback<SelectRequest, Maybe<&2, String>>, confirm: C.Callback<ConfirmRequest, Bool>, input: C.Callback<InputRequest, Maybe<&2, String>>, notify: C.Callback<Notification, Unit>, setStatus: C.Callback<StatusUpdate, Unit>, custom: C.Callback<CustomFactory(), Unit>}

# Session actions (upstream ExtensionContextActions)
# ---------------------------------------------------

# What the context's getters read from the session when they are called.
# Upstream reaches sessionId and sessionFile through its read-only
# SessionManager.
type SessionState is Data:
  SessionState{model: Maybe<&2, Ai.Model<Ai.JsonValue>>, scopedModels: List<&2, Models.ScopedModel>, thinkingLevel: Ai.ModelThinkingLevel, sessionId: String, sessionFile: Maybe<&2, String>, idle: Bool, projectTrusted: Bool, pendingMessages: Bool, signal: Maybe<&2, Abort.AbortSignal<Unit>>}

type ExtensionContextActions is Data:
  ExtensionContextActions{state: C.Callback<Unit, SessionState>, abort: C.Callback<Unit, Unit>, shutdown: C.Callback<Unit, Unit>}

# Session control for commands (upstream ExtensionCommandContextActions).
# The `withSession` and `setup` continuations are not ported.
type ForkPosition is Data:
  ForkBefore{}
  ForkAt{}

type NewSessionRequest is Data:
  NewSessionRequest{parentSession: Maybe<&2, String>}

type ForkRequest is Data:
  ForkRequest{entryId: String, position: Maybe<&2, ForkPosition>}

type NavigateTreeRequest is Data:
  NavigateTreeRequest{targetId: String, summarize: Maybe<&2, Bool>, customInstructions: Maybe<&2, String>, replaceInstructions: Maybe<&2, Bool>, label: Maybe<&2, String>}

type SwitchSessionRequest is Data:
  SwitchSessionRequest{sessionPath: String}

# upstream `{ cancelled: boolean }`
type SessionChange is Data:
  SessionChange{cancelled: Bool}

type ExtensionCommandContextActions is Data:
  ExtensionCommandContextActions{waitForIdle: C.Callback<Unit, Unit>, newSession: C.Callback<NewSessionRequest, SessionChange>, fork: C.Callback<ForkRequest, SessionChange>, navigateTree: C.Callback<NavigateTreeRequest, SessionChange>, switchSession: C.Callback<SwitchSessionRequest, SessionChange>, reload: C.Callback<Unit, Unit>}

# What the runner is bound to. The callbacks belong to whoever bound them;
# they unbind before disposing them.
type Bindings is Data:
  Bindings{ui: Maybe<&2, ExtensionUIContext>, mode: ExtensionMode, session: Maybe<&2, ExtensionContextActions>, commands: Maybe<&2, ExtensionCommandContextActions>}

def unbound() -> Bindings: Bindings{None{}, PrintMode{}, None{}, None{}}

type ExtensionContext is Data:
  ExtensionContext{cwd: String, modelRegistry: Models.ModelRuntime, bindings: R.Ref<Bindings>}

type ExtensionCommandContext is Data:
  ExtensionCommandContext{context: ExtensionContext}

# Accessors
# ---------

def cwd(context: ExtensionContext) -> String:
  match context:
    case ExtensionContext{value, _, _}: value

def modelRegistry(context: ExtensionContext) -> Models.ModelRuntime:
  match context:
    case ExtensionContext{_, models, _}: models

def bindingsOf(context: ExtensionContext) -> IO(Bindings):
  match context:
    case ExtensionContext{_, _, bindings}: R.read(Bindings, bindings)

def modeOf(bindings: Bindings) -> ExtensionMode:
  match bindings:
    case Bindings{_, chosen, _, _}: chosen

def uiOf(bindings: Bindings) -> Maybe<&2, ExtensionUIContext>:
  match bindings:
    case Bindings{ui, _, _, _}: ui

def sessionOf(bindings: Bindings) -> Maybe<&2, ExtensionContextActions>:
  match bindings:
    case Bindings{_, _, session, _}: session

def commandsOf(bindings: Bindings) -> Maybe<&2, ExtensionCommandContextActions>:
  match bindings:
    case Bindings{_, _, _, commands}: commands

def mode(context: ExtensionContext) -> IO(ExtensionMode):
  do IO<ExtensionMode>:
    bindings : Bindings <- bindingsOf(context)
    return modeOf(bindings)

# upstream hasUI: a UI context is bound (TUI and RPC modes).
def hasUI(context: ExtensionContext) -> IO(Bool):
  do IO<Bool>:
    bindings : Bindings <- bindingsOf(context)
    return Maybe.is_some(&2, ExtensionUIContext, uiOf(bindings))

# Without a bound session: no model, no scoped models, "off", idle, trusted.
def unboundState() -> SessionState:
  SessionState{None{}, Nil{}, Ai.Off{}, "", None{}, True{}, True{}, False{}, None{}}

def stateFrom(session: Maybe<&2, ExtensionContextActions>) -> IO(SessionState):
  match session:
    case None{}: IO.pure(SessionState, unboundState())
    case Some{ExtensionContextActions{state, _, _}}: C.call(Unit, SessionState, state, Unit{})

def stateModel(state: SessionState) -> Maybe<&2, Ai.Model<Ai.JsonValue>>:
  match state:
    case SessionState{found, _, _, _, _, _, _, _, _}: found

def stateScoped(state: SessionState) -> List<&2, Models.ScopedModel>:
  match state:
    case SessionState{_, scoped, _, _, _, _, _, _, _}: scoped

def stateThinking(state: SessionState) -> Ai.ModelThinkingLevel:
  match state:
    case SessionState{_, _, level, _, _, _, _, _, _}: level

def stateIdle(state: SessionState) -> Bool:
  match state:
    case SessionState{_, _, _, _, _, idle, _, _, _}: idle

def stateTrusted(state: SessionState) -> Bool:
  match state:
    case SessionState{_, _, _, _, _, _, trusted, _, _}: trusted

def statePending(state: SessionState) -> Bool:
  match state:
    case SessionState{_, _, _, _, _, _, _, pending, _}: pending

def stateSignal(state: SessionState) -> Maybe<&2, Abort.AbortSignal<Unit>>:
  match state:
    case SessionState{_, _, _, _, _, _, _, _, live}: live

def sessionState(context: ExtensionContext) -> IO(SessionState):
  do IO<SessionState>:
    bindings : Bindings <- bindingsOf(context)
    stateFrom(sessionOf(bindings))

def model(context: ExtensionContext) -> IO(Maybe<&2, Ai.Model<Ai.JsonValue>>):
  do IO<Maybe<&2, Ai.Model<Ai.JsonValue>>>:
    state : SessionState <- sessionState(context)
    return stateModel(state)

def scopedModels(context: ExtensionContext) -> IO(List<&2, Models.ScopedModel>):
  do IO<List<&2, Models.ScopedModel>>:
    state : SessionState <- sessionState(context)
    return stateScoped(state)

def thinkingLevel(context: ExtensionContext) -> IO(Ai.ModelThinkingLevel):
  do IO<Ai.ModelThinkingLevel>:
    state : SessionState <- sessionState(context)
    return stateThinking(state)

def isIdle(context: ExtensionContext) -> IO(Bool):
  do IO<Bool>:
    state : SessionState <- sessionState(context)
    return stateIdle(state)

def isProjectTrusted(context: ExtensionContext) -> IO(Bool):
  do IO<Bool>:
    state : SessionState <- sessionState(context)
    return stateTrusted(state)

def hasPendingMessages(context: ExtensionContext) -> IO(Bool):
  do IO<Bool>:
    state : SessionState <- sessionState(context)
    return statePending(state)

# The current abort signal; None while the agent is not streaming.
def signal(context: ExtensionContext) -> IO(Maybe<&2, Abort.AbortSignal<Unit>>):
  do IO<Maybe<&2, Abort.AbortSignal<Unit>>>:
    state : SessionState <- sessionState(context)
    return stateSignal(state)

def abortWith(session: Maybe<&2, ExtensionContextActions>) -> IO(Unit):
  match session:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ExtensionContextActions{_, callback, _}}: C.call(Unit, Unit, callback, Unit{})

def abort(context: ExtensionContext) -> IO(Unit):
  do IO<Unit>:
    bindings : Bindings <- bindingsOf(context)
    abortWith(sessionOf(bindings))

def shutdownWith(session: Maybe<&2, ExtensionContextActions>) -> IO(Unit):
  match session:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ExtensionContextActions{_, _, callback}}: C.call(Unit, Unit, callback, Unit{})

def shutdown(context: ExtensionContext) -> IO(Unit):
  do IO<Unit>:
    bindings : Bindings <- bindingsOf(context)
    shutdownWith(sessionOf(bindings))

# UI accessors; without a UI they answer as upstream's noOpUIContext.

def notifyWith(ui: Maybe<&2, ExtensionUIContext>, notification: Notification) -> IO(Unit):
  match ui:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ExtensionUIContext{_, _, _, callback, _, _}}: C.call(Notification, Unit, callback, notification)

def notify(context: ExtensionContext, message: String, kind: NotifyType) -> IO(Unit):
  do IO<Unit>:
    bindings : Bindings <- bindingsOf(context)
    notifyWith(uiOf(bindings), Notification{message, kind})

def statusWith(ui: Maybe<&2, ExtensionUIContext>, update: StatusUpdate) -> IO(Unit):
  match ui:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ExtensionUIContext{_, _, _, _, callback, _}}: C.call(StatusUpdate, Unit, callback, update)

def setStatus(context: ExtensionContext, key: String, text: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    bindings : Bindings <- bindingsOf(context)
    statusWith(uiOf(bindings), StatusUpdate{key, text})

def selectWith(ui: Maybe<&2, ExtensionUIContext>, request: SelectRequest) -> IO(Maybe<&2, String>):
  match ui:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{ExtensionUIContext{callback, _, _, _, _, _}}: C.call(SelectRequest, Maybe<&2, String>, callback, request)

def select(context: ExtensionContext, title: String, options: List<&2, String>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    bindings : Bindings <- bindingsOf(context)
    selectWith(uiOf(bindings), SelectRequest{title, options})

def confirmWith(ui: Maybe<&2, ExtensionUIContext>, request: ConfirmRequest) -> IO(Bool):
  match ui:
    case None{}: IO.pure(Bool, False{})
    case Some{ExtensionUIContext{_, callback, _, _, _, _}}: C.call(ConfirmRequest, Bool, callback, request)

def confirm(context: ExtensionContext, title: String, message: String) -> IO(Bool):
  do IO<Bool>:
    bindings : Bindings <- bindingsOf(context)
    confirmWith(uiOf(bindings), ConfirmRequest{title, message})

def inputWith(ui: Maybe<&2, ExtensionUIContext>, request: InputRequest) -> IO(Maybe<&2, String>):
  match ui:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{ExtensionUIContext{_, _, callback, _, _, _}}: C.call(InputRequest, Maybe<&2, String>, callback, request)

def input(context: ExtensionContext, title: String, placeholder: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    bindings : Bindings <- bindingsOf(context)
    inputWith(uiOf(bindings), InputRequest{title, placeholder})

def customWith(ui: Maybe<&2, ExtensionUIContext>, factory: CustomFactory()) -> IO(Unit):
  match ui:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ExtensionUIContext{_, _, _, _, _, callback}}: C.call(CustomFactory(), Unit, callback, factory)

def custom(context: ExtensionContext, factory: CustomFactory()) -> IO(Unit):
  do IO<Unit>:
    bindings : Bindings <- bindingsOf(context)
    customWith(uiOf(bindings), factory)

# Command context (upstream createCommandContext)
# -----------------------------------------------

def commandContext(context: ExtensionCommandContext) -> ExtensionContext:
  match context:
    case ExtensionCommandContext{value}: value

def commandActions(context: ExtensionCommandContext) -> IO(Maybe<&2, ExtensionCommandContextActions>):
  do IO<Maybe<&2, ExtensionCommandContextActions>>:
    bindings : Bindings <- bindingsOf(commandContext(context))
    return commandsOf(bindings)

def notCancelled() -> SessionChange: SessionChange{False{}}

def waitForIdleWith(actions: Maybe<&2, ExtensionCommandContextActions>) -> IO(Unit):
  match actions:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ExtensionCommandContextActions{callback, _, _, _, _, _}}: C.call(Unit, Unit, callback, Unit{})

def waitForIdle(context: ExtensionCommandContext) -> IO(Unit):
  do IO<Unit>:
    actions : Maybe<&2, ExtensionCommandContextActions> <- commandActions(context)
    waitForIdleWith(actions)

def newSessionWith(actions: Maybe<&2, ExtensionCommandContextActions>, request: NewSessionRequest) -> IO(SessionChange):
  match actions:
    case None{}: IO.pure(SessionChange, notCancelled())
    case Some{ExtensionCommandContextActions{_, callback, _, _, _, _}}: C.call(NewSessionRequest, SessionChange, callback, request)

def newSession(context: ExtensionCommandContext, request: NewSessionRequest) -> IO(SessionChange):
  do IO<SessionChange>:
    actions : Maybe<&2, ExtensionCommandContextActions> <- commandActions(context)
    newSessionWith(actions, request)

def forkWith(actions: Maybe<&2, ExtensionCommandContextActions>, request: ForkRequest) -> IO(SessionChange):
  match actions:
    case None{}: IO.pure(SessionChange, notCancelled())
    case Some{ExtensionCommandContextActions{_, _, callback, _, _, _}}: C.call(ForkRequest, SessionChange, callback, request)

def fork(context: ExtensionCommandContext, entryId: String, position: Maybe<&2, ForkPosition>) -> IO(SessionChange):
  do IO<SessionChange>:
    actions : Maybe<&2, ExtensionCommandContextActions> <- commandActions(context)
    forkWith(actions, ForkRequest{entryId, position})

def navigateTreeWith(actions: Maybe<&2, ExtensionCommandContextActions>, request: NavigateTreeRequest) -> IO(SessionChange):
  match actions:
    case None{}: IO.pure(SessionChange, notCancelled())
    case Some{ExtensionCommandContextActions{_, _, _, callback, _, _}}: C.call(NavigateTreeRequest, SessionChange, callback, request)

def navigateTree(context: ExtensionCommandContext, request: NavigateTreeRequest) -> IO(SessionChange):
  do IO<SessionChange>:
    actions : Maybe<&2, ExtensionCommandContextActions> <- commandActions(context)
    navigateTreeWith(actions, request)

def switchSessionWith(actions: Maybe<&2, ExtensionCommandContextActions>, request: SwitchSessionRequest) -> IO(SessionChange):
  match actions:
    case None{}: IO.pure(SessionChange, notCancelled())
    case Some{ExtensionCommandContextActions{_, _, _, _, callback, _}}: C.call(SwitchSessionRequest, SessionChange, callback, request)

def switchSession(context: ExtensionCommandContext, sessionPath: String) -> IO(SessionChange):
  do IO<SessionChange>:
    actions : Maybe<&2, ExtensionCommandContextActions> <- commandActions(context)
    switchSessionWith(actions, SwitchSessionRequest{sessionPath})

def reloadWith(actions: Maybe<&2, ExtensionCommandContextActions>) -> IO(Unit):
  match actions:
    case None{}: IO.pure(Unit, Unit{})
    case Some{ExtensionCommandContextActions{_, _, _, _, _, callback}}: C.call(Unit, Unit, callback, Unit{})

def reload(context: ExtensionCommandContext) -> IO(Unit):
  do IO<Unit>:
    actions : Maybe<&2, ExtensionCommandContextActions> <- commandActions(context)
    reloadWith(actions)

# The built-in tools' view
# ------------------------

# What a built-in tool reads from its context when it runs (upstream
# wrapToolDefinition's ctx: cwd, model, session identity, thinking level).
type ContextView is Data:
  ContextView{cwd: String, model: Maybe<&2, Ai.Model<Ai.JsonValue>>, sessionId: String, sessionFile: Maybe<&2, String>, thinkingLevel: Ai.ModelThinkingLevel}

# Tools are created with the runner's context, or without one (upstream's
# missing ctxFactory); `create` is the latter.
def ContextSource() -> Data: Maybe<&2, ExtensionContext>

def create() -> IO(ContextSource()): IO.pure(ContextSource(), None{})

def viewOf(+directory: String, state: SessionState) -> ContextView:
  match state:
    case SessionState{found, _, level, id, file, _, _, _, _}: ContextView{directory, found, id, file, level}

def viewFrom(+directory: String, session: Maybe<&2, ExtensionContextActions>) -> IO(Maybe<&2, ContextView>):
  match session:
    case None{}: IO.pure(Maybe<&2, ContextView>, None{})
    case Some{ExtensionContextActions{state, _, _}}:
      do IO<Maybe<&2, ContextView>>:
        snapshot : SessionState <- C.call(Unit, SessionState, state, Unit{})
        return Some{viewOf(directory, snapshot)}

# Before a session binds the runner, tools keep their own cwd.
def current(source: ContextSource()) -> IO(Maybe<&2, ContextView>):
  match source:
    case None{}: IO.pure(Maybe<&2, ContextView>, None{})
    case Some{+context}:
      do IO<Maybe<&2, ContextView>>:
        bindings : Bindings <- bindingsOf(context)
        viewFrom(cwd(context), sessionOf(bindings))

def cwdOf(context: Maybe<&2, ContextView>) -> Maybe<&2, String>:
  match context:
    case None{}: None{}
    case Some{ContextView{directory, _, _, _, _}}: Some{directory}

# upstream `ctx?.cwd || cwd`
def cwdOr(context: Maybe<&2, ContextView>, +fallback: String) -> String:
  match context:
    case Some{ContextView{SCon{first, rest}, _, _, _, _}}: SCon{first, rest}
    case _: fallback
