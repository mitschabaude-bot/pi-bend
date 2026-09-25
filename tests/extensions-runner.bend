import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/models.bend as AiModels
import ../packages/ai/src/auth/types.bend as Auth
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/tui/src/autocomplete.bend as AC
import ../packages/tui/src/component.bend as Component
import ../packages/coding-agent/src/core/diagnostics.bend as Diagnostics
import ../packages/coding-agent/src/core/slash-commands.bend as Slash
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ../packages/coding-agent/src/core/extensions/types.bend as T
import ../packages/coding-agent/src/modes/interactive/interactive-mode.bend as Interactive
import ../packages/coding-agent/src/modes/rpc.bend as Rpc
import ./model-runtime-fixture.bend as Fixture

# upstream test/extensions-runner.test.ts, the cases phase 1 of the native
# extension runtime covers (commands, context, provider registration,
# command context, event subscriptions, error listeners), plus the RPC
# get_commands entries and autocomplete conflicts of extension commands.
# Extensions are inline factories instead of files discovered on disk; the
# event cases use agent_end, the one event dispatched so far.

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})
def same(+actual: String, +expected: String, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), String.eq(actual, expected), _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ "\n  expected " ++ expected ++ "\n  actual   " ++ actual))(Unit{})

def Outcome() -> Data: Result<&2, &2, String, Unit>

# Fixtures
# --------

def noop(unit: Unit, call: T.CommandCall) -> IO(Outcome()): IO.pure(Outcome(), Done{Unit{}})

def commandOptions(description: String) -> IO(T.CommandOptions):
  do IO<T.CommandOptions>:
    handler : T.CommandHandler() <- C.create(~Unit, ~T.CommandCall, ~Outcome(), ~noop, Unit{})
    return T.CommandOptions{Some{description}, None{}, handler}

def registeringCommand(name: String, description: String, api: T.ExtensionAPI) -> IO(Outcome()):
  do IO<Outcome()>:
    options : T.CommandOptions <- commandOptions(description)
    Loader.registerCommand(api, name, options)

def commandExtension(label: String, name: String, description: String) -> T.InlineExtension:
  T.InlineExtension{label, api => registeringCommand(name, description, api), False{}}

def failing(api: T.ExtensionAPI) -> IO(Outcome()):
  do IO<Outcome()>:
    registered : Outcome() <- registeringCommand("never", "Registered before failing", api)
    return Fail{"factory failed"}

def emptyModels() -> IO(Models.ModelRuntime): Fixture.create(Nil{})

def loaded(extensions: List<&1, T.InlineExtension>) -> IO(Runner.ExtensionRunner):
  do IO<Runner.ExtensionRunner>:
    +runtime : T.ExtensionRuntime() <- Loader.createExtensionRuntime()
    errors : List<&2, T.LoadError> <- Loader.loadExtensionFactories(runtime, extensions)
    models : Models.ModelRuntime <- emptyModels()
    Runner.create(runtime, "/tmp/pi-runner-test", models)

def namesOf(commands: List<&2, T.ResolvedCommand>) -> List<&2, String>:
  match commands:
    case Nil{}: Nil{}
    case T.ResolvedCommand{name, _, _, _, _, _} <> rest: name <> namesOf(rest)

def invocationsOf(commands: List<&2, T.ResolvedCommand>) -> List<&2, String>:
  match commands:
    case Nil{}: Nil{}
    case T.ResolvedCommand{_, invocation, _, _, _, _} <> rest: invocation <> invocationsOf(rest)

def descriptionsOf(commands: List<&2, T.ResolvedCommand>) -> List<&2, String>:
  match commands:
    case Nil{}: Nil{}
    case T.ResolvedCommand{_, _, _, description, _, _} <> rest: Maybe.default(&2, String, description, "-") <> descriptionsOf(rest)

def joined(values: List<&2, String>) -> String: String.join(values, ",")

def shownCommand(command: Maybe<&2, T.ResolvedCommand>) -> String:
  match command:
    case None{}: "undefined"
    case Some{T.ResolvedCommand{name, invocation, _, description, _, _}}: name ++ " " ++ invocation ++ " " ++ Maybe.default(&2, String, description, "-")

def descriptionOf(command: Maybe<&2, T.ResolvedCommand>) -> String:
  match command:
    case Some{T.ResolvedCommand{_, _, _, Some{description}, _, _}}: description
    case _: "undefined"

# command collection
# ------------------

def collectsCommandsFromMultipleExtensions() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(commandExtension("cmd-a", "cmd-a", "Test command") <> commandExtension("cmd-b", "cmd-b", "Test command") <> Nil{})
    +commands : List<&2, T.ResolvedCommand> <- Runner.getRegisteredCommands(runner)
    check(Nat.is_eq(List.length(&2, T.ResolvedCommand, commands), 2n) && String.eq(joined(namesOf(commands)), "cmd-a,cmd-b") && String.eq(joined(invocationsOf(commands)), "cmd-a,cmd-b"), "collects commands from multiple extensions")

def getsCommandByInvocationName() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(commandExtension("cmd", "my-cmd", "My command") <> Nil{})
    found : Maybe<&2, T.ResolvedCommand> <- Runner.getCommand(runner, "my-cmd")
    missing : Maybe<&2, T.ResolvedCommand> <- Runner.getCommand(runner, "not-exists")
    same(shownCommand(found) ++ " / " ++ shownCommand(missing), "my-cmd my-cmd My command / undefined", "gets command by invocation name")

def suffixesDuplicateExtensionCommandsInInsertionOrder() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(commandExtension("cmd-a", "shared-cmd", "First command") <> commandExtension("cmd-b", "shared-cmd", "Second command") <> Nil{})
    +commands : List<&2, T.ResolvedCommand> <- Runner.getRegisteredCommands(runner)
    first : Maybe<&2, T.ResolvedCommand> <- Runner.getCommand(runner, "shared-cmd:1")
    second : Maybe<&2, T.ResolvedCommand> <- Runner.getCommand(runner, "shared-cmd:2")
    same(joined(namesOf(commands)) ++ " | " ++ joined(invocationsOf(commands)) ++ " | " ++ joined(descriptionsOf(commands)) ++ " | " ++ Nat.show(List.length(&2, Diagnostics.ResourceDiagnostic, Runner.getCommandDiagnostics(runner))) ++ " | " ++ descriptionOf(first) ++ " | " ++ descriptionOf(second), "shared-cmd,shared-cmd | shared-cmd:1,shared-cmd:2 | First command,Second command | 0 | First command | Second command", "suffixes duplicate extension commands in insertion order")

# Invocation names already taken are skipped: `a:1` registered as a name
# pushes the second `a` to `a:3` (upstream's do-while).
def skipsTakenInvocationNames() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(commandExtension("one", "a", "x") <> commandExtension("two", "a:2", "y") <> commandExtension("three", "a", "z") <> Nil{})
    commands : List<&2, T.ResolvedCommand> <- Runner.getRegisteredCommands(runner)
    same(joined(invocationsOf(commands)), "a:1,a:2,a:3", "skips invocation names that are already taken")

def shownErrors(errors: List<&2, T.LoadError>) -> String:
  match errors:
    case Nil{}: ""
    case T.LoadError{path, error} <> rest: path ++ ": " ++ error ++ shownErrors(rest)

def shownOutcome(outcome: Outcome()) -> String:
  match outcome:
    case Done{_}: "done"
    case Fail{error}: error

def failedFactoriesAreDiscarded() -> IO(Unit):
  do IO<Unit>:
    +runtime : T.ExtensionRuntime() <- Loader.createExtensionRuntime()
    errors : List<&2, T.LoadError> <- Loader.loadExtensionFactories(runtime, T.InlineExtension{"bad", failing, False{}} <> commandExtension("good", "good", "Good") <> Nil{})
    models : Models.ModelRuntime <- emptyModels()
    +runner : Runner.ExtensionRunner <- Runner.create(runtime, "/tmp/pi-runner-test", models)
    commands : List<&2, T.ResolvedCommand> <- Runner.getRegisteredCommands(runner)
    later : Outcome() <- registeringCommand("late", "After failure", T.ExtensionAPI{runtime, 0n})
    same(shownErrors(errors) ++ " | " ++ joined(invocationsOf(commands)) ++ " | " ++ shownOutcome(later), "<inline:bad>: factory failed | good | Extension \"<inline:bad>\" failed to load and its API is no longer active.", "discards the registrations of a failed factory")

# context creation
# ----------------

def testModel(+id: String) -> Models.Model():
  Ai.Model{id, id, Ai.OpenAICompletionsApi{}, "provider-test", "https://provider.test/v1", False{}, None{}, Ai.InputText{} <> Nil{}, None{}, Ai.ModelCost{U32.to_f64(1), U32.to_f64(2), U32.to_f64(0), U32.to_f64(1), None{}}, None{}, U32.to_f64(128000), U32.to_f64(4096), None{}, None{}, None{}}

type StateEnv is Data:
  StateEnv{scoped: List<&2, Models.ScopedModel>, trusted: Bool, signal: Maybe<&2, Abort.AbortSignal<Unit>>}

def stateOf(env: StateEnv, unit: Unit) -> IO(Ctx.SessionState):
  match env:
    case StateEnv{scoped, trusted, signal}: IO.pure(Ctx.SessionState, Ctx.SessionState{None{}, scoped, Ai.Off{}, "session", None{}, True{}, trusted, False{}, signal})

def nothing(unit: Unit, input: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def contextActions(env: StateEnv) -> IO(Ctx.ExtensionContextActions):
  do IO<Ctx.ExtensionContextActions>:
    state : C.Callback<Unit, Ctx.SessionState> <- C.create(~StateEnv, ~Unit, ~Ctx.SessionState, ~stateOf, env)
    abort : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~nothing, Unit{})
    shutdown : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~nothing, Unit{})
    return Ctx.ExtensionContextActions{state, abort, shutdown}

def scopedIds(items: List<&2, Models.ScopedModel>) -> String:
  match items:
    case Nil{}: ""
    case Models.ScopedModel{model, Some{level}} <> rest: Models.modelId(model) ++ ":high" ++ scopedIds(rest)
    case Models.ScopedModel{model, None{}} <> rest: Models.modelId(model) ++ scopedIds(rest)

def reflectsTheGetScopedModelsContextAction() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(Nil{})
    before : List<&2, Models.ScopedModel> <- Ctx.scopedModels(Runner.createContext(runner))
    actions : Ctx.ExtensionContextActions <- contextActions(StateEnv{[Models.ScopedModel{testModel("scoped-test"), Some{Ai.Thinking{Ai.High{}}}}], True{}, None{}})
    Runner.bindCore(runner, Some{actions}, None{})
    after : List<&2, Models.ScopedModel> <- Ctx.scopedModels(Runner.createContext(runner))
    same("[" ++ scopedIds(before) ++ "] [" ++ scopedIds(after) ++ "]", "[] [scoped-test:high]", "reflects the getScopedModels context action on ctx.scopedModels")

def abortedOf(signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> IO(Maybe<&2, Bool>):
  match signal:
    case None{}: IO.pure(Maybe<&2, Bool>, None{})
    case Some{signal}:
      do IO<Maybe<&2, Bool>>:
        aborted : Bool <- Abort.aborted(Unit, signal)
        return Some{aborted}

def shownAborted(value: Maybe<&2, Bool>) -> String:
  match value:
    case None{}: "undefined"
    case Some{aborted}: Bool.show(aborted)

def exposesTheCurrentAbortSignal() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(Nil{})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    actions : Ctx.ExtensionContextActions <- contextActions(StateEnv{Nil{}, True{}, Some{Abort.signal(Unit, controller)}})
    Runner.bindCore(runner, Some{actions}, None{})
    +ctx : Ctx.ExtensionContext <- IO.pure(Ctx.ExtensionContext, Runner.createContext(runner))
    first : Maybe<&2, Abort.AbortSignal<Unit>> <- Ctx.signal(ctx)
    before : Maybe<&2, Bool> <- abortedOf(first)
    won : Bool <- Abort.abort(Unit, controller, None{})
    second : Maybe<&2, Abort.AbortSignal<Unit>> <- Ctx.signal(ctx)
    after : Maybe<&2, Bool> <- abortedOf(second)
    same(shownAborted(before) ++ " " ++ shownAborted(after), "False True", "exposes the current abort signal on ExtensionContext")

def exposesPrintModeAndHasUIFalseByDefault() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(Nil{})
    actions : Ctx.ExtensionContextActions <- contextActions(StateEnv{Nil{}, True{}, None{}})
    Runner.bindCore(runner, Some{actions}, None{})
    mode : Ctx.ExtensionMode <- Ctx.mode(Runner.createContext(runner))
    ui : Bool <- Ctx.hasUI(Runner.createContext(runner))
    same(Ctx.modeName(mode) ++ " " ++ Bool.show(ui), "print False", "exposes print mode and hasUI false by default")

def exposesProjectTrustState() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(Nil{})
    actions : Ctx.ExtensionContextActions <- contextActions(StateEnv{Nil{}, False{}, None{}})
    Runner.bindCore(runner, Some{actions}, None{})
    trusted : Bool <- Ctx.isProjectTrusted(Runner.createContext(runner))
    check(Bool.not(trusted), "exposes project trust state on ExtensionContext")

def noSelection(unit: Unit, request: Ctx.SelectRequest) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, None{})
def noConfirmation(unit: Unit, request: Ctx.ConfirmRequest) -> IO(Bool): IO.pure(Bool, False{})
def noInput(unit: Unit, request: Ctx.InputRequest) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, None{})
def ignoredNotification(unit: Unit, notification: Ctx.Notification) -> IO(Unit): IO.pure(Unit, Unit{})
def ignoredStatus(unit: Unit, update: Ctx.StatusUpdate) -> IO(Unit): IO.pure(Unit, Unit{})
def ignoredCustom(unit: Unit, factory: Ctx.CustomFactory()) -> IO(Unit): IO.pure(Unit, Unit{})

def someUI() -> IO(Ctx.ExtensionUIContext):
  do IO<Ctx.ExtensionUIContext>:
    select : C.Callback<Ctx.SelectRequest, Maybe<&2, String>> <- C.create(~Unit, ~Ctx.SelectRequest, ~Maybe<&2, String>, ~noSelection, Unit{})
    confirm : C.Callback<Ctx.ConfirmRequest, Bool> <- C.create(~Unit, ~Ctx.ConfirmRequest, ~Bool, ~noConfirmation, Unit{})
    input : C.Callback<Ctx.InputRequest, Maybe<&2, String>> <- C.create(~Unit, ~Ctx.InputRequest, ~Maybe<&2, String>, ~noInput, Unit{})
    notify : C.Callback<Ctx.Notification, Unit> <- C.create(~Unit, ~Ctx.Notification, ~Unit, ~ignoredNotification, Unit{})
    status : C.Callback<Ctx.StatusUpdate, Unit> <- C.create(~Unit, ~Ctx.StatusUpdate, ~Unit, ~ignoredStatus, Unit{})
    custom : C.Callback<Ctx.CustomFactory(), Unit> <- C.create(~Unit, ~Ctx.CustomFactory(), ~Unit, ~ignoredCustom, Unit{})
    return Ctx.ExtensionUIContext{select, confirm, input, notify, status, custom}

def exposesModeWithUI(mode: Ctx.ExtensionMode, +expected: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(Nil{})
    actions : Ctx.ExtensionContextActions <- contextActions(StateEnv{Nil{}, True{}, None{}})
    Runner.bindCore(runner, Some{actions}, None{})
    ui : Ctx.ExtensionUIContext <- someUI()
    Runner.setUIContext(runner, Some{ui}, mode)
    shown : Ctx.ExtensionMode <- Ctx.mode(Runner.createContext(runner))
    available : Bool <- Ctx.hasUI(Runner.createContext(runner))
    same(Ctx.modeName(shown) ++ " " ++ Bool.show(available), expected, name)

# provider registration
# ---------------------

def tieredModel(+id: String, provider: String) -> Models.Model():
  Ai.Model{id, id, Ai.OpenAICompletionsApi{}, provider, "https://provider.test/v1", False{}, None{}, Ai.InputText{} <> Nil{}, None{}, Ai.ModelCost{U32.to_f64(1), U32.to_f64(2), U32.to_f64(0), U32.to_f64(1), Some{[Ai.ModelCostTier{U32.to_f64(2), U32.to_f64(3), U32.to_f64(0), U32.to_f64(2), U32.to_f64(272000)}]}}, None{}, U32.to_f64(128000), U32.to_f64(4096), None{}, None{}, None{}}

def keyResolved(unit: Unit, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  IO.pure(Auth.AuthOutcome(), Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{"provider-test-key"}, None{}, None{}}, None{}, None{}}}})

def keyedProvider(+id: String, models: List<&2, Models.Model()>) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Unit, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~keyResolved, Unit{})
    return AiModels.Provider{id, id, "https://provider.test/v1", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"Test", None{}, resolve}}, None{}}, models, AiModels.ApiStreams{}, None{}}

def capture(slot: R.Ref<Maybe<&2, T.ExtensionAPI>>, api: T.ExtensionAPI) -> IO(Outcome()):
  do IO<Outcome()>:
    R.write(Maybe<&2, T.ExtensionAPI>, slot, Some{api})
    return Done{Unit{}}

def capturing(slot: R.Ref<Maybe<&2, T.ExtensionAPI>>) -> T.InlineExtension:
  T.InlineExtension{"capture", api => capture(slot, api), False{}}

def pendingOf(state: T.ExtensionRuntimeState) -> Nat:
  match state:
    case T.ExtensionRuntimeState{_, pending, _, _}: List.length(&2, T.PendingProvider, pending)

def pendingCount(runtime: T.ExtensionRuntime()) -> IO(Nat):
  do IO<Nat>:
    state : T.ExtensionRuntimeState <- R.read(T.ExtensionRuntimeState, runtime)
    return pendingOf(state)

# A loaded extension's API with a runtime that is not bound to a model
# runtime yet.
type Loaded is Data:
  Loaded{runtime: T.ExtensionRuntime(), api: T.ExtensionAPI}

def loadedApi(+runtime: T.ExtensionRuntime(), found: Maybe<&2, T.ExtensionAPI>) -> IO(Loaded):
  match found:
    case None{}: IO.die(Loaded, 1, "FAIL the extension factory did not run")
    case Some{api}: IO.pure(Loaded, Loaded{runtime, api})

def loadCapturing() -> IO(Loaded):
  do IO<Loaded>:
    +runtime : T.ExtensionRuntime() <- Loader.createExtensionRuntime()
    +slot : R.Ref<Maybe<&2, T.ExtensionAPI>> <- R.new(Maybe<&2, T.ExtensionAPI>, None{})
    errors : List<&2, T.LoadError> <- Loader.loadExtensionFactories(runtime, capturing(slot) <> Nil{})
    found : Maybe<&2, T.ExtensionAPI> <- R.dispose(Maybe<&2, T.ExtensionAPI>, slot)
    loadedApi(runtime, found)

# upstream registers ProviderConfig objects; the native registration here
# queues Provider values the same way.
def preBindUnregisterRemovesQueuedRegistrationsWith(loaded: Loaded) -> IO(Unit):
  match loaded:
    case Loaded{+runtime, +api}:
      do IO<Unit>:
        first : AiModels.Provider <- keyedProvider("queued-provider", [tieredModel("instant-model", "queued-provider")])
        second : AiModels.Provider <- keyedProvider("queued-provider", [tieredModel("instant-model-2", "queued-provider")])
        registeredFirst : Outcome() <- Loader.registerProvider(api, first)
        registeredSecond : Outcome() <- Loader.registerProvider(api, second)
        queued : Nat <- pendingCount(runtime)
        removed : Outcome() <- Loader.unregisterProvider(api, "queued-provider")
        remaining : Nat <- pendingCount(runtime)
        same(Nat.show(queued) ++ " " ++ Nat.show(remaining), "2 0", "pre-bind unregister removes all queued registrations for a provider")
def preBindUnregisterRemovesQueuedRegistrations() -> IO(Unit): IO.bind(Loaded, Unit, loadCapturing(), preBindUnregisterRemovesQueuedRegistrationsWith)

def tiersOf(model: Maybe<&2, Models.Model()>) -> String:
  match model:
    case None{}: "undefined"
    case Some{Ai.Model{_, _, _, _, _, _, _, _, _, Ai.ModelCost{_, _, _, _, Some{[Ai.ModelCostTier{input, output, _, _, above}]}}, _, _, _, _, _, _}}: "above " ++ F64.show(above) ++ " input " ++ F64.show(input) ++ " output " ++ F64.show(output)
    case Some{_}: "other"

def postBindRegisterAndUnregisterTakeEffectImmediatelyWith(loaded: Loaded) -> IO(Unit):
  match loaded:
    case Loaded{+runtime, +api}:
      do IO<Unit>:
        +models : Models.ModelRuntime <- emptyModels()
        +runner : Runner.ExtensionRunner <- Runner.create(runtime, "/tmp/pi-runner-test", models)
        actions : Ctx.ExtensionContextActions <- contextActions(StateEnv{Nil{}, True{}, None{}})
        Runner.bindCore(runner, Some{actions}, None{})
        before : Nat <- pendingCount(runtime)
        provider : AiModels.Provider <- keyedProvider("instant-provider", [tieredModel("instant-model", "instant-provider")])
        registered : Outcome() <- Loader.registerProvider(api, provider)
        queued : Nat <- pendingCount(runtime)
        found : Maybe<&2, Models.Model()> <- Models.getModel(models, "instant-provider", "instant-model")
        removed : Outcome() <- Loader.unregisterProvider(api, "instant-provider")
        gone : Maybe<&2, Models.Model()> <- Models.getModel(models, "instant-provider", "instant-model")
        same(Nat.show(before) ++ " " ++ Nat.show(queued) ++ " " ++ tiersOf(found) ++ " " ++ tiersOf(gone), "0 0 above 272000 input 2 output 3 undefined", "post-bind register and unregister take effect immediately")
def postBindRegisterAndUnregisterTakeEffectImmediately() -> IO(Unit): IO.bind(Loaded, Unit, loadCapturing(), postBindRegisterAndUnregisterTakeEffectImmediatelyWith)

# Registered before the model runtime exists, a provider is available once
# the runtime is bound, and model resolution sees it.
def resolvedId(resolution: Models.Resolution) -> String:
  match resolution:
    case Models.Resolved{Models.ResolveCliModelResult{Some{model}, _, _, _}}: Models.reference(model)
    case _: "unresolved"

def shownExtensionErrors(errors: List<&2, T.ExtensionError>) -> String:
  match errors:
    case Nil{}: ""
    case T.ExtensionError{path, event, error, _} <> rest: path ++ " " ++ event ++ " " ++ error ++ shownExtensionErrors(rest)

def queuedProvidersJoinTheModelRuntimeWith(loaded: Loaded) -> IO(Unit):
  match loaded:
    case Loaded{+runtime, +api}:
      do IO<Unit>:
        provider : AiModels.Provider <- keyedProvider("instant-provider", [tieredModel("instant-model", "instant-provider")])
        registered : Outcome() <- Loader.registerProvider(api, provider)
        +models : Models.ModelRuntime <- emptyModels()
        errors : List<&2, T.ExtensionError> <- Loader.bindProviders(runtime, models, None{})
        available : List<&2, Models.Model()> <- Models.getAvailable(models)
        resolution : Models.Resolution <- Models.resolveCliModel(models, None{}, Some{"instant-model"}, None{})
        same(Nat.show(List.length(&2, T.ExtensionError, errors)) ++ " " ++ Nat.show(List.length(&2, Models.Model(), available)) ++ " " ++ resolvedId(resolution), "0 1 instant-provider/instant-model", "queued provider registrations join the model runtime")
def queuedProvidersJoinTheModelRuntime() -> IO(Unit): IO.bind(Loaded, Unit, loadCapturing(), queuedProvidersJoinTheModelRuntimeWith)

def blankProviderIsAnExtensionErrorWith(loaded: Loaded) -> IO(Unit):
  match loaded:
    case Loaded{+runtime, +api}:
      do IO<Unit>:
        provider : AiModels.Provider <- keyedProvider(" ", Nil{})
        registered : Outcome() <- Loader.registerProvider(api, provider)
        models : Models.ModelRuntime <- emptyModels()
        errors : List<&2, T.ExtensionError> <- Loader.bindProviders(runtime, models, None{})
        same(shownExtensionErrors(errors), "<inline:capture> register_provider Provider id must not be empty.", "bindCore reports a rejected queued registration as an extension error")
def blankProviderIsAnExtensionError() -> IO(Unit): IO.bind(Loaded, Unit, loadCapturing(), blankProviderIsAnExtensionErrorWith)

# command context
# ---------------

def positionName(position: Maybe<&2, Ctx.ForkPosition>) -> String:
  match position:
    case None{}: "undefined"
    case Some{Ctx.ForkBefore{}}: "before"
    case Some{Ctx.ForkAt{}}: "at"

def recordFork(slot: R.Ref<List<&2, String>>, request: Ctx.ForkRequest) -> IO(Ctx.SessionChange):
  match request:
    case Ctx.ForkRequest{entry, position}:
      do IO<Ctx.SessionChange>:
        R.modify(List<&2, String>, Unit, slot, calls => (List.append(&2, String, calls, [entry ++ " " ++ positionName(position)]), Unit{}))
        return Ctx.SessionChange{False{}}

def notCancelled(unit: Unit, request: Ctx.NewSessionRequest) -> IO(Ctx.SessionChange): IO.pure(Ctx.SessionChange, Ctx.SessionChange{False{}})
def notNavigated(unit: Unit, request: Ctx.NavigateTreeRequest) -> IO(Ctx.SessionChange): IO.pure(Ctx.SessionChange, Ctx.SessionChange{False{}})
def notSwitched(unit: Unit, request: Ctx.SwitchSessionRequest) -> IO(Ctx.SessionChange): IO.pure(Ctx.SessionChange, Ctx.SessionChange{False{}})

def passesForkOptionsThroughToTheBoundHandler() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(Nil{})
    +calls : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    wait : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~nothing, Unit{})
    created : C.Callback<Ctx.NewSessionRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.NewSessionRequest, ~Ctx.SessionChange, ~notCancelled, Unit{})
    fork : C.Callback<Ctx.ForkRequest, Ctx.SessionChange> <- C.create(~R.Ref<List<&2, String>>, ~Ctx.ForkRequest, ~Ctx.SessionChange, ~recordFork, calls)
    navigate : C.Callback<Ctx.NavigateTreeRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.NavigateTreeRequest, ~Ctx.SessionChange, ~notNavigated, Unit{})
    switch : C.Callback<Ctx.SwitchSessionRequest, Ctx.SessionChange> <- C.create(~Unit, ~Ctx.SwitchSessionRequest, ~Ctx.SessionChange, ~notSwitched, Unit{})
    reload : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~nothing, Unit{})
    Runner.bindCommandContext(runner, Some{Ctx.ExtensionCommandContextActions{wait, created, fork, navigate, switch, reload}})
    +ctx : Ctx.ExtensionCommandContext <- IO.pure(Ctx.ExtensionCommandContext, Runner.createCommandContext(runner))
    first : Ctx.SessionChange <- Ctx.fork(ctx, "entry-1", None{})
    second : Ctx.SessionChange <- Ctx.fork(ctx, "entry-2", Some{Ctx.ForkAt{}})
    recorded : List<&2, String> <- R.read(List<&2, String>, calls)
    same(joined(recorded), "entry-1 undefined,entry-2 at", "passes fork options through to the bound handler")

# event subscriptions
# -------------------

type Named is Data:
  Named{name: String, stop: Loader.Unsubscribe}

type Harness is Data:
  Harness{calls: R.Ref<List<&2, String>>, stops: R.Ref<List<&2, Named>>, runner: R.Ref<Maybe<&2, Runner.ExtensionRunner>>, api: T.ExtensionAPI}

def Handler() -> Data: T.ExtensionHandler(T.AgentEndEvent, Unit)
def HandlerResult() -> Data: Result<&2, &2, String, Maybe<&2, Unit>>

def callsOf(harness: Harness) -> R.Ref<List<&2, String>>:
  match harness:
    case Harness{calls, _, _, _}: calls

def record(calls: R.Ref<List<&2, String>>, label: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, calls, current => (List.append(&2, String, current, [label]), Unit{}))

type Leaf is Data:
  Leaf{calls: R.Ref<List<&2, String>>, label: String}

def leaf(env: Leaf, call: T.HandlerCall<T.AgentEndEvent>) -> IO(HandlerResult()):
  match env:
    case Leaf{calls, label}:
      do IO<HandlerResult()>:
        record(calls, label)
        return Done{None{}}

def remembered(+harness: Harness, +name: String, result: Result<&2, &2, String, Loader.Unsubscribe>) -> IO(Outcome()):
  match harness result:
    case _ Fail{error}: IO.pure(Outcome(), Fail{error})
    case Harness{_, stops, _, _} Done{stop}:
      do IO<Outcome()>:
        R.modify(List<&2, Named>, Unit, stops, current => (List.append(&2, Named, current, [Named{name, stop}]), Unit{}))
        return Done{Unit{}}

def subscribeCallback(+harness: Harness, +name: String, callback: Handler()) -> IO(Outcome()):
  match harness:
    case Harness{_, _, _, +api}:
      do IO<Outcome()>:
        result : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, T.OnAgentEnd{callback})
        remembered(harness, name, result)

def subscribeLeaf(+harness: Harness, +label: String) -> IO(Outcome()):
  do IO<Outcome()>:
    callback : Handler() <- C.create(~Leaf, ~T.HandlerCall<T.AgentEndEvent>, ~HandlerResult(), ~leaf, Leaf{callsOf(harness), label})
    subscribeCallback(harness, label, callback)

# What a test handler does after recording its label: remove handlers by
# name, register a handler that only records, dispatch again, or fail.
type Step is Data:
  Stop{name: String}
  Subscribe{label: String}
  Dispatch{}
  Throw{message: String}

def stopNamed(stops: List<&2, Named>, +name: String) -> IO(Unit):
  match stops:
    case Nil{}: IO.pure(Unit, Unit{})
    case Named{+other, stop} <> rest:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit), String.eq(other, name), _ => Loader.unsubscribe(stop), _ => IO.pure(Unit, Unit{}))(Unit{})
        stopNamed(rest, name)

def dispatchWith(runner: Maybe<&2, Runner.ExtensionRunner>) -> IO(Unit):
  match runner:
    case None{}: IO.pure(Unit, Unit{})
    case Some{found}: Runner.emit(found, T.AgentEnd{T.AgentEndEvent{Nil{}}})

def performed(steps: List<&2, Step>, +harness: Harness) -> IO(HandlerResult()):
  match steps harness:
    case Nil{} _: IO.pure(HandlerResult(), Done{None{}})
    case Throw{message} <> _ _: IO.pure(HandlerResult(), Fail{message})
    case Stop{name} <> rest Harness{calls, stops, runner, api}:
      do IO<HandlerResult()>:
        registered : List<&2, Named> <- R.read(List<&2, Named>, stops)
        stopNamed(registered, name)
        performed(rest, Harness{calls, stops, runner, api})
    case Subscribe{label} <> rest _:
      do IO<HandlerResult()>:
        subscribed : Outcome() <- subscribeLeaf(harness, label)
        performed(rest, harness)
    case Dispatch{} <> rest Harness{calls, stops, runner, api}:
      do IO<HandlerResult()>:
        current : Maybe<&2, Runner.ExtensionRunner> <- R.read(Maybe<&2, Runner.ExtensionRunner>, runner)
        dispatchWith(current)
        performed(rest, Harness{calls, stops, runner, api})

type Behavior is Data:
  Behavior{harness: Harness, label: String, steps: List<&2, Step>}

def behave(behavior: Behavior, call: T.HandlerCall<T.AgentEndEvent>) -> IO(HandlerResult()):
  match behavior:
    case Behavior{+harness, label, steps}:
      do IO<HandlerResult()>:
        record(callsOf(harness), label)
        performed(steps, harness)

def handlerFor(harness: Harness, label: String, steps: List<&2, Step>) -> IO(Handler()):
  C.create(~Behavior, ~T.HandlerCall<T.AgentEndEvent>, ~HandlerResult(), ~behave, Behavior{harness, label, steps})

def subscribe(+harness: Harness, +label: String, steps: List<&2, Step>) -> IO(Outcome()):
  do IO<Outcome()>:
    callback : Handler() <- handlerFor(harness, label, steps)
    subscribeCallback(harness, label, callback)

# The handlers a test registers from its factory.
type Registration is Data:
  Registration{label: String, steps: List<&2, Step>}

def registerAll(+harness: Harness, registrations: List<&2, Registration>) -> IO(Outcome()):
  match registrations:
    case Nil{}: IO.pure(Outcome(), Done{Unit{}})
    case Registration{label, steps} <> rest:
      do IO<Outcome()>:
        registered : Outcome() <- subscribe(harness, label, steps)
        registerAll(harness, rest)

type Shared is Data:
  Shared{calls: R.Ref<List<&2, String>>, stops: R.Ref<List<&2, Named>>, runner: R.Ref<Maybe<&2, Runner.ExtensionRunner>>}

def registering(shared: Shared, registrations: List<&2, Registration>, api: T.ExtensionAPI) -> IO(Outcome()):
  match shared:
    case Shared{calls, stops, runner}: registerAll(Harness{calls, stops, runner, api}, registrations)

type Subscriptions is Data:
  Subscriptions{shared: Shared, runner: Runner.ExtensionRunner}

def subscriptionExtension(registrations: List<&2, Registration>) -> IO(Subscriptions):
  do IO<Subscriptions>:
    calls : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    stops : R.Ref<List<&2, Named>> <- R.new(List<&2, Named>, Nil{})
    +slot : R.Ref<Maybe<&2, Runner.ExtensionRunner>> <- R.new(Maybe<&2, Runner.ExtensionRunner>, None{})
    +shared : Shared <- IO.pure(Shared, Shared{calls, stops, slot})
    +runner : Runner.ExtensionRunner <- loaded(T.InlineExtension{"subscriptions", api => registering(shared, registrations, api), False{}} <> Nil{})
    R.write(Maybe<&2, Runner.ExtensionRunner>, slot, Some{runner})
    return Subscriptions{shared, runner}

def agentEnd() -> T.ExtensionEvent: T.AgentEnd{T.AgentEndEvent{Nil{}}}

def recordedCalls(shared: Shared) -> IO(String):
  match shared:
    case Shared{calls, _, _}:
      do IO<String>:
        current : List<&2, String> <- R.read(List<&2, String>, calls)
        return joined(current)

def stopByName(shared: Shared, +name: String) -> IO(Unit):
  match shared:
    case Shared{_, stops, _}:
      do IO<Unit>:
        registered : List<&2, Named> <- R.read(List<&2, Named>, stops)
        stopNamed(registered, name)

# Emits agent_end twice and reports the calls after each dispatch.
def twoDispatchesWith(subscriptions: Subscriptions) -> IO(String):
  match subscriptions:
    case Subscriptions{+shared, +runner}:
      do IO<String>:
        Runner.emit(runner, agentEnd())
        first : String <- recordedCalls(shared)
        Runner.emit(runner, agentEnd())
        second : String <- recordedCalls(shared)
        return first ++ " | " ++ second

def twoDispatches(registrations: List<&2, Registration>) -> IO(String):
  IO.bind(Subscriptions, String, subscriptionExtension(registrations), twoDispatchesWith)

def allowsSelfRemoval() -> IO(Unit):
  do IO<Unit>:
    shown : String <- twoDispatches([Registration{"A", [Stop{"A"}]}, Registration{"B", Nil{}}])
    same(shown, "A,B | A,B,B", "allows self-removal without skipping neighboring handlers")

def keepsRemovedPendingHandlers() -> IO(Unit):
  do IO<Unit>:
    shown : String <- twoDispatches([Registration{"A", [Stop{"B"}]}, Registration{"B", Nil{}}, Registration{"C", Nil{}}])
    same(shown, "A,B,C | A,B,C,A,C", "keeps removed pending handlers in the current dispatch")

def defersRegistrationsMadeDuringDispatch() -> IO(Unit):
  do IO<Unit>:
    shown : String <- twoDispatches([Registration{"A", [Subscribe{"C"}]}, Registration{"B", Nil{}}])
    same(shown, "A,B | A,B,A,B,C", "defers registrations made during dispatch until the next dispatch")

def usesAFreshHandlerListForNestedDispatchesWith(subscriptions: Subscriptions) -> IO(Unit):
  match subscriptions:
    case Subscriptions{+shared, +runner}:
      do IO<Unit>:
        Runner.emit(runner, agentEnd())
        shown : String <- recordedCalls(shared)
        same(shown, "A,C,B", "uses a fresh handler list for nested dispatches")
def usesAFreshHandlerListForNestedDispatches() -> IO(Unit): IO.bind(Subscriptions, Unit, subscriptionExtension([Registration{"A", [Stop{"A"}, Stop{"B"}, Subscribe{"C"}, Dispatch{}]}, Registration{"B", Nil{}}]), usesAFreshHandlerListForNestedDispatchesWith)

# Upstream registers one function twice; here one callback is registered
# twice, and the registrations are removed by the ids `on` returned.
def registerShared(+harness: Harness) -> IO(Outcome()):
  do IO<Outcome()>:
    +callback : Handler() <- C.create(~Leaf, ~T.HandlerCall<T.AgentEndEvent>, ~HandlerResult(), ~leaf, Leaf{callsOf(harness), "shared"})
    first : Outcome() <- subscribeCallback(harness, "first", callback)
    b : Outcome() <- subscribeLeaf(harness, "B")
    subscribeCallback(harness, "second", callback)

def sharedHandlerTwice(shared: Shared, api: T.ExtensionAPI) -> IO(Outcome()):
  match shared:
    case Shared{calls, stops, runner}: registerShared(Harness{calls, stops, runner, api})

def removesDuplicateRegistrationsIndependently() -> IO(Unit):
  do IO<Unit>:
    calls : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    stops : R.Ref<List<&2, Named>> <- R.new(List<&2, Named>, Nil{})
    +slot : R.Ref<Maybe<&2, Runner.ExtensionRunner>> <- R.new(Maybe<&2, Runner.ExtensionRunner>, None{})
    +shared : Shared <- IO.pure(Shared, Shared{calls, stops, slot})
    +runner : Runner.ExtensionRunner <- loaded(T.InlineExtension{"subscriptions", api => sharedHandlerTwice(shared, api), False{}} <> Nil{})
    stopByName(shared, "second")
    stopByName(shared, "second")
    Runner.emit(runner, agentEnd())
    first : String <- recordedCalls(shared)
    stopByName(shared, "first")
    Runner.emit(runner, agentEnd())
    second : String <- recordedCalls(shared)
    stopByName(shared, "B")
    remaining : Bool <- Runner.hasHandlers(runner, "agent_end")
    same(first ++ " | " ++ second ++ " | " ++ Bool.show(remaining), "shared,B | shared,B,B | False", "removes duplicate registrations independently and cleans up the last handler")

# hasHandlers (upstream registers tool_call, not dispatched yet here, and
# asks for agent_end; the roles of the two events are swapped).
def returnsTrueWhenHandlersExistWith(subscriptions: Subscriptions) -> IO(Unit):
  match subscriptions:
    case Subscriptions{_, +runner}:
      do IO<Unit>:
        present : Bool <- Runner.hasHandlers(runner, "agent_end")
        absent : Bool <- Runner.hasHandlers(runner, "tool_call")
        check(present && Bool.not(absent), "returns true when handlers exist for event type")
def returnsTrueWhenHandlersExist() -> IO(Unit): IO.bind(Subscriptions, Unit, subscriptionExtension([Registration{"A", Nil{}}]), returnsTrueWhenHandlersExistWith)

# error handling (upstream throws from a `context` handler)
def recordError(slot: R.Ref<List<&2, T.ExtensionError>>, error: T.ExtensionError) -> IO(Unit):
  R.modify(List<&2, T.ExtensionError>, Unit, slot, current => (List.append(&2, T.ExtensionError, current, [error]), Unit{}))

def callsErrorListenersWhenHandlerThrowsWith(subscriptions: Subscriptions) -> IO(Unit):
  match subscriptions:
    case Subscriptions{+shared, +runner}:
      do IO<Unit>:
        +errors : R.Ref<List<&2, T.ExtensionError>> <- R.new(List<&2, T.ExtensionError>, Nil{})
        listener : C.Callback<T.ExtensionError, Unit> <- C.create(~R.Ref<List<&2, T.ExtensionError>>, ~T.ExtensionError, ~Unit, ~recordError, errors)
        subscription : Runner.ErrorSubscription <- Runner.onError(runner, listener)
        Runner.emit(runner, agentEnd())
        reported : List<&2, T.ExtensionError> <- R.read(List<&2, T.ExtensionError>, errors)
        calls : String <- recordedCalls(shared)
        same(shownExtensionErrors(reported) ++ " | " ++ calls, "<inline:subscriptions> agent_end Handler error! | A,B", "calls error listeners when handler throws")
def callsErrorListenersWhenHandlerThrows() -> IO(Unit): IO.bind(Subscriptions, Unit, subscriptionExtension([Registration{"A", [Throw{"Handler error!"}]}, Registration{"B", Nil{}}]), callsErrorListenersWhenHandlerThrowsWith)

# RPC get_commands and autocomplete
# ---------------------------------

def line(value: V.Value) -> String:
  Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(value)), "null")

def rpcCommandsListExtensionCommands() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(commandExtension("cmd-a", "shared-cmd", "First command") <> commandExtension("cmd-b", "shared-cmd", "Second command") <> Nil{})
    commands : List<&2, T.ResolvedCommand> <- Runner.getRegisteredCommands(runner)
    same(line(V.ArrayValue{Rpc.extensionCommands(commands, Nil{})}), "[{\"name\":\"shared-cmd:1\",\"description\":\"First command\",\"source\":\"extension\",\"sourceInfo\":{\"path\":\"<inline:cmd-a>\",\"source\":\"inline\",\"scope\":\"temporary\",\"origin\":\"top-level\"}},{\"name\":\"shared-cmd:2\",\"description\":\"Second command\",\"source\":\"extension\",\"sourceInfo\":{\"path\":\"<inline:cmd-b>\",\"source\":\"inline\",\"scope\":\"temporary\",\"origin\":\"top-level\"}}]", "get_commands lists extension commands by invocation name")

def slashNames(commands: List<&2, AC.Command>) -> List<&2, String>:
  match commands:
    case Nil{}: Nil{}
    case AC.Slash{AC.SlashCommand{name, description, _, _}} <> rest: (name ++ "=" ++ Maybe.default(&2, String, description, "-")) <> slashNames(rest)
    case AC.Item{_} <> rest: slashNames(rest)

def diagnosticMessages(diagnostics: List<&2, Diagnostics.ResourceDiagnostic>) -> List<&2, String>:
  match diagnostics:
    case Nil{}: Nil{}
    case Diagnostics.ResourceDiagnostic{_, message, path, _} <> rest: (message ++ " @" ++ Maybe.default(&2, String, path, "-")) <> diagnosticMessages(rest)

def autocompleteSkipsBuiltinNames() -> IO(Unit):
  do IO<Unit>:
    +runner : Runner.ExtensionRunner <- loaded(commandExtension("one", "model", "Shadow") <> commandExtension("two", "llama", "Manage llama.cpp") <> commandExtension("three", "tree", "First tree") <> commandExtension("four", "tree", "Second tree") <> Nil{})
    +commands : List<&2, T.ResolvedCommand> <- Runner.getRegisteredCommands(runner)
    same(joined(slashNames(Interactive.extensionCommands(commands, Interactive.builtinNames(Slash.BUILTIN_SLASH_COMMANDS())))) ++ " | " ++ String.join(diagnosticMessages(Interactive.getBuiltInCommandConflictDiagnostics(commands)), " / "), "llama=[t] Manage llama.cpp | Extension command '/model' conflicts with built-in interactive command. Skipping in autocomplete. @<inline:one> / Extension command '/tree' conflicts with built-in interactive command. Available as '/tree:1'. @<inline:three> / Extension command '/tree' conflicts with built-in interactive command. Available as '/tree:2'. @<inline:four>", "autocomplete lists extension commands and reports built-in conflicts")

# suite/regressions/8423-extension-factory-failure.test.ts. Adaptations:
# registerFlag/getFlag and the event bus are not ported, so the failed API's
# late call is registerProvider and the event-bus assertion stays pending;
# upstream's config-form registerProvider(name, config) is a Provider value.
def pendingNames(pending: List<&2, T.PendingProvider>) -> List<&2, String>:
  match pending:
    case Nil{}: Nil{}
    case T.PendingProvider{provider, _} <> rest: Loader.providerIdOf(provider) <> pendingNames(rest)

def pendingNamesOf(state: T.ExtensionRuntimeState) -> String:
  match state:
    case T.ExtensionRuntimeState{_, pending, _, _}: joined(pendingNames(pending))

def pendingText(runtime: T.ExtensionRuntime()) -> IO(String):
  do IO<String>:
    state : T.ExtensionRuntimeState <- R.read(T.ExtensionRuntimeState, runtime)
    return pendingNamesOf(state)

def registeringProvider(+id: String, api: T.ExtensionAPI) -> IO(Outcome()):
  do IO<Outcome()>:
    provider : AiModels.Provider <- keyedProvider(id, Nil{})
    Loader.registerProvider(api, provider)

def failingAfterChanges(slot: R.Ref<Maybe<&2, T.ExtensionAPI>>, +api: T.ExtensionAPI) -> IO(Outcome()):
  do IO<Outcome()>:
    R.write(Maybe<&2, T.ExtensionAPI>, slot, Some{api})
    removed : Outcome() <- Loader.unregisterProvider(api, "working-provider")
    registered : Outcome() <- registeringProvider("failed-provider", api)
    return Fail{"factory failed"}

def lateRegistration(found: Maybe<&2, T.ExtensionAPI>) -> IO(Outcome()):
  match found:
    case None{}: IO.pure(Outcome(), Fail{"the failing factory did not run"})
    case Some{api}: registeringProvider("late-provider", api)

def discardsRuntimeChangesOfAFailedFactory() -> IO(Unit):
  do IO<Unit>:
    +runtime : T.ExtensionRuntime() <- Loader.createExtensionRuntime()
    working : Outcome() <- Loader.loadExtensionFromFactory(runtime, api => registeringProvider("working-provider", api), "<working>", False{})
    +slot : R.Ref<Maybe<&2, T.ExtensionAPI>> <- R.new(Maybe<&2, T.ExtensionAPI>, None{})
    failed : Outcome() <- Loader.loadExtensionFromFactory(runtime, api => failingAfterChanges(slot, api), "<failing>", False{})
    names : String <- pendingText(runtime)
    captured : Maybe<&2, T.ExtensionAPI> <- R.dispose(Maybe<&2, T.ExtensionAPI>, slot)
    late : Outcome() <- lateRegistration(captured)
    same(shownOutcome(failed) ++ " | " ++ names ++ " | " ++ shownOutcome(late), "factory failed | working-provider | Extension \"<failing>\" failed to load and its API is no longer active.", "discards runtime changes and disables the failed API")

def signalled(gate: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit, gate, Unit{})
    return Unit{}

def failingLater(started: Chan(Unit), release: Chan(Unit), +api: T.ExtensionAPI) -> IO(Outcome()):
  do IO<Outcome()>:
    registered : Outcome() <- registeringProvider("failed-provider", api)
    signalled(started)
    released : Maybe<&1, Unit> <- Chan.recv(Unit, release)
    return Fail{"factory failed"}

def loadInBackground(+runtime: T.ExtensionRuntime(), started: Chan(Unit), release: Chan(Unit), done: Chan(Outcome())) -> IO(Unit):
  do IO<Unit>:
    result : Outcome() <- Loader.loadExtensionFromFactory(runtime, api => failingLater(started, release, api), "<failing>", False{})
    sent : Bool <- Chan.send(Outcome(), done, result)
    return Unit{}

def finishedOutcome(value: Maybe<&1, Outcome()>) -> String:
  match value:
    case Some{result}: shownOutcome(result)
    case None{}: "unfinished"

def keepsAConcurrentlyLoadedProvider() -> IO(Unit):
  do IO<Unit>:
    +runtime : T.ExtensionRuntime() <- Loader.createExtensionRuntime()
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    +done : Chan(Outcome()) <- Chan.new(Outcome(), 1)
    IO.spawn(Unit, loadInBackground(runtime, started, release, done))
    began : Maybe<&1, Unit> <- Chan.recv(Unit, started)
    working : Outcome() <- Loader.loadExtensionFromFactory(runtime, api => registeringProvider("working-provider", api), "<working>", False{})
    signalled(release)
    failed : Maybe<&1, Outcome()> <- Chan.recv(Outcome(), done)
    names : String <- pendingText(runtime)
    same(finishedOutcome(failed) ++ " | " ++ names, "factory failed | working-provider", "does not discard a concurrently loaded factory's provider")
    Chan.close(Unit, started)
    Chan.close(Unit, release)
    Chan.close(Outcome(), done)

def main() -> IO(Unit):
  do IO<Unit>:
    collectsCommandsFromMultipleExtensions()
    getsCommandByInvocationName()
    suffixesDuplicateExtensionCommandsInInsertionOrder()
    skipsTakenInvocationNames()
    failedFactoriesAreDiscarded()
    reflectsTheGetScopedModelsContextAction()
    exposesTheCurrentAbortSignal()
    exposesPrintModeAndHasUIFalseByDefault()
    exposesProjectTrustState()
    exposesModeWithUI(Ctx.RpcMode{}, "rpc True", "exposes rpc mode with hasUI true when an RPC UI context is provided")
    exposesModeWithUI(Ctx.TuiMode{}, "tui True", "exposes tui mode with hasUI true when a TUI UI context is provided")
    preBindUnregisterRemovesQueuedRegistrations()
    postBindRegisterAndUnregisterTakeEffectImmediately()
    queuedProvidersJoinTheModelRuntime()
    blankProviderIsAnExtensionError()
    passesForkOptionsThroughToTheBoundHandler()
    allowsSelfRemoval()
    removesDuplicateRegistrationsIndependently()
    keepsRemovedPendingHandlers()
    defersRegistrationsMadeDuringDispatch()
    usesAFreshHandlerListForNestedDispatches()
    returnsTrueWhenHandlersExist()
    callsErrorListenersWhenHandlerThrows()
    rpcCommandsListExtensionCommands()
    autocompleteSkipsBuiltinNames()
    discardsRuntimeChangesOfAFailedFactory()
    keepsAConcurrentlyLoadedProvider()
