import Base
import ../../../../ai/src/models.bend as AiModels
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/ref.bend as R
import ../model-runtime.bend as Models
import ../skills.bend as Skills
import ./types.bend as T

# The part of upstream core/extensions/loader.ts that remains without a
# module loader: the shared extension runtime (createExtensionRuntime), the
# ExtensionAPI an extension's factory registers through (createExtensionAPI)
# and loading inline factories (loadExtensionFromFactory, as the resource
# loader's loadExtensionFactories calls it). Registering is a state
# transition of the runtime's immutable ExtensionRuntimeState.

def createExtensionRuntime() -> IO(T.ExtensionRuntime()):
  R.new(T.ExtensionRuntimeState, T.ExtensionRuntimeState{Nil{}, Nil{}, None{}, 0n})

def firstSegment(parts: List<&2, String>) -> String:
  match parts:
    case Nil{}: "temporary"
    case SNil{} <> _: "temporary"
    case first <> _: first

# upstream createExtension's source for a `<source:name>` path.
def syntheticSource(+path: String) -> String:
  firstSegment(String.split(String.take(String.drop(path, 1n), Nat.sub(String.length(path), 2n)), ':'))

# upstream createSyntheticSourceInfo(path, { source }).
def createSourceInfo(+path: String) -> Skills.SourceInfo:
  Skills.SourceInfo{path, syntheticSource(path), Skills.Temporary{}, Skills.TopLevel{}, None{}}

# Extension state
# ---------------

def inactiveMessage(path: String) -> String:
  "Extension \"" ++ path ++ "\" failed to load and its API is no longer active."

def extensionId(extension: T.Extension) -> Nat:
  match extension:
    case T.Extension{id, _, _, _, _, _, _, _, _}: id

def extensionPath(extension: T.Extension) -> String:
  match extension:
    case T.Extension{_, path, _, _, _, _, _, _, _}: path

def isFailed(extension: T.Extension) -> Bool:
  match extension:
    case T.Extension{_, _, _, _, _, _, _, T.Failed{}, _}: True{}
    case _: False{}

def isLoading(extension: T.Extension) -> Bool:
  match extension:
    case T.Extension{_, _, _, _, _, _, _, T.Loading{}, _}: True{}
    case _: False{}

def isActive(extension: T.Extension) -> Bool:
  match extension:
    case T.Extension{_, _, _, _, _, _, _, T.Active{}, _}: True{}
    case _: False{}

# upstream's extension list: extensions that loaded.
def activeExtensions(extensions: List<&2, T.Extension>) -> List<&2, T.Extension>:
  match extensions:
    case Nil{}: Nil{}
    case +extension <> rest:
      +tail = activeExtensions(rest)
      Bool.pick(List<&2, T.Extension>, isActive(extension), extension <> tail, tail)

def findExtension(extensions: List<&2, T.Extension>, +id: Nat) -> Maybe<&2, T.Extension>:
  match extensions:
    case Nil{}: None{}
    case +extension <> rest: Bool.pick(Maybe<&2, T.Extension>, Nat.is_eq(extensionId(extension), id), Some{extension}, findExtension(rest, id))

def replaceExtension(extensions: List<&2, T.Extension>, +extension: T.Extension) -> List<&2, T.Extension>:
  match extensions:
    case Nil{}: Nil{}
    case +current <> rest: Bool.pick(T.Extension, Nat.is_eq(extensionId(current), extensionId(extension)), extension, current) <> replaceExtension(rest, extension)

def extensionsOf(state: T.ExtensionRuntimeState) -> List<&2, T.Extension>:
  match state:
    case T.ExtensionRuntimeState{extensions, _, _, _}: extensions

def withExtension(state: T.ExtensionRuntimeState, +extension: T.Extension) -> T.ExtensionRuntimeState:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, models, next}: T.ExtensionRuntimeState{replaceExtension(extensions, extension), pending, models, next}

def missingMessage(id: Nat) -> String: "Extension runtime has no extension " ++ Nat.show(id)

# upstream assertActive for the API of one extension: a failed extension's
# API no longer registers anything.
def checked(+id: Nat, found: Maybe<&2, T.Extension>) -> Result<&2, &2, String, T.Extension>:
  match found:
    case None{}: Fail{missingMessage(id)}
    case Some{+extension}: Bool.pick(Result<&2, &2, String, T.Extension>, isFailed(extension), Fail{inactiveMessage(extensionPath(extension))}, Done{extension})

def extensionIn(state: T.ExtensionRuntimeState, +id: Nat) -> Result<&2, &2, String, T.Extension>:
  checked(id, findExtension(extensionsOf(state), id))

def updateWith(+state: T.ExtensionRuntimeState, update: T.Extension -> T.Extension, found: Result<&2, &2, String, T.Extension>) -> T.ExtensionRuntimeState & Result<&2, &2, String, Unit>:
  match found:
    case Fail{error}: (state, Fail{error})
    case Done{extension}: (withExtension(state, update(extension)), Done{Unit{}})

def updateExtension(+id: Nat, update: T.Extension -> T.Extension, +state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Result<&2, &2, String, Unit>:
  updateWith(state, update, extensionIn(state, id))

def modifyExtension(api: T.ExtensionAPI, update: T.Extension -> T.Extension) -> IO(Result<&2, &2, String, Unit>):
  match api:
    case T.ExtensionAPI{runtime, +id}: R.modify(T.ExtensionRuntimeState, Result<&2, &2, String, Unit>, runtime, state => updateExtension(id, update, state))

# ExtensionAPI (upstream createExtensionAPI)
# -----------------------------------------

def commandName(command: T.RegisteredCommand) -> String:
  match command:
    case T.RegisteredCommand{name, _, _, _, _}: name

def missingCommand(commands: List<&2, T.RegisteredCommand>, +name: String) -> Bool:
  match commands:
    case Nil{}: True{}
    case command <> rest: Bool.not(String.eq(commandName(command), name)) && missingCommand(rest, name)

def replacedCommand(commands: List<&2, T.RegisteredCommand>, +command: T.RegisteredCommand) -> List<&2, T.RegisteredCommand>:
  match commands:
    case Nil{}: Nil{}
    case +current <> rest: Bool.pick(T.RegisteredCommand, String.eq(commandName(current), commandName(command)), command, current) <> replacedCommand(rest, command)

# Map.set: a name registered again keeps its position.
def setCommand(+commands: List<&2, T.RegisteredCommand>, +command: T.RegisteredCommand) -> List<&2, T.RegisteredCommand>:
  Bool.pick(List<&2, T.RegisteredCommand>, missingCommand(commands, commandName(command)), List.append(&2, T.RegisteredCommand, commands, [command]), replacedCommand(commands, command))

def withCommand(+name: String, options: T.CommandOptions, extension: T.Extension) -> T.Extension:
  match options extension:
    case T.CommandOptions{description, completions, handler} T.Extension{id, path, resolved, hidden, +info, handlers, commands, state, changes}:
      T.Extension{id, path, resolved, hidden, info, handlers, setCommand(commands, T.RegisteredCommand{name, info, description, completions, handler}), state, changes}

# upstream registerCommand(name, options): the command carries the
# extension's source info.
def registerCommand(api: T.ExtensionAPI, name: String, options: T.CommandOptions) -> IO(Result<&2, &2, String, Unit>):
  modifyExtension(api, extension => withCommand(name, options, extension))

def withSubscription(subscription: T.Subscription, extension: T.Extension) -> T.Extension:
  match extension:
    case T.Extension{id, path, resolved, hidden, info, handlers, commands, state, changes}:
      T.Extension{id, path, resolved, hidden, info, List.append(&2, T.Subscription, handlers, [subscription]), commands, state, changes}

def subscriptionId(subscription: T.Subscription) -> Nat:
  match subscription:
    case T.Subscription{id, _}: id

def withoutSubscription(handlers: List<&2, T.Subscription>, +id: Nat) -> List<&2, T.Subscription>:
  match handlers:
    case Nil{}: Nil{}
    case +subscription <> rest:
      +tail = withoutSubscription(rest, id)
      Bool.pick(List<&2, T.Subscription>, Nat.is_eq(subscriptionId(subscription), id), tail, subscription <> tail)

def unsubscribed(+id: Nat, extension: T.Extension) -> T.Extension:
  match extension:
    case T.Extension{owner, path, resolved, hidden, info, handlers, commands, state, changes}:
      T.Extension{owner, path, resolved, hidden, info, withoutSubscription(handlers, id), commands, state, changes}

# What `on` returns: removing the handler it registered.
type Unsubscribe is Data:
  Unsubscribe{api: T.ExtensionAPI, id: Nat}

def subscribedResult(+next: Nat, pair: T.ExtensionRuntimeState & Result<&2, &2, String, Unit>) -> T.ExtensionRuntimeState & Result<&2, &2, String, Nat>:
  match pair:
    case (updated, Fail{error}): (updated, Fail{error})
    case (updated, Done{_}): (updated, Done{next})

def subscribed(+id: Nat, handler: T.EventHandler, state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Result<&2, &2, String, Nat>:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, models, +next}:
      subscribedResult(next, updateExtension(id, extension => withSubscription(T.Subscription{next, handler}, extension), T.ExtensionRuntimeState{extensions, pending, models, Nat.add(next, 1n)}))

def unsubscribeOf(+api: T.ExtensionAPI, result: Result<&2, &2, String, Nat>) -> Result<&2, &2, String, Unsubscribe>:
  match result:
    case Fail{error}: Fail{error}
    case Done{id}: Done{Unsubscribe{api, id}}

# upstream on(event, handler): handlers run in registration order; the
# returned unsubscribe removes this registration only.
def on(+api: T.ExtensionAPI, handler: T.EventHandler) -> IO(Result<&2, &2, String, Unsubscribe>):
  match api:
    case T.ExtensionAPI{runtime, +id}:
      do IO<Result<&2, &2, String, Unsubscribe>>:
        result : Result<&2, &2, String, Nat> <- R.modify(T.ExtensionRuntimeState, Result<&2, &2, String, Nat>, runtime, state => subscribed(id, handler, state))
        return unsubscribeOf(api, result)

# Removing an already removed handler does nothing.
def unsubscribe(value: Unsubscribe) -> IO(Unit):
  match value:
    case Unsubscribe{api, +id}:
      do IO<Unit>:
        result : Result<&2, &2, String, Unit> <- modifyExtension(api, extension => unsubscribed(id, extension))
        return Unit{}

# Providers
# ---------

def withChange(change: T.ProviderChange, extension: T.Extension) -> T.Extension:
  match extension:
    case T.Extension{id, path, resolved, hidden, info, handlers, commands, state, changes}:
      T.Extension{id, path, resolved, hidden, info, handlers, commands, state, List.append(&2, T.ProviderChange, changes, [change])}

def providerIdOf(provider: AiModels.Provider) -> String:
  match provider:
    case AiModels.Provider{id, _, _, _, _, _, _}: id

def withoutPending(pending: List<&2, T.PendingProvider>, +name: String) -> List<&2, T.PendingProvider>:
  match pending:
    case Nil{}: Nil{}
    case T.PendingProvider{+provider, path} <> rest:
      +tail = withoutPending(rest, name)
      Bool.pick(List<&2, T.PendingProvider>, String.eq(providerIdOf(provider), name), tail, T.PendingProvider{provider, path} <> tail)

# How a provider change takes effect in the current runtime state.
type Effect is Data:
  NoEffect{}
  Deferred{}
  RegisterNow{binding: T.ProviderBinding, provider: AiModels.Provider}
  UnregisterNow{binding: T.ProviderBinding, name: String}
  Rejected{error: String}

# Before the runtime is bound to the model runtime, registrations queue and
# an unregistration drops the queued ones (upstream createExtensionRuntime).
def appliedChange(change: T.ProviderChange, +path: String, state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Effect:
  match change state:
    case T.RegisterProvider{provider} T.ExtensionRuntimeState{extensions, pending, None{}, next}: (T.ExtensionRuntimeState{extensions, List.append(&2, T.PendingProvider, pending, [T.PendingProvider{provider, path}]), None{}, next}, NoEffect{})
    case T.UnregisterProvider{name} T.ExtensionRuntimeState{extensions, pending, None{}, next}: (T.ExtensionRuntimeState{extensions, withoutPending(pending, name), None{}, next}, NoEffect{})
    case T.RegisterProvider{provider} T.ExtensionRuntimeState{extensions, pending, Some{+binding}, next}: (T.ExtensionRuntimeState{extensions, pending, Some{binding}, next}, RegisterNow{binding, provider})
    case T.UnregisterProvider{name} T.ExtensionRuntimeState{extensions, pending, Some{+binding}, next}: (T.ExtensionRuntimeState{extensions, pending, Some{binding}, next}, UnregisterNow{binding, name})

def notifyChanged(changed: Maybe<&2, C.Callback<Unit, Unit>>) -> IO(Unit):
  match changed:
    case None{}: IO.pure(Unit, Unit{})
    case Some{callback}: C.call(Unit, Unit, callback, Unit{})

def registeredWith(binding: T.ProviderBinding, provider: AiModels.Provider) -> IO(Result<&2, &2, String, Unit>):
  match binding:
    case T.ProviderBinding{models, changed}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, String, Unit> <- Models.registerNativeProvider(models, provider)
        notifyChanged(changed)
        return result

def unregisteredWith(binding: T.ProviderBinding, name: String) -> IO(Result<&2, &2, String, Unit>):
  match binding:
    case T.ProviderBinding{models, changed}:
      do IO<Result<&2, &2, String, Unit>>:
        Models.unregisterProvider(models, name)
        notifyChanged(changed)
        return Done{Unit{}}

def performed(effect: Effect) -> IO(Result<&2, &2, String, Unit>):
  match effect:
    case NoEffect{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Deferred{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Rejected{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case RegisterNow{binding, provider}: registeredWith(binding, provider)
    case UnregisterNow{binding, name}: unregisteredWith(binding, name)

def deferredOr(loading: Bool, change: T.ProviderChange, +state: T.ExtensionRuntimeState, +extension: T.Extension) -> T.ExtensionRuntimeState & Effect:
  match loading:
    case True{}: (withExtension(state, withChange(change, extension)), Deferred{})
    case False{}: appliedChange(change, extensionPath(extension), state)

def effectFor(change: T.ProviderChange, +state: T.ExtensionRuntimeState, found: Result<&2, &2, String, T.Extension>) -> T.ExtensionRuntimeState & Effect:
  match found:
    case Fail{error}: (state, Rejected{error})
    case Done{+extension}: deferredOr(isLoading(extension), change, state, extension)

def changeEffect(+id: Nat, change: T.ProviderChange, +state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Effect:
  effectFor(change, state, extensionIn(state, id))

def applyChange(api: T.ExtensionAPI, change: T.ProviderChange) -> IO(Result<&2, &2, String, Unit>):
  match api:
    case T.ExtensionAPI{runtime, +id}:
      do IO<Result<&2, &2, String, Unit>>:
        effect : Effect <- R.modify(T.ExtensionRuntimeState, Effect, runtime, state => changeEffect(id, change, state))
        performed(effect)

# upstream registerProvider(provider): while the extension loads, the change
# waits for it to finish; then it queues until the model runtime is bound,
# and afterwards takes effect immediately.
def registerProvider(api: T.ExtensionAPI, provider: AiModels.Provider) -> IO(Result<&2, &2, String, Unit>):
  applyChange(api, T.RegisterProvider{provider})

def unregisterProvider(api: T.ExtensionAPI, name: String) -> IO(Result<&2, &2, String, Unit>):
  applyChange(api, T.UnregisterProvider{name})

# Loading (upstream initializeExtension and loadExtensionFactories)
# ----------------------------------------------------------------

def added(+path: String, hidden: Bool, state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Nat:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, models, +next}:
      (T.ExtensionRuntimeState{List.append(&2, T.Extension, extensions, [T.Extension{next, path, path, hidden, createSourceInfo(path), Nil{}, Nil{}, T.Loading{}, Nil{}}]), pending, models, Nat.add(next, 1n)}, next)

def withState(extension: T.Extension, state: T.LoadState) -> T.Extension & List<&2, T.ProviderChange>:
  match extension:
    case T.Extension{id, path, resolved, hidden, info, handlers, commands, _, changes}: (T.Extension{id, path, resolved, hidden, info, handlers, commands, state, Nil{}}, changes)

def storedSettled(state: T.ExtensionRuntimeState, pair: T.Extension & List<&2, T.ProviderChange>) -> T.ExtensionRuntimeState & List<&2, T.ProviderChange>:
  match pair:
    case (extension, changes): (withExtension(state, extension), changes)

def settledWith(+state: T.ExtensionRuntimeState, outcome: T.LoadState, found: Maybe<&2, T.Extension>) -> T.ExtensionRuntimeState & List<&2, T.ProviderChange>:
  match found:
    case None{}: (state, Nil{})
    case Some{extension}: storedSettled(state, withState(extension, outcome))

def settled(+id: Nat, outcome: T.LoadState, +state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & List<&2, T.ProviderChange>:
  settledWith(state, outcome, findExtension(extensionsOf(state), id))

def applyChanges(+api: T.ExtensionAPI, changes: List<&2, T.ProviderChange>) -> IO(Result<&2, &2, String, Unit>):
  match changes:
    case Nil{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case change <> rest:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, String, Unit> <- applyChange(api, change)
        applyChanges(api, rest)

# A loaded extension becomes active and its deferred provider changes apply
# in order (upstream commit); a failed one is discarded with them.
def finishLoad(+api: T.ExtensionAPI, outcome: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match api outcome:
    case T.ExtensionAPI{runtime, +id} Fail{error}:
      do IO<Result<&2, &2, String, Unit>>:
        dropped : List<&2, T.ProviderChange> <- R.modify(T.ExtensionRuntimeState, List<&2, T.ProviderChange>, runtime, state => settled(id, T.Failed{}, state))
        return Fail{error}
    case T.ExtensionAPI{runtime, +id} Done{_}:
      do IO<Result<&2, &2, String, Unit>>:
        changes : List<&2, T.ProviderChange> <- R.modify(T.ExtensionRuntimeState, List<&2, T.ProviderChange>, runtime, state => settled(id, T.Active{}, state))
        applied : Result<&2, &2, String, Unit> <- applyChanges(T.ExtensionAPI{runtime, id}, changes)
        return Done{Unit{}}

# upstream loadExtensionFromFactory with path `<inline:name>`.
def loadExtensionFromFactory(+runtime: T.ExtensionRuntime(), factory: T.ExtensionFactory(), +path: String, hidden: Bool) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    id : Nat <- R.modify(T.ExtensionRuntimeState, Nat, runtime, state => added(path, hidden, state))
    +api : T.ExtensionAPI <- IO.pure(T.ExtensionAPI, T.ExtensionAPI{runtime, id})
    outcome : Result<&2, &2, String, Unit> <- factory(api)
    finishLoad(api, outcome)

def loadError(+path: String, result: Result<&2, &2, String, Unit>, rest: List<&2, T.LoadError>) -> List<&2, T.LoadError>:
  match result:
    case Done{_}: rest
    case Fail{error}: T.LoadError{path, error} <> rest

# upstream DefaultResourceLoader.loadExtensionFactories: each named factory
# loads as `<inline:name>` in order; failures become load errors.
def loadExtensionFactories(+runtime: T.ExtensionRuntime(), extensions: List<&1, T.InlineExtension>) -> IO(List<&2, T.LoadError>):
  match extensions:
    case Nil{}: IO.pure(List<&2, T.LoadError>, Nil{})
    case T.InlineExtension{name, factory, hidden} <> rest:
      +path = "<inline:" ++ name ++ ">"
      do IO<List<&2, T.LoadError>>:
        result : Result<&2, &2, String, Unit> <- loadExtensionFromFactory(runtime, factory, path, hidden)
        others : List<&2, T.LoadError> <- loadExtensionFactories(runtime, rest)
        return loadError(path, result, others)

# Binding to the model runtime (upstream agent-session-services)
# -------------------------------------------------------------

def taken(state: T.ExtensionRuntimeState, binding: T.ProviderBinding) -> T.ExtensionRuntimeState & List<&2, T.PendingProvider>:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, _, next}: (T.ExtensionRuntimeState{extensions, Nil{}, Some{binding}, next}, pending)

def providerError(path: String, result: Result<&2, &2, String, Unit>, others: List<&2, T.ExtensionError>) -> List<&2, T.ExtensionError>:
  match result:
    case Done{_}: others
    case Fail{error}: T.ExtensionError{path, "register_provider", error, None{}} <> others

def registeredPending(+models: Models.ModelRuntime, pending: List<&2, T.PendingProvider>) -> IO(List<&2, T.ExtensionError>):
  match pending:
    case Nil{}: IO.pure(List<&2, T.ExtensionError>, Nil{})
    case T.PendingProvider{provider, path} <> rest:
      do IO<List<&2, T.ExtensionError>>:
        result : Result<&2, &2, String, Unit> <- Models.registerNativeProvider(models, provider)
        others : List<&2, T.ExtensionError> <- registeredPending(models, rest)
        return providerError(path, result, others)

def bindingOf(state: T.ExtensionRuntimeState) -> Maybe<&2, T.ProviderBinding>:
  match state:
    case T.ExtensionRuntimeState{_, _, binding, _}: binding

def changedOf(binding: Maybe<&2, T.ProviderBinding>) -> Maybe<&2, C.Callback<Unit, Unit>>:
  match binding:
    case Some{T.ProviderBinding{_, changed}}: changed
    case None{}: None{}

def notifyIfRegistered(pending: Bool, changed: Maybe<&2, C.Callback<Unit, Unit>>) -> IO(Unit):
  match pending:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: notifyChanged(changed)

# Queued provider registrations reach the model runtime in order, and later
# ones take effect immediately; `changed` runs after each change. A rejected
# registration becomes an error for its extension.
def bindProviders(runtime: T.ExtensionRuntime(), +models: Models.ModelRuntime, +changed: Maybe<&2, C.Callback<Unit, Unit>>) -> IO(List<&2, T.ExtensionError>):
  do IO<List<&2, T.ExtensionError>>:
    +pending : List<&2, T.PendingProvider> <- R.modify(T.ExtensionRuntimeState, List<&2, T.PendingProvider>, runtime, state => taken(state, T.ProviderBinding{models, changed}))
    errors : List<&2, T.ExtensionError> <- registeredPending(models, pending)
    notifyIfRegistered(Bool.not(List.is_empty(&2, T.PendingProvider, pending)), changed)
    return errors
