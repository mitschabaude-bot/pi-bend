import Base
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/record.bend as Rec
import ../../../../runtime/src/ref.bend as R
import ../diagnostics.bend as D
import ../model-runtime.bend as Models
import ./context.bend as Ctx
import ./loader.bend as Loader
import ./types.bend as T
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/schema-value.bend as V
import ../messages.bend as Messages
import ../tools/index.bend as Tools

# upstream core/extensions/runner.ts: the loaded extensions of one runtime,
# what they are bound to (session, command actions, UI and mode), command
# resolution, error listeners and event dispatch. Handlers run in
# registration order over a snapshot taken when dispatch starts.

type ErrorListener is Data:
  ErrorListener{id: Nat, listener: C.Callback<T.ExtensionError, Unit>}

type Listeners is Data:
  Listeners{next: Nat, listeners: List<&2, ErrorListener>}

type ExtensionRunner is Data:
  ExtensionRunner{runtime: T.ExtensionRuntime(), cwd: String, models: Models.ModelRuntime, bindings: R.Ref<Ctx.Bindings>, listeners: R.Ref<Listeners>}

# The runner owns the extension runtime from here on.
def create(runtime: T.ExtensionRuntime(), cwd: String, models: Models.ModelRuntime) -> IO(ExtensionRunner):
  do IO<ExtensionRunner>:
    bindings : R.Ref<Ctx.Bindings> <- R.new(Ctx.Bindings, Ctx.unbound())
    listeners : R.Ref<Listeners> <- R.new(Listeners, Listeners{0n, Nil{}})
    return ExtensionRunner{runtime, cwd, models, bindings, listeners}

# Whoever bound callbacks or listeners unbinds and disposes them; the
# extensions' own registrations live as long as the program.
def dispose(runner: ExtensionRunner) -> IO(Unit):
  match runner:
    case ExtensionRunner{runtime, _, _, bindings, listeners}:
      do IO<Unit>:
        state : T.ExtensionRuntimeState <- R.dispose(T.ExtensionRuntimeState, runtime)
        bound : Ctx.Bindings <- R.dispose(Ctx.Bindings, bindings)
        registered : Listeners <- R.dispose(Listeners, listeners)
        return Unit{}

def runtimeOf(runner: ExtensionRunner) -> T.ExtensionRuntime():
  match runner:
    case ExtensionRunner{runtime, _, _, _, _}: runtime

def modelsOf(runner: ExtensionRunner) -> Models.ModelRuntime:
  match runner:
    case ExtensionRunner{_, _, models, _, _}: models

def bindingsRef(runner: ExtensionRunner) -> R.Ref<Ctx.Bindings>:
  match runner:
    case ExtensionRunner{_, _, _, bindings, _}: bindings

# upstream createContext and createCommandContext.
def createContext(runner: ExtensionRunner) -> Ctx.ExtensionContext:
  match runner:
    case ExtensionRunner{_, cwd, models, bindings, _}: Ctx.ExtensionContext{cwd, models, bindings}

def createCommandContext(runner: ExtensionRunner) -> Ctx.ExtensionCommandContext:
  Ctx.ExtensionCommandContext{createContext(runner)}

def extensions(runner: ExtensionRunner) -> IO(List<&2, T.Extension>):
  do IO<List<&2, T.Extension>>:
    state : T.ExtensionRuntimeState <- R.read(T.ExtensionRuntimeState, runtimeOf(runner))
    return Loader.activeExtensions(Loader.extensionsOf(state))

def pathsOf(extensions: List<&2, T.Extension>) -> List<&2, String>:
  match extensions:
    case Nil{}: Nil{}
    case extension <> rest: Loader.extensionPath(extension) <> pathsOf(rest)

def getExtensionPaths(runner: ExtensionRunner) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    loaded : List<&2, T.Extension> <- extensions(runner)
    return pathsOf(loaded)

# Errors
# ------

type ErrorSubscription is Data:
  ErrorSubscription{id: Nat}

def withListener(listeners: Listeners, listener: C.Callback<T.ExtensionError, Unit>) -> Listeners & Nat:
  match listeners:
    case Listeners{+next, registered}: (Listeners{Nat.add(next, 1n), List.append(&2, ErrorListener, registered, [ErrorListener{next, listener}])}, next)

# upstream onError: the listener stays with its owner, who removes it with
# the returned subscription before disposing it.
def onError(runner: ExtensionRunner, listener: C.Callback<T.ExtensionError, Unit>) -> IO(ErrorSubscription):
  match runner:
    case ExtensionRunner{_, _, _, _, listeners}:
      do IO<ErrorSubscription>:
        id : Nat <- R.modify(Listeners, Nat, listeners, current => withListener(current, listener))
        return ErrorSubscription{id}

def listenerId(listener: ErrorListener) -> Nat:
  match listener:
    case ErrorListener{id, _}: id

def withoutListener(listeners: List<&2, ErrorListener>, +id: Nat) -> List<&2, ErrorListener>:
  match listeners:
    case Nil{}: Nil{}
    case +listener <> rest:
      +tail = withoutListener(rest, id)
      Bool.pick(List<&2, ErrorListener>, Nat.is_eq(listenerId(listener), id), tail, listener <> tail)

def removedListener(listeners: Listeners, +id: Nat) -> Listeners:
  match listeners:
    case Listeners{next, registered}: Listeners{next, withoutListener(registered, id)}

def offError(runner: ExtensionRunner, subscription: ErrorSubscription) -> IO(Unit):
  match runner subscription:
    case ExtensionRunner{_, _, _, _, listeners} ErrorSubscription{+id}: R.modify(Listeners, Unit, listeners, current => (removedListener(current, id), Unit{}))

def notifyListeners(listeners: List<&2, ErrorListener>, +error: T.ExtensionError) -> IO(Unit):
  match listeners:
    case Nil{}: IO.pure(Unit, Unit{})
    case ErrorListener{_, listener} <> rest:
      do IO<Unit>:
        C.call(T.ExtensionError, Unit, listener, error)
        notifyListeners(rest, error)

def registeredListeners(listeners: Listeners) -> List<&2, ErrorListener>:
  match listeners:
    case Listeners{_, registered}: registered

def emitError(runner: ExtensionRunner, error: T.ExtensionError) -> IO(Unit):
  match runner:
    case ExtensionRunner{_, _, _, _, listeners}:
      do IO<Unit>:
        current : Listeners <- R.read(Listeners, listeners)
        notifyListeners(registeredListeners(current), error)

def emitErrors(+runner: ExtensionRunner, errors: List<&2, T.ExtensionError>) -> IO(Unit):
  match errors:
    case Nil{}: IO.pure(Unit, Unit{})
    case error <> rest:
      do IO<Unit>:
        emitError(runner, error)
        emitErrors(runner, rest)

# Binding (upstream bindCore, bindCommandContext and setUIContext)
# ----------------------------------------------------------------

def withSession(bindings: Ctx.Bindings, session: Maybe<&2, Ctx.ExtensionContextActions>) -> Ctx.Bindings:
  match bindings:
    case Ctx.Bindings{ui, mode, _, commands}: Ctx.Bindings{ui, mode, session, commands}

def withCommands(bindings: Ctx.Bindings, commands: Maybe<&2, Ctx.ExtensionCommandContextActions>) -> Ctx.Bindings:
  match bindings:
    case Ctx.Bindings{ui, mode, session, _}: Ctx.Bindings{ui, mode, session, commands}

def withUI(bindings: Ctx.Bindings, ui: Maybe<&2, Ctx.ExtensionUIContext>, mode: Ctx.ExtensionMode) -> Ctx.Bindings:
  match bindings:
    case Ctx.Bindings{_, _, session, commands}: Ctx.Bindings{ui, mode, session, commands}

# upstream bindCore: the session's context actions and what follows a
# provider change (upstream's providerActions refresh the session's current
# model); provider registrations still queued reach the model runtime (a
# rejected one is an extension error). None unbinds the session before its
# callbacks are disposed.
def bindCore(+runner: ExtensionRunner, actions: Maybe<&2, Ctx.ExtensionContextActions>, providersChanged: Maybe<&2, C.Callback<Unit, Unit>>) -> IO(Unit):
  do IO<Unit>:
    R.modify(Ctx.Bindings, Unit, bindingsRef(runner), current => (withSession(current, actions), Unit{}))
    errors : List<&2, T.ExtensionError> <- Loader.bindProviders(runtimeOf(runner), modelsOf(runner), providersChanged)
    emitErrors(runner, errors)

# upstream bindCommandContext; None restores the defaults (nothing to wait
# for, session changes not cancelled).
def bindCommandContext(runner: ExtensionRunner, actions: Maybe<&2, Ctx.ExtensionCommandContextActions>) -> IO(Unit):
  R.modify(Ctx.Bindings, Unit, bindingsRef(runner), current => (withCommands(current, actions), Unit{}))

# upstream setUIContext(uiContext?, mode = "print").
def setUIContext(runner: ExtensionRunner, ui: Maybe<&2, Ctx.ExtensionUIContext>, mode: Ctx.ExtensionMode) -> IO(Unit):
  R.modify(Ctx.Bindings, Unit, bindingsRef(runner), current => (withUI(current, ui, mode), Unit{}))

def hasUI(runner: ExtensionRunner) -> IO(Bool): Ctx.hasUI(createContext(runner))

# Commands
# --------

def commandsOf(extensions: List<&2, T.Extension>) -> List<&2, T.RegisteredCommand>:
  match extensions:
    case Nil{}: Nil{}
    case T.Extension{_, _, _, _, _, _, commands, _, _} <> rest: List.append(&2, T.RegisteredCommand, commands, commandsOf(rest))

def counted(commands: List<&2, T.RegisteredCommand>, +counts: Rec.Record<Nat>) -> Rec.Record<Nat>:
  match commands:
    case Nil{}: counts
    case command <> rest:
      +name = Loader.commandName(command)
      counted(rest, Rec.set(Nat, counts, name, Nat.add(Maybe.default(&2, Nat, Rec.get(Nat, counts, name), 0n), 1n)))

def containsName(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: String.eq(first, name) || containsName(rest, name)

def suffixed(+name: String, suffix: Nat) -> String: name ++ ":" ++ Nat.show(suffix)

# upstream's do-while: the first free `name:n` above the occurrence. `fuel`
# bounds the search by the number of taken names.
def freeSuffix(fuel: Nat, +name: String, +suffix: Nat, +taken: List<&2, String>) -> String:
  match fuel:
    case 0n: suffixed(name, Nat.add(suffix, 1n))
    case 1n+rest:
      +next = Nat.add(suffix, 1n)
      Bool.pick(Unit -> String, containsName(taken, suffixed(name, next)), _ => freeSuffix(rest, name, next, taken), _ => suffixed(name, next))(Unit{})

def invocationFor(+name: String, +occurrence: Nat, count: Nat, +taken: List<&2, String>) -> String:
  +preferred = Bool.pick(String, Nat.is_gt(count, 1n), suffixed(name, occurrence), name)
  Bool.pick(Unit -> String, containsName(taken, preferred), _ => freeSuffix(List.length(&2, String, taken), name, occurrence, taken), _ => preferred)(Unit{})

def resolvedAs(command: T.RegisteredCommand, invocationName: String) -> T.ResolvedCommand:
  match command:
    case T.RegisteredCommand{name, info, description, completions, handler}: T.ResolvedCommand{name, invocationName, info, description, completions, handler}

def resolving(commands: List<&2, T.RegisteredCommand>, +counts: Rec.Record<Nat>, +seen: Rec.Record<Nat>, +taken: List<&2, String>) -> List<&2, T.ResolvedCommand>:
  match commands:
    case Nil{}: Nil{}
    case +command <> rest:
      +name = Loader.commandName(command)
      +occurrence = Nat.add(Maybe.default(&2, Nat, Rec.get(Nat, seen, name), 0n), 1n)
      +invocation = invocationFor(name, occurrence, Maybe.default(&2, Nat, Rec.get(Nat, counts, name), 0n), taken)
      resolvedAs(command, invocation) <> resolving(rest, counts, Rec.set(Nat, seen, name, occurrence), invocation <> taken)

# upstream resolveRegisteredCommands: every extension command in load and
# registration order; a name registered by several extensions is invoked as
# `name:n` by occurrence, skipping invocation names already taken.
def resolveRegisteredCommands(+commands: List<&2, T.RegisteredCommand>) -> List<&2, T.ResolvedCommand>:
  resolving(commands, counted(commands, Rec.new(Nat)), Rec.new(Nat), Nil{})

def getRegisteredCommands(runner: ExtensionRunner) -> IO(List<&2, T.ResolvedCommand>):
  do IO<List<&2, T.ResolvedCommand>>:
    loaded : List<&2, T.Extension> <- extensions(runner)
    return resolveRegisteredCommands(commandsOf(loaded))

# upstream getCommandDiagnostics: resolution renames conflicting commands
# rather than reporting them, so the list stays empty.
def getCommandDiagnostics(runner: ExtensionRunner) -> List<&2, D.ResourceDiagnostic>: Nil{}

def invocationName(command: T.ResolvedCommand) -> String:
  match command:
    case T.ResolvedCommand{_, invocation, _, _, _, _}: invocation

def findInvocation(commands: List<&2, T.ResolvedCommand>, +name: String) -> Maybe<&2, T.ResolvedCommand>:
  match commands:
    case Nil{}: None{}
    case +command <> rest: Bool.pick(Maybe<&2, T.ResolvedCommand>, String.eq(invocationName(command), name), Some{command}, findInvocation(rest, name))

def getCommand(runner: ExtensionRunner, name: String) -> IO(Maybe<&2, T.ResolvedCommand>):
  do IO<Maybe<&2, T.ResolvedCommand>>:
    commands : List<&2, T.ResolvedCommand> <- getRegisteredCommands(runner)
    return findInvocation(commands, name)

# Events
# ------

def subscribedTo(handlers: List<&2, T.Subscription>, +eventType: String) -> List<&2, T.EventHandler>:
  match handlers:
    case Nil{}: Nil{}
    case T.Subscription{_, +handler} <> rest:
      +tail = subscribedTo(rest, eventType)
      Bool.pick(List<&2, T.EventHandler>, String.eq(T.handlerEventType(handler), eventType), handler <> tail, tail)

type Dispatch is Data:
  Dispatch{extensionPath: String, handler: T.EventHandler}

def dispatchesOf(+path: String, handlers: List<&2, T.EventHandler>) -> List<&2, Dispatch>:
  match handlers:
    case Nil{}: Nil{}
    case handler <> rest: Dispatch{path, handler} <> dispatchesOf(path, rest)

# upstream snapshotEventHandlers: the handlers registered when dispatch
# starts, by extension in load order.
def snapshotEventHandlers(extensions: List<&2, T.Extension>, +eventType: String) -> List<&2, Dispatch>:
  match extensions:
    case Nil{}: Nil{}
    case T.Extension{_, path, _, _, _, handlers, _, _, _} <> rest: List.append(&2, Dispatch, dispatchesOf(path, subscribedTo(handlers, eventType)), snapshotEventHandlers(rest, eventType))

def hasHandlers(runner: ExtensionRunner, eventType: String) -> IO(Bool):
  do IO<Bool>:
    loaded : List<&2, T.Extension> <- extensions(runner)
    return Bool.not(List.is_empty(&2, Dispatch, snapshotEventHandlers(loaded, eventType)))

def ignored(result: Result<&2, &2, String, Maybe<&2, Unit>>) -> Result<&2, &2, String, Unit>:
  Result.map(&2, &2, String, Maybe<&2, Unit>, Unit, _ => Unit{}, result)

def called(-E: Data, callback: T.ExtensionHandler(E, Unit), event: E, ctx: Ctx.ExtensionContext) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    result : Result<&2, &2, String, Maybe<&2, Unit>> <- C.call(T.HandlerCall<E>, Result<&2, &2, String, Maybe<&2, Unit>>, callback, T.HandlerCall{event, ctx})
    return ignored(result)

# The snapshot holds only handlers of the event's type; another pairing
# cannot occur.
def handled(handler: T.EventHandler, event: T.ExtensionEvent, ctx: Ctx.ExtensionContext) -> IO(Result<&2, &2, String, Unit>):
  match handler event:
    case T.OnAgentStart{callback} T.AgentStart{value}: called(T.AgentStartEvent, callback, value, ctx)
    case T.OnAgentEnd{callback} T.AgentEnd{value}: called(T.AgentEndEvent, callback, value, ctx)
    case T.OnAgentSettled{callback} T.AgentSettled{value}: called(T.AgentSettledEvent, callback, value, ctx)
    case T.OnTurnStart{callback} T.TurnStart{value}: called(T.TurnStartEvent, callback, value, ctx)
    case T.OnMessageStart{callback} T.MessageStart{value}: called(T.MessageStartEvent, callback, value, ctx)
    case T.OnMessageUpdate{callback} T.MessageUpdate{value}: called(T.MessageUpdateEvent, callback, value, ctx)
    case T.OnToolExecutionStart{callback} T.ToolExecutionStart{value}: called(T.ToolExecutionStartEvent, callback, value, ctx)
    case T.OnToolExecutionUpdate{callback} T.ToolExecutionUpdate{value}: called(T.ToolExecutionUpdateEvent, callback, value, ctx)
    case T.OnToolExecutionEnd{callback} T.ToolExecutionEnd{value}: called(T.ToolExecutionEndEvent, callback, value, ctx)
    case T.OnSessionTree{callback} T.SessionTree{value}: called(T.SessionTreeEvent, callback, value, ctx)
    case T.OnSessionCompact{callback} T.SessionCompact{value}: called(T.SessionCompactEvent, callback, value, ctx)
    case T.OnSessionCompactFailed{callback} T.SessionCompactFailed{value}: called(T.SessionCompactFailedEvent, callback, value, ctx)
    case _ _: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})

def reported(+runner: ExtensionRunner, path: String, eventType: String, result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{error}: emitError(runner, T.ExtensionError{path, eventType, error, None{}})

# A failing handler is reported to the error listeners and dispatch goes on.
def dispatchAll(+runner: ExtensionRunner, dispatches: List<&2, Dispatch>, +event: T.ExtensionEvent) -> IO(Unit):
  match dispatches:
    case Nil{}: IO.pure(Unit, Unit{})
    case Dispatch{path, handler} <> rest:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- handled(handler, event, createContext(runner))
        reported(runner, path, T.eventType(event), result)
        dispatchAll(runner, rest, event)

# upstream emit for events without results. Handlers registered or removed
# during dispatch take effect from the next dispatch.
def emit(+runner: ExtensionRunner, +event: T.ExtensionEvent) -> IO(Unit):
  do IO<Unit>:
    loaded : List<&2, T.Extension> <- extensions(runner)
    dispatchAll(runner, snapshotEventHandlers(loaded, T.eventType(event)), event)

def snapshot(runner: ExtensionRunner, +eventType: String) -> IO(List<&2, Dispatch>):
  do IO<List<&2, Dispatch>>:
    loaded : List<&2, T.Extension> <- extensions(runner)
    return snapshotEventHandlers(loaded, eventType)

# message_end
# -----------

def roleOf(message: T.AgentMessage()) -> String:
  match message:
    case Agent.LlmMessage{Ai.System{_}}: "system"
    case Agent.LlmMessage{Ai.User{_}}: "user"
    case Agent.LlmMessage{Ai.Assistant{_}}: "assistant"
    case Agent.LlmMessage{Ai.ToolResult{_}}: "toolResult"
    case Agent.CustomMessage{Messages.BashExecution{_}}: "bashExecution"
    case Agent.CustomMessage{Messages.Custom{_}}: "custom"
    case Agent.CustomMessage{Messages.BranchSummary{_}}: "branchSummary"
    case Agent.CustomMessage{Messages.CompactionSummary{_}}: "compactionSummary"

type Replacing is Data:
  Replacing{message: T.AgentMessage(), modified: Bool}

def replacedBy(+runner: ExtensionRunner, path: String, +current: T.AgentMessage(), result: Result<&2, &2, String, Maybe<&2, T.MessageEndEventResult>>) -> IO(Replacing):
  match result:
    case Fail{error}:
      do IO<Replacing>:
        emitError(runner, T.ExtensionError{path, "message_end", error, None{}})
        return Replacing{current, False{}}
    case Done{Some{T.MessageEndEventResult{Some{+replacement}}}}:
      Bool.pick(Unit -> IO(Replacing), String.eq(roleOf(replacement), roleOf(current)), _ => IO.pure(Replacing, Replacing{replacement, True{}}), _ => IO.bind(Unit, Replacing, emitError(runner, T.ExtensionError{path, "message_end", "message_end handlers must return a message with the same role", None{}}), _ => IO.pure(Replacing, Replacing{current, False{}})))(Unit{})
    case Done{_}: IO.pure(Replacing, Replacing{current, False{}})

def replacingMessage(value: Replacing) -> T.AgentMessage():
  match value:
    case Replacing{message, _}: message

def replacingChanged(value: Replacing) -> Bool:
  match value:
    case Replacing{_, changed}: changed

def endMessages(+runner: ExtensionRunner, dispatches: List<&2, Dispatch>, +current: T.AgentMessage(), +modified: Bool) -> IO(Replacing):
  match dispatches:
    case Nil{}: IO.pure(Replacing, Replacing{current, modified})
    case Dispatch{path, T.OnMessageEnd{callback}} <> rest:
      do IO<Replacing>:
        result : Result<&2, &2, String, Maybe<&2, T.MessageEndEventResult>> <- C.call(T.HandlerCall<T.MessageEndEvent>, Result<&2, &2, String, Maybe<&2, T.MessageEndEventResult>>, callback, T.HandlerCall{T.MessageEndEvent{current}, createContext(runner)})
        +next : Replacing <- replacedBy(runner, path, current, result)
        endMessages(runner, rest, replacingMessage(next), modified || replacingChanged(next))
    case _ <> rest: endMessages(runner, rest, current, modified)

def replacementOf(result: Replacing) -> Maybe<&2, T.AgentMessage()>:
  match result:
    case Replacing{message, True{}}: Some{message}
    case Replacing{_, False{}}: None{}

# upstream emitMessageEnd: each handler sees the message as replaced so far;
# a replacement with another role is reported and ignored. The replacement,
# when any handler made one.
def emitMessageEnd(+runner: ExtensionRunner, event: T.MessageEndEvent) -> IO(Maybe<&2, T.AgentMessage()>):
  match event:
    case T.MessageEndEvent{message}:
      do IO<Maybe<&2, T.AgentMessage()>>:
        dispatches : List<&2, Dispatch> <- snapshot(runner, "message_end")
        result : Replacing <- endMessages(runner, dispatches, message, False{})
        return replacementOf(result)

# tool_call
# ---------

def blocks(result: Maybe<&2, T.ToolCallEventResult>) -> Bool:
  match result:
    case Some{T.ToolCallEventResult{Some{True{}}, _, _}}: True{}
    case _: False{}

def latestResult(found: Maybe<&2, T.ToolCallEventResult>, previous: Maybe<&2, T.ToolCallEventResult>) -> Maybe<&2, T.ToolCallEventResult>:
  match found:
    case Some{value}: Some{value}
    case None{}: previous

def callFailed(called: Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>) -> Bool:
  match called:
    case Fail{_}: True{}
    case Done{_}: False{}

def callFound(called: Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>) -> Maybe<&2, T.ToolCallEventResult>:
  match called:
    case Fail{_}: None{}
    case Done{found}: found

def callTools(+runner: ExtensionRunner, dispatches: List<&2, Dispatch>, +event: T.ToolCallEvent, +result: Maybe<&2, T.ToolCallEventResult>) -> IO(Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>):
  match dispatches:
    case Nil{}: IO.pure(Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>, Done{result})
    case Dispatch{_, T.OnToolCall{callback}} <> rest:
      do IO<Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>>:
        +called : Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>> <- C.call(T.HandlerCall<T.ToolCallEvent>, Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>, callback, T.HandlerCall{event, createContext(runner)})
        +latest : Maybe<&2, T.ToolCallEventResult> = latestResult(callFound(called), result)
        Bool.pick(Unit -> IO(Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>), callFailed(called) || blocks(callFound(called)), _ => IO.pure(Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>, Bool.pick(Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>, callFailed(called), called, Done{latest})), _ => callTools(runner, rest, event, latest))(Unit{})
    case _ <> rest: callTools(runner, rest, event, result)

# upstream emitToolCall: the first blocking result wins; otherwise the last
# result. A failing handler is not caught: its message blocks the call.
def emitToolCall(+runner: ExtensionRunner, event: T.ToolCallEvent) -> IO(Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>):
  do IO<Result<&2, &2, String, Maybe<&2, T.ToolCallEventResult>>>:
    dispatches : List<&2, Dispatch> <- snapshot(runner, "tool_call")
    callTools(runner, dispatches, event, None{})

# tool_result
# -----------

type ResultPatch is Data:
  ResultPatch{event: T.ToolResultEvent, modified: Bool}

def orKeep(-A: Data, found: Maybe<&2, A>, current: A) -> A:
  match found:
    case Some{value}: value
    case None{}: current

def orKeepMaybe(-A: Data, found: Maybe<&2, A>, current: Maybe<&2, A>) -> Maybe<&2, A>:
  match found:
    case Some{value}: Some{value}
    case None{}: current

def anySet(result: T.ToolResultEventResult) -> Bool:
  match result:
    case T.ToolResultEventResult{content, details, isError, usage}: Bool.not(Maybe.is_none(&2, List<&2, Ai.TextImageContent>, content)) || Bool.not(Maybe.is_none(&2, Tools.ToolDetails, details)) || Bool.not(Maybe.is_none(&2, Bool, isError)) || Bool.not(Maybe.is_none(&2, Ai.Usage, usage))

def patched(event: T.ToolResultEvent, +result: T.ToolResultEventResult) -> T.ToolResultEvent:
  match event result:
    case T.ToolResultEvent{id, name, input, content, details, isError, usage} T.ToolResultEventResult{newContent, newDetails, newIsError, newUsage}:
      T.ToolResultEvent{id, name, input, orKeep(List<&2, Ai.TextImageContent>, newContent, content), orKeepMaybe(Tools.ToolDetails, newDetails, details), orKeep(Bool, newIsError, isError), orKeepMaybe(Ai.Usage, newUsage, usage)}

def patchedBy(+runner: ExtensionRunner, path: String, +patch: ResultPatch, result: Result<&2, &2, String, Maybe<&2, T.ToolResultEventResult>>) -> IO(ResultPatch):
  match patch result:
    case _ Fail{error}:
      do IO<ResultPatch>:
        emitError(runner, T.ExtensionError{path, "tool_result", error, None{}})
        return patch
    case ResultPatch{event, modified} Done{Some{+found}}: IO.pure(ResultPatch, ResultPatch{patched(event, found), modified || anySet(found)})
    case _ Done{None{}}: IO.pure(ResultPatch, patch)

def eventOfPatch(patch: ResultPatch) -> T.ToolResultEvent:
  match patch:
    case ResultPatch{event, _}: event

def resultTools(+runner: ExtensionRunner, dispatches: List<&2, Dispatch>, +patch: ResultPatch) -> IO(ResultPatch):
  match dispatches:
    case Nil{}: IO.pure(ResultPatch, patch)
    case Dispatch{path, T.OnToolResult{callback}} <> rest:
      do IO<ResultPatch>:
        result : Result<&2, &2, String, Maybe<&2, T.ToolResultEventResult>> <- C.call(T.HandlerCall<T.ToolResultEvent>, Result<&2, &2, String, Maybe<&2, T.ToolResultEventResult>>, callback, T.HandlerCall{eventOfPatch(patch), createContext(runner)})
        next : ResultPatch <- patchedBy(runner, path, patch, result)
        resultTools(runner, rest, next)
    case _ <> rest: resultTools(runner, rest, patch)

def patchResult(patch: ResultPatch) -> Maybe<&2, T.ToolResultEventResult>:
  match patch:
    case ResultPatch{T.ToolResultEvent{_, _, _, content, details, isError, usage}, True{}}: Some{T.ToolResultEventResult{Some{content}, details, Some{isError}, usage}}
    case ResultPatch{_, False{}}: None{}

# upstream emitToolResult: handlers see the result as patched so far; a
# failing handler is reported and skipped. The patched fields, when any
# handler set one.
def emitToolResult(+runner: ExtensionRunner, event: T.ToolResultEvent) -> IO(Maybe<&2, T.ToolResultEventResult>):
  do IO<Maybe<&2, T.ToolResultEventResult>>:
    dispatches : List<&2, Dispatch> <- snapshot(runner, "tool_result")
    result : ResultPatch <- resultTools(runner, dispatches, ResultPatch{event, False{}})
    return patchResult(result)

# session_before_* (upstream emit's SessionBeforeEvent results)
# -------------------------------------------------------------
# The last result a handler returned; a result with `cancel` stops dispatch.
# A failing handler is reported and skipped.

def treeCancels(result: Maybe<&2, T.SessionBeforeTreeResult>) -> Bool:
  match result:
    case Some{T.SessionBeforeTreeResult{Some{True{}}, _, _, _, _}}: True{}
    case _: False{}

def treeResultOf(+runner: ExtensionRunner, path: String, result: Result<&2, &2, String, Maybe<&2, T.SessionBeforeTreeResult>>, previous: Maybe<&2, T.SessionBeforeTreeResult>) -> IO(Maybe<&2, T.SessionBeforeTreeResult>):
  match result:
    case Fail{error}:
      do IO<Maybe<&2, T.SessionBeforeTreeResult>>:
        emitError(runner, T.ExtensionError{path, "session_before_tree", error, None{}})
        return previous
    case Done{None{}}: IO.pure(Maybe<&2, T.SessionBeforeTreeResult>, previous)
    case Done{Some{found}}: IO.pure(Maybe<&2, T.SessionBeforeTreeResult>, Some{found})

def beforeTree(+runner: ExtensionRunner, dispatches: List<&2, Dispatch>, +event: T.SessionBeforeTreeEvent, result: Maybe<&2, T.SessionBeforeTreeResult>) -> IO(Maybe<&2, T.SessionBeforeTreeResult>):
  match dispatches:
    case Nil{}: IO.pure(Maybe<&2, T.SessionBeforeTreeResult>, result)
    case Dispatch{path, T.OnSessionBeforeTree{callback}} <> rest:
      do IO<Maybe<&2, T.SessionBeforeTreeResult>>:
        called : Result<&2, &2, String, Maybe<&2, T.SessionBeforeTreeResult>> <- C.call(T.HandlerCall<T.SessionBeforeTreeEvent>, Result<&2, &2, String, Maybe<&2, T.SessionBeforeTreeResult>>, callback, T.HandlerCall{event, createContext(runner)})
        +next : Maybe<&2, T.SessionBeforeTreeResult> <- treeResultOf(runner, path, called, result)
        Bool.pick(Unit -> IO(Maybe<&2, T.SessionBeforeTreeResult>), treeCancels(next), _ => IO.pure(Maybe<&2, T.SessionBeforeTreeResult>, next), _ => beforeTree(runner, rest, event, next))(Unit{})
    case _ <> rest: beforeTree(runner, rest, event, result)

def emitSessionBeforeTree(+runner: ExtensionRunner, event: T.SessionBeforeTreeEvent) -> IO(Maybe<&2, T.SessionBeforeTreeResult>):
  do IO<Maybe<&2, T.SessionBeforeTreeResult>>:
    dispatches : List<&2, Dispatch> <- snapshot(runner, "session_before_tree")
    beforeTree(runner, dispatches, event, None{})

def compactCancels(result: Maybe<&2, T.SessionBeforeCompactResult>) -> Bool:
  match result:
    case Some{T.SessionBeforeCompactResult{Some{True{}}, _}}: True{}
    case _: False{}

def compactResultOf(+runner: ExtensionRunner, path: String, result: Result<&2, &2, String, Maybe<&2, T.SessionBeforeCompactResult>>, previous: Maybe<&2, T.SessionBeforeCompactResult>) -> IO(Maybe<&2, T.SessionBeforeCompactResult>):
  match result:
    case Fail{error}:
      do IO<Maybe<&2, T.SessionBeforeCompactResult>>:
        emitError(runner, T.ExtensionError{path, "session_before_compact", error, None{}})
        return previous
    case Done{None{}}: IO.pure(Maybe<&2, T.SessionBeforeCompactResult>, previous)
    case Done{Some{found}}: IO.pure(Maybe<&2, T.SessionBeforeCompactResult>, Some{found})

def beforeCompact(+runner: ExtensionRunner, dispatches: List<&2, Dispatch>, +event: T.SessionBeforeCompactEvent, result: Maybe<&2, T.SessionBeforeCompactResult>) -> IO(Maybe<&2, T.SessionBeforeCompactResult>):
  match dispatches:
    case Nil{}: IO.pure(Maybe<&2, T.SessionBeforeCompactResult>, result)
    case Dispatch{path, T.OnSessionBeforeCompact{callback}} <> rest:
      do IO<Maybe<&2, T.SessionBeforeCompactResult>>:
        called : Result<&2, &2, String, Maybe<&2, T.SessionBeforeCompactResult>> <- C.call(T.HandlerCall<T.SessionBeforeCompactEvent>, Result<&2, &2, String, Maybe<&2, T.SessionBeforeCompactResult>>, callback, T.HandlerCall{event, createContext(runner)})
        +next : Maybe<&2, T.SessionBeforeCompactResult> <- compactResultOf(runner, path, called, result)
        Bool.pick(Unit -> IO(Maybe<&2, T.SessionBeforeCompactResult>), compactCancels(next), _ => IO.pure(Maybe<&2, T.SessionBeforeCompactResult>, next), _ => beforeCompact(runner, rest, event, next))(Unit{})
    case _ <> rest: beforeCompact(runner, rest, event, result)

def emitSessionBeforeCompact(+runner: ExtensionRunner, event: T.SessionBeforeCompactEvent) -> IO(Maybe<&2, T.SessionBeforeCompactResult>):
  do IO<Maybe<&2, T.SessionBeforeCompactResult>>:
    dispatches : List<&2, Dispatch> <- snapshot(runner, "session_before_compact")
    beforeCompact(runner, dispatches, event, None{})


# Boundaries (upstream emitBoundary)
# ----------------------------------
# Each turn_end or agent_before_settle handler sees the drafts and decision
# so far with a preview of the context they produce; after each handler the
# preview is rebuilt. Drafts the preview rejects are reported and make the
# result invalid (no drafts, no continuation).

type BoundaryDispatchResult is Data:
  BoundaryDispatchResult{entries: List<&2, T.SessionBoundaryDraft>, continue: Bool, context: T.BoundaryContextPreview, valid: Bool}

def BoundaryPreview() -> Data: C.Callback<List<&2, T.SessionBoundaryDraft>, Result<&2, &2, String, T.BoundaryContextPreview>>

def boundaryType(base: T.BoundaryBase) -> String:
  match base:
    case T.TurnEndBase{_, _, _, _, _, _}: "turn_end"
    case T.BeforeSettleBase{_}: "agent_before_settle"

def callBoundary(handler: T.EventHandler, base: T.BoundaryBase, entries: List<&2, T.SessionBoundaryDraft>, continued: Bool, context: T.BoundaryContextPreview, ctx: Ctx.ExtensionContext) -> IO(Result<&2, &2, String, Maybe<&2, T.BoundaryResult>>):
  match handler base:
    case T.OnTurnEnd{callback} T.TurnEndBase{turnIndex, message, toolResults, messageEntryId, toolResultEntryIds, outcome}: C.call(T.HandlerCall<T.TurnEndEvent>, Result<&2, &2, String, Maybe<&2, T.BoundaryResult>>, callback, T.HandlerCall{T.TurnEndEvent{turnIndex, message, toolResults, messageEntryId, toolResultEntryIds, entries, continued, context, outcome}, ctx})
    case T.OnAgentBeforeSettle{callback} T.BeforeSettleBase{outcome}: C.call(T.HandlerCall<T.AgentBeforeSettleEvent>, Result<&2, &2, String, Maybe<&2, T.BoundaryResult>>, callback, T.HandlerCall{T.AgentBeforeSettleEvent{entries, continued, context, outcome}, ctx})
    case _ _: IO.pure(Result<&2, &2, String, Maybe<&2, T.BoundaryResult>>, Done{None{}})

type BoundaryState is Data:
  BoundaryState{entries: List<&2, T.SessionBoundaryDraft>, continue: Bool, context: T.BoundaryContextPreview, valid: Bool}

def draftsAfter(result: Result<&2, &2, String, Maybe<&2, T.BoundaryResult>>, previous: List<&2, T.SessionBoundaryDraft>) -> List<&2, T.SessionBoundaryDraft>:
  match result:
    case Done{Some{T.BoundaryResult{Some{entries}, _}}}: entries
    case _: previous

def continueAfter(result: Result<&2, &2, String, Maybe<&2, T.BoundaryResult>>, previous: Bool) -> Bool:
  match result:
    case Done{Some{T.BoundaryResult{_, Some{value}}}}: value
    case _: previous

def handlerFailed(+runner: ExtensionRunner, path: String, eventType: String, result: Result<&2, &2, String, Maybe<&2, T.BoundaryResult>>) -> IO(Unit):
  match result:
    case Fail{error}: emitError(runner, T.ExtensionError{path, eventType, error, None{}})
    case Done{_}: IO.pure(Unit, Unit{})

def previewed(+runner: ExtensionRunner, path: String, eventType: String, +entries: List<&2, T.SessionBoundaryDraft>, continued: Bool, previous: T.BoundaryContextPreview, built: Result<&2, &2, String, T.BoundaryContextPreview>) -> IO(BoundaryState):
  match built:
    case Done{context}: IO.pure(BoundaryState, BoundaryState{entries, continued, context, True{}})
    case Fail{error}:
      do IO<BoundaryState>:
        emitError(runner, T.ExtensionError{path, eventType, "Invalid boundary entries: " ++ error, None{}})
        return BoundaryState{entries, continued, previous, False{}}

def boundaryStep(+runner: ExtensionRunner, +path: String, +handler: T.EventHandler, +base: T.BoundaryBase, +build: BoundaryPreview(), state: BoundaryState) -> IO(BoundaryState):
  match state:
    case BoundaryState{+entries, +continued, +context, _}:
      do IO<BoundaryState>:
        +result : Result<&2, &2, String, Maybe<&2, T.BoundaryResult>> <- callBoundary(handler, base, entries, continued, context, createContext(runner))
        handlerFailed(runner, path, boundaryType(base), result)
        +drafts : List<&2, T.SessionBoundaryDraft> = draftsAfter(result, entries)
        built : Result<&2, &2, String, T.BoundaryContextPreview> <- C.call(List<&2, T.SessionBoundaryDraft>, Result<&2, &2, String, T.BoundaryContextPreview>, build, drafts)
        previewed(runner, path, boundaryType(base), drafts, continueAfter(result, continued), context, built)

def boundaryDispatches(+runner: ExtensionRunner, dispatches: List<&2, Dispatch>, +base: T.BoundaryBase, +build: BoundaryPreview(), state: BoundaryState) -> IO(BoundaryState):
  match dispatches:
    case Nil{}: IO.pure(BoundaryState, state)
    case Dispatch{path, handler} <> rest:
      do IO<BoundaryState>:
        next : BoundaryState <- boundaryStep(runner, path, handler, base, build, state)
        boundaryDispatches(runner, rest, base, build, next)

def boundaryResult(state: BoundaryState) -> BoundaryDispatchResult:
  match state:
    case BoundaryState{entries, continued, context, True{}}: BoundaryDispatchResult{entries, continued, context, True{}}
    case BoundaryState{_, _, context, False{}}: BoundaryDispatchResult{Nil{}, False{}, context, False{}}

def emitBoundary(+runner: ExtensionRunner, +base: T.BoundaryBase, +build: BoundaryPreview(), initial: T.BoundaryContextPreview) -> IO(BoundaryDispatchResult):
  do IO<BoundaryDispatchResult>:
    dispatches : List<&2, Dispatch> <- snapshot(runner, boundaryType(base))
    final : BoundaryState <- boundaryDispatches(runner, dispatches, base, build, BoundaryState{Nil{}, False{}, initial, True{}})
    return boundaryResult(final)
