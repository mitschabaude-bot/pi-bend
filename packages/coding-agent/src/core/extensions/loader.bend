import Base
import ../../../../runtime/src/record.bend as Record
import ../../../../ai/src/models.bend as AiModels
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/ref.bend as R
import ../model-runtime.bend as Models
import ../provider-composer.bend as Composer
import ../skills.bend as Skills
import ./types.bend as T
import ./context.bend as Ctx
import ./tool-context.bend as ToolContext
import ../tools/bash.bend as Bash
import ../tools/index.bend as Tools
import ../../../../agent/src/types.bend as Agent
import ../../../../runtime/src/child-process.bend as Child
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/schema-value.bend as V

# The part of upstream core/extensions/loader.ts that remains without a
# module loader: the shared extension runtime (createExtensionRuntime), the
# ExtensionAPI an extension's factory registers through (createExtensionAPI)
# and loading inline factories (loadExtensionFromFactory, as the resource
# loader's loadExtensionFactories calls it). Registering is a state
# transition of the runtime's immutable ExtensionRuntimeState.

def createExtensionRuntime() -> IO(T.ExtensionRuntime()):
  R.new(T.ExtensionRuntimeState, T.ExtensionRuntimeState{Nil{}, Nil{}, None{}, 0n, None{}, None{}, Nil{}})

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

# Build a registerable Bash definition with the same live session context as
# the built-in tool. Each execution owns its short-lived shell operations;
# the definition keeps only its options and the extension-owned callback.
type BashDefinition is Data:
  BashDefinition{cwd: String, options: Bash.BashToolOptions}

def runBashDefinitionOwned(pair: Tools.ToolOwner & Tools.Tool(), input: Tools.Input()) -> IO(Tools.Output()):
  match pair:
    case (owner,Agent.AgentTool{_,_,_,_,_,_,execute,_,_}):
      do IO<Tools.Output()>:
        result : Tools.Output() <- C.call(Tools.Input(),Tools.Output(),execute,input)
        Tools.disposeTool(owner)
        return result

def runBashDefinition(env: BashDefinition, call: T.ToolCallInput) -> IO(Tools.Output()):
  match env call:
    case BashDefinition{cwd,options} T.ToolCallInput{input,context}:
      do IO<Tools.Output()>:
        +reader : C.Callback<Unit,Maybe<&2,ToolContext.ContextView>> <- Ctx.createToolContext(context)
        owner : Bash.ToolOwner <- Bash.createBashTool("",cwd,options,Some{reader})
        bridged : Tools.ToolOwner <- Tools.bridgedBash(Bash.borrowTool(owner))
        result : Tools.Output() <- runBashDefinitionOwned(Tools.borrowTool(bridged),input)
        C.dispose(Unit,Maybe<&2,ToolContext.ContextView>,reader)
        return result

def createBashToolDefinition(+cwd: String, +options: Bash.BashToolOptions) -> IO(T.ToolDefinition):
  +guidelines = Bool.pick(List<&2,String>,Tools.exposesSessionEnvironment(Some{options}),Tools.promptGuidelines(Tools.BashTool{}),Nil{})
  do IO<T.ToolDefinition>:
    execute : T.ToolExecute() <- C.create(~BashDefinition,~T.ToolCallInput,~Tools.Output(),~runBashDefinition,BashDefinition{cwd,options})
    return T.ToolDefinition{"bash","bash",Bash.description(),Some{Tools.promptSnippet(Tools.BashTool{})},guidelines,Bash.bashSchema(),None{},execute,T.DefaultShell{},None{},None{}}

# Extension state
# ---------------

def inactiveMessage(path: String) -> String:
  "Extension \"" ++ path ++ "\" failed to load and its API is no longer active."

def extensionId(extension: T.Extension) -> Nat:
  match extension:
    case T.Extension{id, _, _, _, _, _, _, _, _, _, _}: id

def extensionPath(extension: T.Extension) -> String:
  match extension:
    case T.Extension{_, path, _, _, _, _, _, _, _, _, _}: path

def isFailed(extension: T.Extension) -> Bool:
  match extension:
    case T.Extension{_, _, _, _, _, _, _, T.Failed{}, _, _, _}: True{}
    case _: False{}

def isLoading(extension: T.Extension) -> Bool:
  match extension:
    case T.Extension{_, _, _, _, _, _, _, T.Loading{}, _, _, _}: True{}
    case _: False{}

def isActive(extension: T.Extension) -> Bool:
  match extension:
    case T.Extension{_, _, _, _, _, _, _, T.Active{}, _, _, _}: True{}
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
    case T.ExtensionRuntimeState{extensions, _, _, _, actions, runtimeCwd, flagValues}: extensions

def withExtension(state: T.ExtensionRuntimeState, +extension: T.Extension) -> T.ExtensionRuntimeState:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, models, next, actions, runtimeCwd, flagValues}: T.ExtensionRuntimeState{replaceExtension(extensions, extension), pending, models, next, actions, runtimeCwd, flagValues}

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
    case T.CommandOptions{description, completions, handler} T.Extension{id, path, resolved, hidden, +info, handlers, commands, state, changes, tools, extras}:
      T.Extension{id, path, resolved, hidden, info, handlers, setCommand(commands, T.RegisteredCommand{name, info, description, completions, handler}), state, changes, tools, extras}

# upstream registerCommand(name, options): the command carries the
# extension's source info.
def registerCommand(api: T.ExtensionAPI, name: String, options: T.CommandOptions) -> IO(Result<&2, &2, String, Unit>):
  modifyExtension(api, extension => withCommand(name, options, extension))

def toolNameOf(definition: T.ToolDefinition) -> String:
  match definition:
    case T.ToolDefinition{name, _, _, _, _, _, _, _, _, _, _}: name

def definedTool(tools: List<&2, T.ToolDefinition>, +definition: T.ToolDefinition) -> List<&2, T.ToolDefinition>:
  match tools:
    case Nil{}: [definition]
    case +existing <> +rest: Bool.pick(List<&2, T.ToolDefinition>, String.eq(toolNameOf(existing), toolNameOf(definition)), definition <> rest, existing <> definedTool(rest, definition))

def withTool(definition: T.ToolDefinition, extension: T.Extension) -> T.Extension:
  match extension:
    case T.Extension{id, path, resolved, hidden, info, handlers, commands, state, changes, tools, extras}:
      T.Extension{id, path, resolved, hidden, info, handlers, commands, state, changes, definedTool(tools, definition), extras}

def withSubscription(subscription: T.Subscription, extension: T.Extension) -> T.Extension:
  match extension:
    case T.Extension{id, path, resolved, hidden, info, handlers, commands, state, changes, tools, extras}:
      T.Extension{id, path, resolved, hidden, info, List.append(&2, T.Subscription, handlers, [subscription]), commands, state, changes, tools, extras}

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
    case T.Extension{owner, path, resolved, hidden, info, handlers, commands, state, changes, tools, extras}:
      T.Extension{owner, path, resolved, hidden, info, withoutSubscription(handlers, id), commands, state, changes, tools, extras}

# What `on` returns: removing the handler it registered.
type Unsubscribe is Data:
  Unsubscribe{api: T.ExtensionAPI, id: Nat}

def subscribedResult(+next: Nat, pair: T.ExtensionRuntimeState & Result<&2, &2, String, Unit>) -> T.ExtensionRuntimeState & Result<&2, &2, String, Nat>:
  match pair:
    case (updated, Fail{error}): (updated, Fail{error})
    case (updated, Done{_}): (updated, Done{next})

def subscribed(+id: Nat, handler: T.EventHandler, state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Result<&2, &2, String, Nat>:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, models, +next, actions, runtimeCwd, flagValues}:
      subscribedResult(next, updateExtension(id, extension => withSubscription(T.Subscription{next, handler}, extension), T.ExtensionRuntimeState{extensions, pending, models, Nat.add(next, 1n), actions, runtimeCwd, flagValues}))

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
    case T.Extension{id, path, resolved, hidden, info, handlers, commands, state, changes, tools, extras}:
      T.Extension{id, path, resolved, hidden, info, handlers, commands, state, List.append(&2, T.ProviderChange, changes, [change]), tools, extras}

def providerIdOf(provider: AiModels.Provider) -> String:
  match provider:
    case AiModels.Provider{id, _, _, _, _, _, _, _}: id

# The provider id a registration is for.
def registrationId(registration: T.ProviderRegistration) -> String:
  match registration:
    case T.NativeRegistration{provider, _}: providerIdOf(provider)
    case T.ConfigRegistration{name, _}: name

def withoutPending(pending: List<&2, T.PendingProvider>, +name: String) -> List<&2, T.PendingProvider>:
  match pending:
    case Nil{}: Nil{}
    case T.PendingProvider{+registration, path} <> rest:
      +tail = withoutPending(rest, name)
      Bool.pick(List<&2, T.PendingProvider>, String.eq(registrationId(registration), name), tail, T.PendingProvider{registration, path} <> tail)

# How a provider change takes effect in the current runtime state.
type Effect is Data:
  NoEffect{}
  Deferred{}
  RegisterNow{binding: T.ProviderBinding, registration: T.ProviderRegistration}
  UnregisterNow{binding: T.ProviderBinding, name: String}
  Rejected{error: String}

# Before the runtime is bound to the model runtime, registrations queue and
# an unregistration drops the queued ones (upstream createExtensionRuntime).
def appliedChange(change: T.ProviderChange, +path: String, state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Effect:
  match change state:
    case T.RegisterProvider{registration} T.ExtensionRuntimeState{extensions, pending, None{}, next, actions, runtimeCwd, flagValues}: (T.ExtensionRuntimeState{extensions, List.append(&2, T.PendingProvider, pending, [T.PendingProvider{registration, path}]), None{}, next, actions, runtimeCwd, flagValues}, NoEffect{})
    case T.UnregisterProvider{name} T.ExtensionRuntimeState{extensions, pending, None{}, next, actions, runtimeCwd, flagValues}: (T.ExtensionRuntimeState{extensions, withoutPending(pending, name), None{}, next, actions, runtimeCwd, flagValues}, NoEffect{})
    case T.RegisterProvider{registration} T.ExtensionRuntimeState{extensions, pending, Some{+binding}, next, actions, runtimeCwd, flagValues}: (T.ExtensionRuntimeState{extensions, pending, Some{binding}, next, actions, runtimeCwd, flagValues}, RegisterNow{binding, registration})
    case T.UnregisterProvider{name} T.ExtensionRuntimeState{extensions, pending, Some{+binding}, next, actions, runtimeCwd, flagValues}: (T.ExtensionRuntimeState{extensions, pending, Some{binding}, next, actions, runtimeCwd, flagValues}, UnregisterNow{binding, name})

def notifyChanged(changed: Maybe<&2, C.Callback<Unit, Unit>>) -> IO(Unit):
  match changed:
    case None{}: IO.pure(Unit, Unit{})
    case Some{callback}: C.call(Unit, Unit, callback, Unit{})

# upstream ModelRuntime.registerNativeProvider or registerProvider(name,
# config), by the registration's form.
def registerWith(+models: Models.ModelRuntime, registration: T.ProviderRegistration) -> IO(Result<&2, &2, String, Unit>):
  match registration:
    case T.NativeRegistration{provider, stream}: Models.registerNativeProviderStream(models, provider, stream)
    case T.ConfigRegistration{name, config}: Models.registerProvider(models, name, config)

def registeredWith(binding: T.ProviderBinding, registration: T.ProviderRegistration) -> IO(Result<&2, &2, String, Unit>):
  match binding:
    case T.ProviderBinding{models, changed}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, String, Unit> <- registerWith(models, registration)
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
    case RegisterNow{binding, registration}: registeredWith(binding, registration)
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
  applyChange(api, T.RegisterProvider{T.NativeRegistration{provider, None{}}})

# A native provider with its own streamSimple (upstream Provider.streamSimple).
def registerStreamingProvider(api: T.ExtensionAPI, provider: AiModels.Provider, stream: Composer.ProviderStream()) -> IO(Result<&2, &2, String, Unit>):
  applyChange(api, T.RegisterProvider{T.NativeRegistration{provider, Some{stream}}})

# upstream registerProvider(name, config): the config layers over the
# built-in or models.json provider of that name (a base URL override, API
# key, headers, streamSimple for its api, replacement models).
def registerProviderConfig(api: T.ExtensionAPI, name: String, config: Composer.ProviderConfigInput) -> IO(Result<&2, &2, String, Unit>):
  applyChange(api, T.RegisterProvider{T.ConfigRegistration{name, config}})

def unregisterProvider(api: T.ExtensionAPI, name: String) -> IO(Result<&2, &2, String, Unit>):
  applyChange(api, T.UnregisterProvider{name})

# Loading (upstream initializeExtension and loadExtensionFactories)
# ----------------------------------------------------------------

def added(+path: String, hidden: Bool, state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Nat:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, models, +next, actions, runtimeCwd, flagValues}:
      (T.ExtensionRuntimeState{List.append(&2, T.Extension, extensions, [T.Extension{next, path, path, hidden, createSourceInfo(path), Nil{}, Nil{}, T.Loading{}, Nil{}, Nil{}, T.noExtras()}]), pending, models, Nat.add(next, 1n), actions, runtimeCwd, flagValues}, next)

def withState(extension: T.Extension, state: T.LoadState) -> T.Extension & List<&2, T.ProviderChange>:
  match extension:
    case T.Extension{id, path, resolved, hidden, info, handlers, commands, _, changes, tools, extras}: (T.Extension{id, path, resolved, hidden, info, handlers, commands, state, Nil{}, tools, extras}, changes)

def storedSettled(state: T.ExtensionRuntimeState, pair: T.Extension & List<&2, T.ProviderChange>) -> T.ExtensionRuntimeState & List<&2, T.ProviderChange>:
  match pair:
    case (extension, changes): (withExtension(state, extension), changes)

def settledWith(+state: T.ExtensionRuntimeState, outcome: T.LoadState, found: Maybe<&2, T.Extension>) -> T.ExtensionRuntimeState & List<&2, T.ProviderChange>:
  match found:
    case None{}: (state, Nil{})
    case Some{extension}: storedSettled(state, withState(extension, outcome))

def settled(+id: Nat, outcome: T.LoadState, +state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & List<&2, T.ProviderChange>:
  settledWith(state, outcome, findExtension(extensionsOf(state), id))

# Flags (upstream registerFlag, getFlag and the commit of pending defaults)
# ------------------------------------------------------------------------

def flagName(flag: T.ExtensionFlag) -> String:
  match flag:
    case T.ExtensionFlag{name, _, _, _, _}: name

def settingName(setting: T.FlagSetting) -> String:
  match setting:
    case T.FlagSetting{name, _}: name

def hasFlag(flags: List<&2, T.ExtensionFlag>, +name: String) -> Bool:
  match flags:
    case Nil{}: False{}
    case flag <> rest: String.eq(flagName(flag), name) || hasFlag(rest, name)

# Map.set: a name registered again keeps its position.
def replacedFlag(flags: List<&2, T.ExtensionFlag>, +flag: T.ExtensionFlag) -> List<&2, T.ExtensionFlag>:
  match flags:
    case Nil{}: Nil{}
    case +current <> rest: Bool.pick(T.ExtensionFlag, String.eq(flagName(current), flagName(flag)), flag, current) <> replacedFlag(rest, flag)

def setFlag(+flags: List<&2, T.ExtensionFlag>, +flag: T.ExtensionFlag) -> List<&2, T.ExtensionFlag>:
  Bool.pick(List<&2, T.ExtensionFlag>, hasFlag(flags, flagName(flag)), replacedFlag(flags, flag), List.append(&2, T.ExtensionFlag, flags, [flag]))

def settingValue(settings: List<&2, T.FlagSetting>, +name: String) -> Maybe<&2, T.FlagValue>:
  match settings:
    case Nil{}: None{}
    case T.FlagSetting{key, value} <> rest: Bool.pick(Maybe<&2, T.FlagValue>, String.eq(key, name), Some{value}, settingValue(rest, name))

def hasSetting(settings: List<&2, T.FlagSetting>, +name: String) -> Bool: Maybe.is_some(&2, T.FlagValue, settingValue(settings, name))

def replacedSetting(settings: List<&2, T.FlagSetting>, +setting: T.FlagSetting) -> List<&2, T.FlagSetting>:
  match settings:
    case Nil{}: Nil{}
    case +current <> rest: Bool.pick(T.FlagSetting, String.eq(settingName(current), settingName(setting)), setting, current) <> replacedSetting(rest, setting)

# Map.set for flag values.
def setSetting(+settings: List<&2, T.FlagSetting>, +setting: T.FlagSetting) -> List<&2, T.FlagSetting>:
  Bool.pick(List<&2, T.FlagSetting>, hasSetting(settings, settingName(setting)), replacedSetting(settings, setting), List.append(&2, T.FlagSetting, settings, [setting]))

# Only when the name has no value yet.
def settingIfAbsent(+settings: List<&2, T.FlagSetting>, +setting: T.FlagSetting) -> List<&2, T.FlagSetting>:
  Bool.pick(List<&2, T.FlagSetting>, hasSetting(settings, settingName(setting)), settings, List.append(&2, T.FlagSetting, settings, [setting]))

def flagTypeName(kind: T.FlagType) -> String:
  match kind:
    case T.BooleanFlag{}: "boolean"
    case T.StringFlag{}: "string"

def valueTypeName(value: T.FlagValue) -> String:
  match value:
    case T.FlagBoolean{_}: "boolean"
    case T.FlagString{_}: "string"

# upstream's typeof check of a flag's default.
def defaultMismatch(+name: String, options: T.FlagOptions) -> Maybe<&2, String>:
  match options:
    case T.FlagOptions{_, +kind, Some{+value}}:
      Bool.pick(Maybe<&2, String>, String.eq(flagTypeName(kind), valueTypeName(value)), None{}, Some{"Invalid default for flag \"" ++ name ++ "\": expected " ++ flagTypeName(kind) ++ ", got " ++ valueTypeName(value)})
    case _: None{}

def extrasOf(extension: T.Extension) -> T.ExtensionExtras:
  match extension:
    case T.Extension{_, _, _, _, _, _, _, _, _, _, extras}: extras

def withExtras(extension: T.Extension, +extras: T.ExtensionExtras) -> T.Extension:
  match extension:
    case T.Extension{id, path, resolved, hidden, info, handlers, commands, state, changes, tools, _}: T.Extension{id, path, resolved, hidden, info, handlers, commands, state, changes, tools, extras}

def flagValuesOf(state: T.ExtensionRuntimeState) -> List<&2, T.FlagSetting>:
  match state:
    case T.ExtensionRuntimeState{_, _, _, _, _, _, flagValues}: flagValues

def withFlagValues(state: T.ExtensionRuntimeState, +values: List<&2, T.FlagSetting>) -> T.ExtensionRuntimeState:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, models, next, actions, runtimeCwd, _}: T.ExtensionRuntimeState{extensions, pending, models, next, actions, runtimeCwd, values}

def extrasWithPending(extras: T.ExtensionExtras, +setting: T.FlagSetting) -> T.ExtensionExtras:
  match extras:
    case T.ExtensionExtras{flags, shortcuts, pending, renderers}: T.ExtensionExtras{flags, shortcuts, settingIfAbsent(pending, setting), renderers}

def pendingDefault(+extension: T.Extension, +setting: T.FlagSetting) -> T.Extension: withExtras(extension, extrasWithPending(extrasOf(extension), setting))

# A default applies unless the name has a value: while the extension loads it
# waits for the commit, otherwise it applies at once.
def withDefault(+state: T.ExtensionRuntimeState, +extension: T.Extension, +name: String, value: Maybe<&2, T.FlagValue>) -> T.ExtensionRuntimeState:
  match value:
    case None{}: withExtension(state, extension)
    case Some{+found}:
      Bool.pick(T.ExtensionRuntimeState, hasSetting(flagValuesOf(state), name), withExtension(state, extension),
        Bool.pick(T.ExtensionRuntimeState, isLoading(extension), withExtension(state, pendingDefault(extension, T.FlagSetting{name, found})), withFlagValues(withExtension(state, extension), setSetting(flagValuesOf(state), T.FlagSetting{name, found}))))

def extrasWithFlag(extras: T.ExtensionExtras, +flag: T.ExtensionFlag) -> T.ExtensionExtras:
  match extras:
    case T.ExtensionExtras{flags, shortcuts, pending, renderers}: T.ExtensionExtras{setFlag(flags, flag), shortcuts, pending, renderers}

def flaggedExtension(+extension: T.Extension, +flag: T.ExtensionFlag) -> T.Extension: withExtras(extension, extrasWithFlag(extrasOf(extension), flag))

def flagAdded(+state: T.ExtensionRuntimeState, +name: String, options: T.FlagOptions, +extension: T.Extension) -> T.ExtensionRuntimeState & Result<&2, &2, String, Unit>:
  match options:
    case T.FlagOptions{description, kind, +value}:
      (withDefault(state, flaggedExtension(extension, T.ExtensionFlag{name, extensionPath(extension), description, kind, value}), name, value), Done{Unit{}})

def flagValidated(+state: T.ExtensionRuntimeState, +name: String, options: T.FlagOptions, +extension: T.Extension, mismatch: Maybe<&2, String>) -> T.ExtensionRuntimeState & Result<&2, &2, String, Unit>:
  match mismatch:
    case Some{error}: (state, Fail{error})
    case None{}: flagAdded(state, name, options, extension)

def flagChecked(+state: T.ExtensionRuntimeState, +name: String, +options: T.FlagOptions, found: Result<&2, &2, String, T.Extension>) -> T.ExtensionRuntimeState & Result<&2, &2, String, Unit>:
  match found:
    case Fail{error}: (state, Fail{error})
    case Done{extension}: flagValidated(state, name, options, extension, defaultMismatch(name, options))

def flagRegistered(+id: Nat, +name: String, options: T.FlagOptions, +state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Result<&2, &2, String, Unit>:
  flagChecked(state, name, options, extensionIn(state, id))

# upstream registerFlag(name, options): a default of the wrong type fails.
def registerFlag(api: T.ExtensionAPI, +name: String, options: T.FlagOptions) -> IO(Result<&2, &2, String, Unit>):
  match api:
    case T.ExtensionAPI{runtime, +id}: R.modify(T.ExtensionRuntimeState, Result<&2, &2, String, Unit>, runtime, state => flagRegistered(id, name, options, state))

def flagIn(state: T.ExtensionRuntimeState, +name: String, extras: T.ExtensionExtras) -> Maybe<&2, T.FlagValue>:
  match extras:
    case T.ExtensionExtras{flags, _, pending, _}:
      Bool.pick(Maybe<&2, T.FlagValue>, hasFlag(flags, name), Maybe.or(&2, T.FlagValue, settingValue(flagValuesOf(state), name), settingValue(pending, name)), None{})

def flagFrom(state: T.ExtensionRuntimeState, +name: String, found: Result<&2, &2, String, T.Extension>) -> Result<&2, &2, String, Maybe<&2, T.FlagValue>>:
  match found:
    case Fail{error}: Fail{error}
    case Done{extension}: Done{flagIn(state, name, extrasOf(extension))}

def flagOf(+id: Nat, +name: String, +state: T.ExtensionRuntimeState) -> Result<&2, &2, String, Maybe<&2, T.FlagValue>>: flagFrom(state, name, extensionIn(state, id))

# upstream getFlag(name): None unless this extension registered the flag;
# the runtime's value, else the default waiting for the commit.
def getFlag(api: T.ExtensionAPI, +name: String) -> IO(Result<&2, &2, String, Maybe<&2, T.FlagValue>>):
  match api:
    case T.ExtensionAPI{runtime, +id}:
      do IO<Result<&2, &2, String, Maybe<&2, T.FlagValue>>>:
        state : T.ExtensionRuntimeState <- R.read(T.ExtensionRuntimeState, runtime)
        return flagOf(id, name, state)

def settingsCommitted(pending: List<&2, T.FlagSetting>, +values: List<&2, T.FlagSetting>) -> List<&2, T.FlagSetting>:
  match pending:
    case Nil{}: values
    case setting <> rest: settingsCommitted(rest, settingIfAbsent(values, setting))

def committedFlags(+state: T.ExtensionRuntimeState, pending: List<&2, T.FlagSetting>) -> T.ExtensionRuntimeState:
  withFlagValues(state, settingsCommitted(pending, flagValuesOf(state)))

def committedExtras(+state: T.ExtensionRuntimeState, +extension: T.Extension, extras: T.ExtensionExtras) -> T.ExtensionRuntimeState & Unit:
  match extras:
    case T.ExtensionExtras{flags, shortcuts, pending, renderers}: (committedFlags(withExtension(state, withExtras(extension, T.ExtensionExtras{flags, shortcuts, Nil{}, renderers})), pending), Unit{})

def committedWith(+state: T.ExtensionRuntimeState, found: Maybe<&2, T.Extension>) -> T.ExtensionRuntimeState & Unit:
  match found:
    case None{}: (state, Unit{})
    case Some{+extension}: committedExtras(state, extension, extrasOf(extension))

# upstream commit: pending flag defaults apply where no value exists.
def committedFor(+id: Nat, +state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Unit:
  committedWith(state, findExtension(extensionsOf(state), id))

def commitFlags(runtime: T.ExtensionRuntime(), +id: Nat) -> IO(Unit):
  R.modify(T.ExtensionRuntimeState, Unit, runtime, state => committedFor(id, state))

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
        commitFlags(runtime, id)
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

# upstream DefaultResourceLoader.loadExtensionFactories: a named factory
# loads as `<inline:name>`, a bare one as `<inline:N>` (its 1-based
# position), in order; failures become load errors.
def loadFactoriesFrom(+runtime: T.ExtensionRuntime(), extensions: List<&1, T.InlineExtension>, +position: Nat) -> IO(List<&2, T.LoadError>):
  match extensions:
    case Nil{}: IO.pure(List<&2, T.LoadError>, Nil{})
    case T.InlineExtension{name, factory, hidden} <> rest:
      +path = "<inline:" ++ name ++ ">"
      do IO<List<&2, T.LoadError>>:
        result : Result<&2, &2, String, Unit> <- loadExtensionFromFactory(runtime, factory, path, hidden)
        others : List<&2, T.LoadError> <- loadFactoriesFrom(runtime, rest, position + 1n)
        return loadError(path, result, others)
    case T.BareExtension{factory} <> rest:
      +path = "<inline:" ++ Nat.show(position) ++ ">"
      do IO<List<&2, T.LoadError>>:
        result : Result<&2, &2, String, Unit> <- loadExtensionFromFactory(runtime, factory, path, False{})
        others : List<&2, T.LoadError> <- loadFactoriesFrom(runtime, rest, position + 1n)
        return loadError(path, result, others)

def loadExtensionFactories(+runtime: T.ExtensionRuntime(), extensions: List<&1, T.InlineExtension>) -> IO(List<&2, T.LoadError>):
  loadFactoriesFrom(runtime, extensions, 1n)

# Binding to the model runtime (upstream agent-session-services)
# -------------------------------------------------------------

def taken(state: T.ExtensionRuntimeState, binding: T.ProviderBinding) -> T.ExtensionRuntimeState & List<&2, T.PendingProvider>:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, _, next, actions, runtimeCwd, flagValues}: (T.ExtensionRuntimeState{extensions, Nil{}, Some{binding}, next, actions, runtimeCwd, flagValues}, pending)

def providerError(path: String, result: Result<&2, &2, String, Unit>, others: List<&2, T.ExtensionError>) -> List<&2, T.ExtensionError>:
  match result:
    case Done{_}: others
    case Fail{error}: T.ExtensionError{path, "register_provider", error, None{}} <> others

def registeredPending(+models: Models.ModelRuntime, pending: List<&2, T.PendingProvider>) -> IO(List<&2, T.ExtensionError>):
  match pending:
    case Nil{}: IO.pure(List<&2, T.ExtensionError>, Nil{})
    case T.PendingProvider{registration, path} <> rest:
      do IO<List<&2, T.ExtensionError>>:
        result : Result<&2, &2, String, Unit> <- registerWith(models, registration)
        others : List<&2, T.ExtensionError> <- registeredPending(models, rest)
        return providerError(path, result, others)

def bindingOf(state: T.ExtensionRuntimeState) -> Maybe<&2, T.ProviderBinding>:
  match state:
    case T.ExtensionRuntimeState{_, _, binding, _, actions, runtimeCwd, flagValues}: binding

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

# Session actions (upstream ExtensionAPI's action methods)
# -------------------------------------------------------

def notInitialized() -> String: "Extension runtime not initialized. Action methods cannot be called during extension loading."

def withActions(state: T.ExtensionRuntimeState, actions: Maybe<&2, T.ExtensionActions>) -> T.ExtensionRuntimeState & Unit:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, models, next, _, runtimeCwd, flagValues}: (T.ExtensionRuntimeState{extensions, pending, models, next, actions, runtimeCwd, flagValues}, Unit{})

# upstream bindCore's actions; None unbinds them before the session disposes
# its callbacks.
def bindActions(runtime: T.ExtensionRuntime(), actions: Maybe<&2, T.ExtensionActions>) -> IO(Unit):
  R.modify(T.ExtensionRuntimeState, Unit, runtime, state => withActions(state, actions))

def actionsIn(state: T.ExtensionRuntimeState) -> Maybe<&2, T.ExtensionActions>:
  match state:
    case T.ExtensionRuntimeState{_, _, _, _, actions, runtimeCwd, flagValues}: actions

# The extension must be active and the actions bound.
def checkedActions(found: Result<&2, &2, String, T.Extension>, actions: Maybe<&2, T.ExtensionActions>) -> Result<&2, &2, String, T.ExtensionActions>:
  match found actions:
    case Fail{error} _: Fail{error}
    case Done{_} None{}: Fail{notInitialized()}
    case Done{_} Some{bound}: Done{bound}

def activeActions(+state: T.ExtensionRuntimeState, +id: Nat) -> Result<&2, &2, String, T.ExtensionActions>:
  checkedActions(extensionIn(state, id), actionsIn(state))

def performedWith(found: Result<&2, &2, String, T.ExtensionActions>, act: T.ExtensionActions -> IO(Unit)) -> IO(Result<&2, &2, String, Unit>):
  match found:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{actions}:
      do IO<Result<&2, &2, String, Unit>>:
        act(actions)
        return Done{Unit{}}

def withActionsOf(api: T.ExtensionAPI, act: T.ExtensionActions -> IO(Unit)) -> IO(Result<&2, &2, String, Unit>):
  match api:
    case T.ExtensionAPI{runtime, id}:
      do IO<Result<&2, &2, String, Unit>>:
        state : T.ExtensionRuntimeState <- R.read(T.ExtensionRuntimeState, runtime)
        performedWith(activeActions(state, id), act)

def sendWith(actions: T.ExtensionActions, request: T.SendMessage) -> IO(Unit):
  match actions:
    case T.ExtensionActions{send, _, _, _, _}: C.call(T.SendMessage, Unit, send, request)

# upstream pi.sendMessage(message, options).
def sendMessage(api: T.ExtensionAPI, message: T.CustomMessageInput, options: T.SendMessageOptions) -> IO(Result<&2, &2, String, Unit>):
  withActionsOf(api, actions => sendWith(actions, T.SendMessage{message, options}))

def sendUserWith(actions: T.ExtensionActions, request: T.SendUserMessage) -> IO(Unit):
  match actions:
    case T.ExtensionActions{_, send, _, _, _}: C.call(T.SendUserMessage, Unit, send, request)

# upstream pi.sendUserMessage(content, options).
def sendUserMessage(api: T.ExtensionAPI, content: Ai.UserContent, options: T.SendUserMessageOptions) -> IO(Result<&2, &2, String, Unit>):
  withActionsOf(api, actions => sendUserWith(actions, T.SendUserMessage{content, options}))

def modelSetWith(found: Result<&2, &2, String, T.ExtensionActions>, model: Ai.Model<Ai.JsonValue>) -> IO(Result<&2, &2, String, Bool>):
  match found:
    case Fail{error}: IO.pure(Result<&2, &2, String, Bool>, Fail{error})
    case Done{T.ExtensionActions{_, _, setter, _, _}}:
      do IO<Result<&2, &2, String, Bool>>:
        changed : Bool <- C.call(Ai.Model<Ai.JsonValue>, Bool, setter, model)
        return Done{changed}

# upstream pi.setModel(model): False when the model's provider has no
# configured auth; otherwise the session switches to it.
def setModel(api: T.ExtensionAPI, model: Ai.Model<Ai.JsonValue>) -> IO(Result<&2, &2, String, Bool>):
  match api:
    case T.ExtensionAPI{runtime, id}:
      do IO<Result<&2, &2, String, Bool>>:
        state : T.ExtensionRuntimeState <- R.read(T.ExtensionRuntimeState, runtime)
        modelSetWith(activeActions(state, id), model)

def toolActionsWith(-A: Data, found: Result<&2, &2, String, T.ExtensionActions>, act: T.ToolActions -> IO(A)) -> IO(Result<&2, &2, String, A>):
  match found:
    case Fail{error}: IO.pure(Result<&2, &2, String, A>, Fail{error})
    case Done{T.ExtensionActions{_, _, _, tools, _}}:
      do IO<Result<&2, &2, String, A>>:
        value : A <- act(tools)
        return Done{value}

def withToolActions(-A: Data, api: T.ExtensionAPI, act: T.ToolActions -> IO(A)) -> IO(Result<&2, &2, String, A>):
  match api:
    case T.ExtensionAPI{runtime, id}:
      do IO<Result<&2, &2, String, A>>:
        state : T.ExtensionRuntimeState <- R.read(T.ExtensionRuntimeState, runtime)
        toolActionsWith(A, activeActions(state, id), act)

def activeToolsWith(tools: T.ToolActions) -> IO(List<&2, String>):
  match tools:
    case T.ToolActions{get, _, _, _}: C.call(Unit, List<&2, String>, get, Unit{})

def allToolsWith(tools: T.ToolActions) -> IO(List<&2, T.ToolInfo>):
  match tools:
    case T.ToolActions{_, all, _, _}: C.call(Unit, List<&2, T.ToolInfo>, all, Unit{})

def activateWith(names: List<&2, String>, tools: T.ToolActions) -> IO(Unit):
  match tools:
    case T.ToolActions{_, _, set, _}: C.call(List<&2, String>, Unit, set, names)

# upstream pi.getActiveTools / getAllTools / setActiveTools.
def getActiveTools(api: T.ExtensionAPI) -> IO(Result<&2, &2, String, List<&2, String>>):
  withToolActions(List<&2, String>, api, activeToolsWith)

def getAllTools(api: T.ExtensionAPI) -> IO(Result<&2, &2, String, List<&2, T.ToolInfo>>):
  withToolActions(List<&2, T.ToolInfo>, api, allToolsWith)

def setActiveTools(api: T.ExtensionAPI, names: List<&2, String>) -> IO(Result<&2, &2, String, Unit>):
  withToolActions(Unit, api, tools => activateWith(names, tools))

def refreshWith(actions: Maybe<&2, T.ExtensionActions>) -> IO(Unit):
  match actions:
    case None{}: IO.pure(Unit, Unit{})
    case Some{T.ExtensionActions{_, _, _, T.ToolActions{_, _, _, refresh}, _}}: C.call(Unit, Unit, refresh, Unit{})

def refreshBound(runtime: T.ExtensionRuntime()) -> IO(Unit):
  do IO<Unit>:
    state : T.ExtensionRuntimeState <- R.read(T.ExtensionRuntimeState, runtime)
    refreshWith(actionsIn(state))

# upstream pi.registerTool: the definition replaces one of the same name;
# once the session is bound its tool registry refreshes (during loading the
# session picks the tools up when it binds).
def registerTool(api: T.ExtensionAPI, definition: T.ToolDefinition) -> IO(Result<&2, &2, String, Unit>):
  match api:
    case T.ExtensionAPI{+runtime, id}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, String, Unit> <- modifyExtension(T.ExtensionAPI{runtime, id}, extension => withTool(definition, extension))
        refreshBound(runtime)
        return result

# The directory extension commands run in (upstream loader cwd), set when a
# runner is created for a session.
def withCwd(+cwd: String, state: T.ExtensionRuntimeState) -> T.ExtensionRuntimeState & Unit:
  match state:
    case T.ExtensionRuntimeState{extensions, pending, models, next, actions, _, flagValues}: (T.ExtensionRuntimeState{extensions, pending, models, next, actions, Some{cwd}, flagValues}, Unit{})

def setCwd(runtime: T.ExtensionRuntime(), +cwd: String) -> IO(Unit):
  R.modify(T.ExtensionRuntimeState, Unit, runtime, state => withCwd(cwd, state))

def cwdOf(state: T.ExtensionRuntimeState) -> String:
  match state:
    case T.ExtensionRuntimeState{_, _, _, _, _, runtimeCwd, flagValues}: Maybe.default(&2, String, runtimeCwd, ".")

# upstream ExecOptions: the directory (its timeout and abort signal are not
# ported yet).
type ExecOptions is Data:
  ExecOptions{cwd: Maybe<&2, String>}

def noExecOptions() -> ExecOptions: ExecOptions{None{}}

# upstream ExecResult.
type ExecResult is Data:
  ExecResult{stdout: String, stderr: String, code: U32, killed: Bool}

def execResult(completed: Child.Completed) -> ExecResult:
  match completed:
    case Child.Completed{Done{code}, out, err}: ExecResult{Utf8.decodeBuffer(out), Utf8.decodeBuffer(err), code, False{}}
    case Child.Completed{Fail{Child.ExecutionTimedOut{}}, out, err}: ExecResult{Utf8.decodeBuffer(out), Utf8.decodeBuffer(err), 0, True{}}
    case Child.Completed{Fail{Child.ExecutionAborted{}}, out, err}: ExecResult{Utf8.decodeBuffer(out), Utf8.decodeBuffer(err), 0, True{}}
    case Child.Completed{Fail{_}, out, err}: ExecResult{Utf8.decodeBuffer(out), Utf8.decodeBuffer(err), 1, False{}}

def execIn(+command: String, args: List<String>, +cwd: String) -> IO(ExecResult):
  do IO<ExecResult>:
    environment : List<String> <- IO.environment()
    completed : Child.Completed <- Child.spawnSync(command, args, cwd, environment, Nil{})
    return execResult(completed)

# upstream pi.exec (execCommand): the command without a shell, in the given
# cwd or the extensions' one; a failure to run it exits with code 1.
def exec(api: T.ExtensionAPI, +command: String, args: List<String>, options: ExecOptions) -> IO(ExecResult):
  match api options:
    case T.ExtensionAPI{runtime, _} ExecOptions{cwd}:
      do IO<ExecResult>:
        state : T.ExtensionRuntimeState <- R.read(T.ExtensionRuntimeState, runtime)
        execIn(command, args, Maybe.default(&2, String, cwd, cwdOf(state)))

# Shortcuts and custom entries (upstream registerShortcut, appendEntry)
# ---------------------------------------------------------------------

def shortcutKey(shortcut: T.ExtensionShortcut) -> String:
  match shortcut:
    case T.ExtensionShortcut{key, _, _, _}: key

def hasShortcut(shortcuts: List<&2, T.ExtensionShortcut>, +key: String) -> Bool:
  match shortcuts:
    case Nil{}: False{}
    case shortcut <> rest: String.eq(shortcutKey(shortcut), key) || hasShortcut(rest, key)

def replacedShortcut(shortcuts: List<&2, T.ExtensionShortcut>, +shortcut: T.ExtensionShortcut) -> List<&2, T.ExtensionShortcut>:
  match shortcuts:
    case Nil{}: Nil{}
    case +current <> rest: Bool.pick(T.ExtensionShortcut, String.eq(shortcutKey(current), shortcutKey(shortcut)), shortcut, current) <> replacedShortcut(rest, shortcut)

def setShortcut(+shortcuts: List<&2, T.ExtensionShortcut>, +shortcut: T.ExtensionShortcut) -> List<&2, T.ExtensionShortcut>:
  Bool.pick(List<&2, T.ExtensionShortcut>, hasShortcut(shortcuts, shortcutKey(shortcut)), replacedShortcut(shortcuts, shortcut), List.append(&2, T.ExtensionShortcut, shortcuts, [shortcut]))

def extrasWithShortcut(extras: T.ExtensionExtras, +shortcut: T.ExtensionShortcut) -> T.ExtensionExtras:
  match extras:
    case T.ExtensionExtras{flags, shortcuts, pending, renderers}: T.ExtensionExtras{flags, setShortcut(shortcuts, shortcut), pending, renderers}

def withShortcut(+key: String, options: T.ShortcutOptions, +extension: T.Extension) -> T.Extension:
  match options:
    case T.ShortcutOptions{description, handler}: withExtras(extension, extrasWithShortcut(extrasOf(extension), T.ExtensionShortcut{key, extensionPath(extension), description, handler}))

# upstream registerShortcut(shortcut, options).
def registerShortcut(api: T.ExtensionAPI, key: String, options: T.ShortcutOptions) -> IO(Result<&2, &2, String, Unit>):
  modifyExtension(api, extension => withShortcut(key, options, extension))

def appendWith(actions: T.ExtensionActions, request: T.AppendEntry) -> IO(Unit):
  match actions:
    case T.ExtensionActions{_, _, _, _, append}: C.call(T.AppendEntry, Unit, append, request)

# upstream appendEntry(customType, data): a custom entry in the session.
def appendEntry(api: T.ExtensionAPI, customType: String, data: Maybe<&2, V.Value>) -> IO(Result<&2, &2, String, Unit>):
  withActionsOf(api, actions => appendWith(actions, T.AppendEntry{customType, data}))

# Registration replaces this extension's renderer for the same custom type.
def withMessageRenderer(extension: T.Extension, customType: String, renderer: T.MessageRenderer()) -> T.Extension:
  match extension:
    case T.Extension{id, path, resolved, hidden, source, handlers, commands, state, changes, tools, T.ExtensionExtras{flags, shortcuts, pending, renderers}}:
      T.Extension{id, path, resolved, hidden, source, handlers, commands, state, changes, tools, T.ExtensionExtras{flags, shortcuts, pending, Record.set(T.MessageRenderer(), renderers, customType, renderer)}}
def registerMessageRenderer(api: T.ExtensionAPI, customType: String, renderer: T.MessageRenderer()) -> IO(Result<&2, &2, String, Unit>):
  modifyExtension(api, extension => withMessageRenderer(extension, customType, renderer))
