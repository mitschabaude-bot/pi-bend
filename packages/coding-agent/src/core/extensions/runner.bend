import Base
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/record.bend as Rec
import ../../../../runtime/src/ref.bend as R
import ../diagnostics.bend as D
import ../model-runtime.bend as Models
import ./context.bend as Ctx
import ./loader.bend as Loader
import ./types.bend as T

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

def handled(handler: T.EventHandler, event: T.ExtensionEvent, ctx: Ctx.ExtensionContext) -> IO(Result<&2, &2, String, Unit>):
  match handler event:
    case T.OnAgentEnd{callback} T.AgentEnd{value}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, String, Maybe<&2, Unit>> <- C.call(T.HandlerCall<T.AgentEndEvent>, Result<&2, &2, String, Maybe<&2, Unit>>, callback, T.HandlerCall{value, ctx})
        return Result.map(&2, &2, String, Maybe<&2, Unit>, Unit, _ => Unit{}, result)

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
