import Base
import ../../ai/src/types.bend as Ai
import ../../ai/src/models.bend as AiModels
import ../../ai/src/auth/types.bend as Auth
import ../../ai/src/auth/helpers.bend as AuthHelpers
import ../../ai/src/auth/context.bend as AuthContext
import ../../ai/src/auth/resolve.bend as Resolve
import ../../ai/src/auth/credential-store.bend as Credentials
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/record.bend as Record
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema-value.bend as V
import ../src/utils/paths.bend as Paths
import ../src/core/agent-runtime.bend as Runtime
import ../src/core/agent-session.bend as Session
import ../src/core/sdk.bend as Sdk
import ../src/core/settings-manager.bend as Settings
import ../src/core/model-runtime.bend as Models
import ../src/core/session-manager.bend as Manager
import ../src/core/session-persistence.bend as Persistence
import ../src/core/tools/index.bend as Tools
import ../src/core/resource-loader.bend as Resources
import ../src/core/extensions/loader.bend as Loader
import ../src/core/extensions/runner.bend as Runner
import ../src/core/extensions/types.bend as Ext
import ../src/core/extensions/context.bend as Ctx

# Model and thinking selection through a real SDK AgentSession and injected models.
# The SDK records its initial model; compare the appended entry against that
# baseline because upstream's direct AgentSession harness skips SDK initialization.
# The teardown case checks native resource lifetime; upstream rejects stale
# context access, while Bend's typed stale-context rejection is still pending.
# Build: BEND_TUS=64 BEND_CFLAGS='-DBEND_APP_ARGV -DBEND_DEFAULT_THREADS=1' sh scripts/build-incremental.sh packages/coding-agent/test/sdk-model-events.bend build/sdk-model-events-native

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def model(+id: String, +name: String, +provider: String, reasoning: Bool) -> Ai.Model<Ai.JsonValue>:
  Ai.Model{id, name, Ai.OpenAICompletionsApi{}, provider, "https://capture.invalid/v1", reasoning, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def provider(models: List<&2, Ai.Model<Ai.JsonValue>>) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    key : Auth.ApiKeyAuth <- AuthHelpers.envApiKeyAuth("Capture key", ["PI_SDK_MODEL_UNUSED"])
    return AiModels.Provider{"capture-provider", "Capture Provider", "https://capture.invalid/v1", Auth.ProviderAuth{Some{key}, None{}}, models, AiModels.ApiStreams{}, None{}, None{}}

def key(found: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> String:
  match found:
    case None{}: "none"
    case Some{value}: Models.reference(value)

def level(value: Ai.ModelThinkingLevel) -> String:
  match value:
    case Ai.Off{}: "off"
    case Ai.Thinking{Ai.Minimal{}}: "minimal"
    case Ai.Thinking{Ai.Low{}}: "low"
    case Ai.Thinking{Ai.Medium{}}: "medium"
    case Ai.Thinking{Ai.High{}}: "high"
    case Ai.Thinking{Ai.XHigh{}}: "xhigh"
    case Ai.Thinking{Ai.Max{}}: "max"

def source(value: Ext.ModelSelectSource) -> String:
  match value:
    case Ext.ModelSelectSet{}: "set"
    case Ext.ModelSelectCycle{}: "cycle"
    case Ext.ModelSelectRestore{}: "restore"

def appended(+value: String, +prior: List<&2, String>) -> List<&2, String>: List.append(&2, String, prior, [value])
def add(items: R.Ref<List<&2, String>>, value: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, items, prior => (appended(value, prior), Unit{}))

type Trace is Data:
  Trace{items: R.Ref<List<&2, String>>, started: Chan(Unit), release: Chan(Unit), completed: Chan(Unit), blocked: R.Ref<Bool>, api: R.Ref<Maybe<&2, Ext.ExtensionAPI>>}

def failedModel(_: Unit, _: Ext.HandlerCall<Ext.ModelSelectEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  IO.pure(Result<&2, &2, String, Maybe<&2, Unit>>, Fail{"model handler boom"})

def failedThinking(_: Unit, _: Ext.HandlerCall<Ext.ThinkingLevelSelectEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  IO.pure(Result<&2, &2, String, Maybe<&2, Unit>>, Fail{"thinking handler boom"})

def seenModel(items: R.Ref<List<&2, String>>, call: Ext.HandlerCall<Ext.ModelSelectEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  match call:
    case Ext.HandlerCall{Ext.ModelSelectEvent{model, previous, origin}, ctx}:
      do IO<Result<&2, &2, String, Maybe<&2, Unit>>>:
        current : Maybe<&2, Ai.Model<Ai.JsonValue>> <- Ctx.model(ctx)
        add(items, "model:" ++ source(origin) ++ ":" ++ key(previous) ++ "->" ++ Models.reference(model) ++ ":" ++ key(current))
        return Done{None{}}

def seenThinking(trace: Trace, call: Ext.HandlerCall<Ext.ThinkingLevelSelectEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  match trace call:
    case Trace{items, started, release, completed, blocked, _} Ext.HandlerCall{Ext.ThinkingLevelSelectEvent{selected, previous}, +ctx}:
      do IO<Result<&2, &2, String, Maybe<&2, Unit>>>:
        waiting : Bool <- R.read(Bool, blocked)
        Bool.pick(Unit -> IO(Unit), waiting, _ => do IO<Unit>:
          sent : Bool <- Chan.send(Unit, started, Unit{})
          ready : Maybe<&1, Unit> <- Chan.recv(Unit, release)
          return Unit{}, _ => IO.pure(Unit, Unit{}))(Unit{})
        current : Ai.ModelThinkingLevel <- Ctx.thinkingLevel(ctx)
        selectedModel : Maybe<&2, Ai.Model<Ai.JsonValue>> <- Ctx.model(ctx)
        add(items, "thinking:" ++ level(previous) ++ "->" ++ level(selected) ++ ":" ++ level(current) ++ ":" ++ key(selectedModel))
        finished : Bool <- Chan.send(Unit, completed, Unit{})
        return Done{None{}}

def registrations(items: List<&2, Result<&2, &2, String, Loader.Unsubscribe>>) -> Result<&2, &2, String, Unit>:
  match items:
    case Nil{}: Done{Unit{}}
    case Fail{message} <> _: Fail{message}
    case Done{_} <> rest: registrations(rest)

def factoryWith(+trace: Trace, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match trace:
    case Trace{+items, _, _, _, _, apiSlot}:
      do IO<Result<&2, &2, String, Unit>>:
        getter : Result<&2, &2, String, Ai.ModelThinkingLevel> <- Loader.getThinkingLevel(api)
        setter : Result<&2, &2, String, Unit> <- Loader.setThinkingLevel(api, Ai.Thinking{Ai.High{}})
        check(Result.is_fail(&2, &2, String, Ai.ModelThinkingLevel, getter) && Result.is_fail(&2, &2, String, Unit, setter), "extension thinking actions reject calls during loading")
        R.write(Maybe<&2, Ext.ExtensionAPI>, apiSlot, Some{api})
        modelBad : Ext.ExtensionHandler(Ext.ModelSelectEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ModelSelectEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~failedModel, Unit{})
        modelGood : Ext.ExtensionHandler(Ext.ModelSelectEvent, Unit) <- C.create(~R.Ref<List<&2, String>>, ~Ext.HandlerCall<Ext.ModelSelectEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~seenModel, items)
        thinkingBad : Ext.ExtensionHandler(Ext.ThinkingLevelSelectEvent, Unit) <- C.create(~Unit, ~Ext.HandlerCall<Ext.ThinkingLevelSelectEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~failedThinking, Unit{})
        thinkingGood : Ext.ExtensionHandler(Ext.ThinkingLevelSelectEvent, Unit) <- C.create(~Trace, ~Ext.HandlerCall<Ext.ThinkingLevelSelectEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~seenThinking, trace)
        one : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnModelSelect{modelBad})
        two : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnModelSelect{modelGood})
        three : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnThinkingLevelSelect{thinkingBad})
        four : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnThinkingLevelSelect{thinkingGood})
        return registrations([one, two, three, four])

def factory(trace: Trace, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): factoryWith(trace, api)

def recordError(slot: R.Ref<List<&2, Ext.ExtensionError>>, error: Ext.ExtensionError) -> IO(Unit):
  R.modify(List<&2, Ext.ExtensionError>, Unit, slot, prior => (List.append(&2, Ext.ExtensionError, prior, [error]), Unit{}))

def requiredRunner(found: Maybe<&2, Runner.ExtensionRunner>) -> IO(Runner.ExtensionRunner):
  match found:
    case Some{runner}: IO.pure(Runner.ExtensionRunner, runner)
    case None{}: IO.die(Runner.ExtensionRunner, 1, "missing extension runner")

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, value): value

def has(items: List<&2, String>, +wanted: String) -> Bool:
  match items:
    case Nil{}: False{}
    case item <> rest: String.eq(item, wanted) || has(rest, wanted)

def oneError(errors: List<&2, Ext.ExtensionError>, kind: String, message: String) -> Bool:
  match errors:
    case Ext.ExtensionError{_, event, failure, _} <> Nil{}: String.eq(event, kind) && String.contains(failure, message)
    case _: False{}

def twoErrors(errors: List<&2, Ext.ExtensionError>) -> Bool:
  match errors:
    case Ext.ExtensionError{_, "thinking_level_select", thinking, _} <> Ext.ExtensionError{_, "model_select", model, _} <> Nil{}: String.contains(thinking, "thinking handler boom") && String.contains(model, "model handler boom")
    case Ext.ExtensionError{_, "model_select", model, _} <> Ext.ExtensionError{_, "thinking_level_select", thinking, _} <> Nil{}: String.contains(thinking, "thinking handler boom") && String.contains(model, "model handler boom")
    case _: False{}

def changes(entries: List<&2, Manager.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case Manager.ModelChangeEntry{_, provider, id} <> rest: (provider ++ "/" ++ id) <> changes(rest)
    case _ <> rest: changes(rest)

def transcript(live: Session.AgentSession) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    session : Session.Session() <- Session.sessionOf(live)
    return changes(Manager.getEntries(V.Value, Tools.ToolDetails, V.Value, Persistence.stateOf(V.Value, Tools.ToolDetails, V.Value, session)))

def appendedChange(before: List<&2, String>, after: List<&2, String>) -> Bool:
  match before after:
    case Nil{} "capture-provider/two" <> Nil{}: True{}
    case first <> rest observed <> tail: String.eq(first, observed) && appendedChange(rest, tail)
    case _ _: False{}

def rejected(result: Result<&2, &2, String, Unit>) -> Bool:
  match result:
    case Fail{message}: String.contains(message, "No API key")
    case _: False{}

def good(result: Result<&2, &2, String, Unit>) -> Bool:
  match result:
    case Done{_}: True{}
    case _: False{}

def requiredApi(found: Maybe<&2, Ext.ExtensionAPI>) -> IO(Ext.ExtensionAPI):
  match found:
    case Some{api}: IO.pure(Ext.ExtensionAPI, api)
    case None{}: IO.die(Ext.ExtensionAPI, 1, "missing extension API")
def levelResult(value: Result<&2, &2, String, Ai.ModelThinkingLevel>) -> String:
  match value:
    case Done{selected}: level(selected)
    case Fail{_}: "error"
def entries(live: Session.AgentSession) -> IO(Nat):
  do IO<Nat>:
    stored : Session.Session() <- Session.sessionOf(live)
    return List.length(&2, Manager.SessionEntry<V.Value, Tools.ToolDetails, V.Value>, Manager.getEntries(V.Value, Tools.ToolDetails, V.Value, Persistence.stateOf(V.Value, Tools.ToolDetails, V.Value, stored)))
def thinkingActions(+api: Ext.ExtensionAPI, +live: Session.AgentSession, +a: Ai.Model<Ai.JsonValue>, +b: Ai.Model<Ai.JsonValue>, +items: R.Ref<List<&2, String>>, +completed: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    start : Result<&2, &2, String, Ai.ModelThinkingLevel> <- Loader.getThinkingLevel(api)
    check(String.eq(levelResult(start), "off"), "extension getter reads the bound session thinking level")
    beforeEntries : Nat <- entries(live)
    changed : Result<&2, &2, String, Unit> <- Loader.setThinkingLevel(api, Ai.Thinking{Ai.High{}})
    event : Maybe<&1, Unit> <- Chan.recv(Unit, completed)
    read : Result<&2, &2, String, Ai.ModelThinkingLevel> <- Loader.getThinkingLevel(api)
    +afterEntries : Nat <- entries(live)
    +priorEvents : List<&2, String> <- R.read(List<&2, String>, items)
    defaults : Settings.SettingsManager <- R.read(Settings.SettingsManager, Session.settingsOf(live))
    check(good(changed) && String.eq(levelResult(read), "high") && Nat.is_eq(afterEntries, beforeEntries + 1n) && has(priorEvents, "thinking:off->high:high:capture-provider/one") && Maybe.is_none(&2, Ai.ModelThinkingLevel, Settings.getDefaultThinkingLevel(defaults)), "extension setter records and announces the session level without changing defaults")
    same : Result<&2, &2, String, Unit> <- Loader.setThinkingLevel(api, Ai.Thinking{Ai.High{}})
    afterSame : Nat <- entries(live)
    currentEvents : List<&2, String> <- R.read(List<&2, String>, items)
    check(good(same) && Nat.is_eq(afterSame, afterEntries) && Nat.is_eq(List.length(&2, String, currentEvents), List.length(&2, String, priorEvents)), "extension no-op thinking change records and emits nothing")
    switched : Result<&2, &2, String, Bool> <- Loader.setModel(api, b)
    switchEvent : Maybe<&1, Unit> <- Chan.recv(Unit, completed)
    +beforeClamp : Nat <- entries(live)
    clamped : Result<&2, &2, String, Unit> <- Loader.setThinkingLevel(api, Ai.Thinking{Ai.High{}})
    off : Result<&2, &2, String, Ai.ModelThinkingLevel> <- Loader.getThinkingLevel(api)
    afterClamp : Nat <- entries(live)
    check(good(clamped) && String.eq(levelResult(off), "off") && Nat.is_eq(beforeClamp, afterClamp), "extension thinking setter clamps to current model capabilities")
    restored : Result<&2, &2, String, Bool> <- Loader.setModel(api, a)
    check(Result.is_done(&2, &2, String, Bool, restored), "extension model actions remain bound after thinking changes")

def checked(pair: Sdk.CreateAgentSessionResult & Session.AgentSession, models: Models.ModelRuntime, +a: Ai.Model<Ai.JsonValue>, +b: Ai.Model<Ai.JsonValue>, +trace: Trace, +errors: R.Ref<List<&2, Ext.ExtensionError>>, loader: Resources.DefaultResourceLoader) -> IO(Unit):
  match pair trace:
    case Tuple{owner, +live} Trace{+items, started, release, +completed, +blocked, +apiSlot}:
      do IO<Unit>:
        found : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(live)
        +runner : Runner.ExtensionRunner <- requiredRunner(found)
        +listener : C.Callback<Ext.ExtensionError, Unit> <- C.create(~R.Ref<List<&2, Ext.ExtensionError>>, ~Ext.ExtensionError, ~Unit, ~recordError, errors)
        subscription : Runner.ErrorSubscription <- Runner.onError(runner, listener)
        beforeModel : List<&2, String> <- transcript(live)
        R.write(Bool, blocked, True{})
        high : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.High{}}, Session.ModelMutationOptions{False{}})
        begun : Maybe<&1, Unit> <- Chan.recv(Unit, started)
        highState : Session.AgentState() <- Session.state(live)
        check(good(high) && String.eq(level(Session.stateThinking(highState)), "high"), "setThinkingLevel returns before a blocked thinking handler and exposes updated state")
        released : Bool <- Chan.send(Unit, release, Unit{})
        finishedHigh : Maybe<&1, Unit> <- Chan.recv(Unit, completed)
        highEvents : List<&2, String> <- R.read(List<&2, String>, items)
        highErrors : List<&2, Ext.ExtensionError> <- R.read(List<&2, Ext.ExtensionError>, errors)
        check(has(highEvents, "thinking:off->high:high:capture-provider/one") && oneError(highErrors, "thinking_level_select", "thinking handler boom"), "thinking selection isolates a failing handler")
        R.write(Bool, blocked, False{})
        R.write(List<&2, Ext.ExtensionError>, errors, Nil{})
        +beforeSame : List<&2, String> <- R.read(List<&2, String>, items)
        same : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.High{}}, Session.ModelMutationOptions{False{}})
        afterSame : List<&2, String> <- R.read(List<&2, String>, items)
        check(good(same) && Nat.is_eq(List.length(&2, String, beforeSame), List.length(&2, String, afterSame)), "unchanged thinking level emits no selection event")
        first : Result<&2, &2, String, Unit> <- Session.setModel(live, b, Session.ModelMutationOptions{False{}})
        completedSwitch : Maybe<&1, Unit> <- Chan.recv(Unit, completed)
        +initial : List<&2, String> <- R.read(List<&2, String>, items)
        recorded : List<&2, String> <- transcript(live)
        +defaults : Settings.SettingsManager <- R.read(Settings.SettingsManager, Session.settingsOf(live))
        check(good(first) && has(initial, "model:set:capture-provider/one->capture-provider/two:capture-provider/two") && appendedChange(beforeModel, recorded) && Maybe.is_none(&2, String, Settings.getDefaultProvider(defaults)) && Maybe.is_none(&2, String, Settings.getDefaultModel(defaults)), "setModel saves the model to the session and emits model_select")
        check(has(initial, "thinking:high->off:off:capture-provider/two"), "model switch clamps thinking and reports effective previous and current levels")
        switchErrors : List<&2, Ext.ExtensionError> <- R.read(List<&2, Ext.ExtensionError>, errors)
        check(twoErrors(switchErrors), "model and thinking handler failures remain isolated")
        +beforeMetadata : List<&2, String> <- R.read(List<&2, String>, items)
        metadata : Result<&2, &2, String, Unit> <- Session.setModel(live, model("two", "Updated Two", "capture-provider", False{}), Session.ModelMutationOptions{False{}})
        afterMetadata : List<&2, String> <- R.read(List<&2, String>, items)
        check(good(metadata) && Nat.is_eq(List.length(&2, String, beforeMetadata), List.length(&2, String, afterMetadata)), "same provider and id with changed metadata does not notify")
        cycled : Result<&2, &2, String, Maybe<&2, Session.ModelCycleResult>> <- Session.cycleModel(live, Session.Forward{}, Session.ModelMutationOptions{False{}})
        cycleEvents : List<&2, String> <- R.read(List<&2, String>, items)
        check(Result.is_done(&2, &2, String, Maybe<&2, Session.ModelCycleResult>, cycled) && has(cycleEvents, "model:cycle:capture-provider/two->capture-provider/one:capture-provider/one"), "cycleModel reports cycle source and previous current model")
        +beforeReject : List<&2, String> <- R.read(List<&2, String>, items)
        failed : Result<&2, &2, String, Unit> <- Session.setModel(live, model("unknown", "Unknown", "unconfigured-provider", True{}), Session.ModelMutationOptions{False{}})
        afterReject : List<&2, String> <- R.read(List<&2, String>, items)
        check(rejected(failed) && Nat.is_eq(List.length(&2, String, beforeReject), List.length(&2, String, afterReject)), "auth failure emits no model selection")
        +api : Ext.ExtensionAPI <- IO.bind(Maybe<&2, Ext.ExtensionAPI>, Ext.ExtensionAPI, R.read(Maybe<&2, Ext.ExtensionAPI>, apiSlot), requiredApi)
        thinkingActions(api, live, a, b, items, completed)
        Runner.offError(runner, subscription)
        C.dispose(Ext.ExtensionError, Unit, listener)
        R.write(Bool, blocked, True{})
        shutdownChange : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.High{}}, Session.ModelMutationOptions{False{}})
        shutdownStarted : Maybe<&1, Unit> <- Chan.recv(Unit, started)
        Sdk.dispose(owner)
        shutdownReleased : Bool <- Chan.send(Unit, release, Unit{})
        shutdownCompleted : Maybe<&1, Unit> <- Chan.recv(Unit, completed)
        afterShutdown : List<&2, String> <- R.read(List<&2, String>, items)
        check(good(shutdownChange) && has(afterShutdown, "thinking:off->high:off:none"), "detached thinking handler can finish after SDK disposal")
        staleGet : Result<&2, &2, String, Ai.ModelThinkingLevel> <- Loader.getThinkingLevel(api)
        staleSet : Result<&2, &2, String, Unit> <- Loader.setThinkingLevel(api, Ai.Thinking{Ai.Low{}})
        check(Result.is_fail(&2, &2, String, Ai.ModelThinkingLevel, staleGet) && Result.is_fail(&2, &2, String, Unit, staleSet), "retired extension thinking actions reject before accessing disposed session callbacks")
        Resources.disposeDefaultResourceLoader(loader)
        IO.print("ok SDK model events disposed")

def finished(result: Sdk.Outcome(), models: Models.ModelRuntime, a: Ai.Model<Ai.JsonValue>, b: Ai.Model<Ai.JsonValue>, trace: Trace, errors: R.Ref<List<&2, Ext.ExtensionError>>, loader: Resources.DefaultResourceLoader) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{owner}: checked(Sdk.sessionOf(owner), models, a, b, trace, errors, loader)

def run(+directory: String) -> IO(Unit):
  do IO<Unit>:
    +items : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +errors : R.Ref<List<&2, Ext.ExtensionError>> <- R.new(List<&2, Ext.ExtensionError>, Nil{})
    +blocked : R.Ref<Bool> <- R.new(Bool, False{})
    +started : Chan(Unit) <- Chan.new(Unit, 4)
    +release : Chan(Unit) <- Chan.new(Unit, 4)
    +completed : Chan(Unit) <- Chan.new(Unit, 4)
    +apiSlot : R.Ref<Maybe<&2, Ext.ExtensionAPI>> <- R.new(Maybe<&2, Ext.ExtensionAPI>, None{})
    +trace : Trace = Trace{items, started, release, completed, blocked, apiSlot}
    factoryHandle : Ext.ExtensionFactory() <- C.create(~Trace, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~factory, trace)
    +a : Ai.Model<Ai.JsonValue> = model("one", "One", "capture-provider", True{})
    +b : Ai.Model<Ai.JsonValue> = model("two", "Two", "capture-provider", False{})
    +store : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- AuthContext.defaultProviderAuthContext()
    +models : Models.ModelRuntime <- Models.fromProviders(Nil{}, store, context)
    native : AiModels.Provider <- provider([a, b])
    registered : Result<&2, &2, String, Unit> <- Models.registerNativeProviderStream(models, native, None{})
    authorized : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.setRuntimeApiKey(models, "capture-provider", "test-key", None{})
    pair : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(directory, directory, Settings.options())
    +settings : Settings.SettingsManager = settingsOf(pair)
    +loader : Resources.DefaultResourceLoader <- Resources.createDefaultResourceLoader(Paths.Environment{directory, directory, Runtime.urlContext()}, Resources.defaultResourceLoaderOptions(directory, directory, settings), [Ext.InlineExtension{"model-events", factoryHandle, False{}}])
    Resources.reload(Resources.loaderOf(loader), Resources.ResourceLoaderReloadOptions{None{}})
    created : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{directory}, Some{directory}, Some{models}, Some{a}, Some{Ai.Off{}}, Nil{}, None{}, None{}, None{}, Some{Resources.loaderOf(loader)}, None{}, Some{settings}, Nil{}, None{}})
    finished(created, models, a, b, trace, errors, loader)
    Models.dispose(models)
    Auth.disposeStore(store)
    prior : List<&2, String> <- R.dispose(List<&2, String>, items)
    priorErrors : List<&2, Ext.ExtensionError> <- R.dispose(List<&2, Ext.ExtensionError>, errors)
    retiredApi : Maybe<&2, Ext.ExtensionAPI> <- R.dispose(Maybe<&2, Ext.ExtensionAPI>, apiSlot)
    wasBlocked : Bool <- R.dispose(Bool, blocked)
    Chan.close(Unit, started)
    Chan.close(Unit, release)
    Chan.close(Unit, completed)
    return Unit{}

def maybeLevel(value: Maybe<&2, Ai.ModelThinkingLevel>) -> String:
  match value:
    case None{}: "none"
    case Some{found}: level(found)

def cycleLevel(value: Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>>) -> String:
  match value:
    case Fail{error}: error
    case Done{found}: maybeLevel(found)

def levelNames(values: List<&2, Ai.ModelThinkingLevel>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: level(value) <> levelNames(rest)

def extendedModel(value: Ai.Model<Ai.JsonValue>) -> Ai.Model<Ai.JsonValue>:
  match value:
    case Ai.Model{id, name, api, provider, url, reasoning, _, input, limits, cost, cache, window, tokens, sampling, headers, compat}:
      Ai.Model{id, name, api, provider, url, reasoning, Some{Ai.ThinkingLevelMap{[Ai.ThinkingLevelMapping{Ai.Thinking{Ai.XHigh{}}, Some{Ai.PresentValue{"xhigh"}}}, Ai.ThinkingLevelMapping{Ai.Thinking{Ai.Max{}}, Some{Ai.PresentValue{"max"}}}]}}, input, limits, cost, cache, window, tokens, sampling, headers, compat}

# Run related contracts on one real SDK session, resetting the relevant
# settings and scope at each boundary. No provider request is needed.
def defaultsChecked(pair: Sdk.CreateAgentSessionResult & Session.AgentSession, +a: Ai.Model<Ai.JsonValue>, +b: Ai.Model<Ai.JsonValue>, +c: Ai.Model<Ai.JsonValue>) -> IO(Unit):
  match pair:
    case (owner, +live):
      do IO<Unit>:
        initialHigh : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.High{}}, Session.ModelMutationOptions{False{}})
        fallback : Result<&2, &2, String, Unit> <- Session.setModel(live, c, Session.ModelMutationOptions{False{}})
        high : Ai.ModelThinkingLevel <- Session.getThinkingLevel(live)
        check(good(initialHigh) && good(fallback) && String.eq(level(high), "high"), "falls back to current session thinking level when no per-model or global default is configured")
        lowOnly : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.Low{}}, Session.ModelMutationOptions{False{}})
        +unsaved : Settings.SettingsManager <- R.read(Settings.SettingsManager, Session.settingsOf(live))
        saveModel : Result<&2, &2, String, Unit> <- Session.setModel(live, c, Session.ModelMutationOptions{True{}})
        saveThinking : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.High{}}, Session.ModelMutationOptions{True{}})
        +saved : Settings.SettingsManager <- R.read(Settings.SettingsManager, Session.settingsOf(live))
        check(good(lowOnly) && good(saveModel) && good(saveThinking) && Maybe.is_none(&2, String, Settings.getDefaultProvider(unsaved)) && Maybe.is_none(&2, String, Settings.getDefaultModel(unsaved)) && Maybe.is_none(&2, Ai.ModelThinkingLevel, Settings.getDefaultThinkingLevel(unsaved)) && String.eq(Maybe.default(&2, String, Settings.getDefaultProvider(saved), ""), "capture-provider") && String.eq(Maybe.default(&2, String, Settings.getDefaultModel(saved), ""), "three") && String.eq(maybeLevel(Settings.getDefaultThinkingLevel(saved)), "high"), "only persists model and thinking defaults when requested")
        saveMax : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.Max{}}, Session.ModelMutationOptions{True{}})
        clamped : Ai.ModelThinkingLevel <- Session.getThinkingLevel(live)
        maxSettings : Settings.SettingsManager <- R.read(Settings.SettingsManager, Session.settingsOf(live))
        check(good(saveMax) && String.eq(level(clamped), "high") && String.eq(maybeLevel(Settings.getDefaultThinkingLevel(maxSettings)), "max"), "persists the requested default thinking level even when the current model clamps it")
        configured : Result<&2, &2, String, Unit> <- Session.updateSettings(Session.settingsOf(live), current => Settings.setDefaultModelAndProvider("capture-provider", "one", current))
        defaultLow : Result<&2, &2, String, Unit> <- Session.updateSettings(Session.settingsOf(live), current => Settings.setDefaultThinkingLevel(Ai.Thinking{Ai.Low{}}, current))
        Session.setScopedModels(live, [Models.ScopedModel{a, None{}}, Models.ScopedModel{c, None{}}])
        reset : Result<&2, &2, String, Unit> <- Session.setModel(live, a, Session.ModelMutationOptions{False{}})
        next : Result<&2, &2, String, Maybe<&2, Session.ModelCycleResult>> <- Session.cycleModel(live, Session.Forward{}, Session.ModelMutationOptions{False{}})
        +cycledState : Session.AgentState() <- Session.state(live)
        off : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Off{}, Session.ModelMutationOptions{False{}})
        minimal : Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>> <- Session.cycleThinkingLevel(live, Session.ModelMutationOptions{False{}})
        +cycleSettings : Settings.SettingsManager <- R.read(Settings.SettingsManager, Session.settingsOf(live))
        check(good(configured) && good(defaultLow) && good(reset) && Result.is_done(&2, &2, String, Maybe<&2, Session.ModelCycleResult>, next) && String.eq(key(Session.stateModel(cycledState)), "capture-provider/three") && good(off) && String.eq(cycleLevel(minimal), "minimal") && String.eq(Maybe.default(&2, String, Settings.getDefaultModel(cycleSettings), ""), "one") && String.eq(maybeLevel(Settings.getDefaultThinkingLevel(cycleSettings)), "low"), "cycleModel and cycleThinkingLevel are session-only by default")
        Session.setScopedModels(live, Nil{})
        medium : Result<&2, &2, String, Unit> <- Session.updateSettings(Session.settingsOf(live), current => Settings.setDefaultThinkingLevel(Ai.Thinking{Ai.Medium{}}, current))
        override : Result<&2, &2, String, Unit> <- Session.updateSettings(Session.settingsOf(live), current => Settings.setModelThinkingLevel("capture-provider", "three", Ai.Thinking{Ai.Low{}}, current))
        priorModel : Result<&2, &2, String, Unit> <- Session.setModel(live, a, Session.ModelMutationOptions{False{}})
        highAgain : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.High{}}, Session.ModelMutationOptions{False{}})
        perModel : Result<&2, &2, String, Unit> <- Session.setModel(live, c, Session.ModelMutationOptions{False{}})
        selectedLow : Ai.ModelThinkingLevel <- Session.getThinkingLevel(live)
        global : Result<&2, &2, String, Unit> <- Session.setModel(live, a, Session.ModelMutationOptions{False{}})
        selectedMedium : Ai.ModelThinkingLevel <- Session.getThinkingLevel(live)
        check(good(priorModel) && good(medium) && good(override) && good(highAgain) && good(perModel) && good(global) && String.eq(level(selectedLow), "low") && String.eq(level(selectedMedium), "medium"), "applies per-model thinking level override on model switch")
        highDefault : Result<&2, &2, String, Unit> <- Session.updateSettings(Session.settingsOf(live), current => Settings.setDefaultThinkingLevel(Ai.Thinking{Ai.High{}}, current))
        minimalOverride : Result<&2, &2, String, Unit> <- Session.updateSettings(Session.settingsOf(live), current => Settings.setModelThinkingLevel("capture-provider", "three", Ai.Thinking{Ai.Minimal{}}, current))
        preferred : Result<&2, &2, String, Unit> <- Session.setModel(live, c, Session.ModelMutationOptions{False{}})
        selectedMinimal : Ai.ModelThinkingLevel <- Session.getThinkingLevel(live)
        check(good(highDefault) && good(minimalOverride) && good(preferred) && String.eq(level(selectedMinimal), "minimal"), "per-model override takes priority over global default during model switch")
        Session.setScopedModels(live, [Models.ScopedModel{a, Some{Ai.Thinking{Ai.High{}}}}, Models.ScopedModel{b, None{}}])
        scopeStart : Result<&2, &2, String, Unit> <- Session.setModel(live, a, Session.ModelMutationOptions{False{}})
        scopeNext : Result<&2, &2, String, Maybe<&2, Session.ModelCycleResult>> <- Session.cycleModel(live, Session.Forward{}, Session.ModelMutationOptions{False{}})
        +nonThinking : Session.AgentState() <- Session.state(live)
        scopeBack : Result<&2, &2, String, Maybe<&2, Session.ModelCycleResult>> <- Session.cycleModel(live, Session.Forward{}, Session.ModelMutationOptions{False{}})
        +thinking : Session.AgentState() <- Session.state(live)
        check(good(scopeStart) && Result.is_done(&2, &2, String, Maybe<&2, Session.ModelCycleResult>, scopeNext) && Result.is_done(&2, &2, String, Maybe<&2, Session.ModelCycleResult>, scopeBack) && String.eq(key(Session.stateModel(nonThinking)), "capture-provider/two") && String.eq(level(Session.stateThinking(nonThinking)), "off") && String.eq(key(Session.stateModel(thinking)), "capture-provider/one") && String.eq(level(Session.stateThinking(thinking)), "high"), "cycles through scoped models and preserves the scoped thinking preference")
        noReasoning : Result<&2, &2, String, Unit> <- Session.setModel(live, b, Session.ModelMutationOptions{False{}})
        unsupported : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.High{}}, Session.ModelMutationOptions{False{}})
        stillOff : Ai.ModelThinkingLevel <- Session.getThinkingLevel(live)
        noCycle : Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>> <- Session.cycleThinkingLevel(live, Session.ModelMutationOptions{False{}})
        check(good(noReasoning) && good(unsupported) && String.eq(level(stillOff), "off") && String.eq(cycleLevel(noCycle), "none"), "clamps thinking levels to model capabilities and cycles available levels")
        extended : Result<&2, &2, String, Unit> <- Session.setModel(live, extendedModel(a), Session.ModelMutationOptions{False{}})
        available : List<&2, Ai.ModelThinkingLevel> <- Session.getAvailableThinkingLevels(live)
        fromHigh : Result<&2, &2, String, Unit> <- Session.setThinkingLevel(live, Ai.Thinking{Ai.High{}}, Session.ModelMutationOptions{False{}})
        xhigh : Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>> <- Session.cycleThinkingLevel(live, Session.ModelMutationOptions{False{}})
        max : Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>> <- Session.cycleThinkingLevel(live, Session.ModelMutationOptions{False{}})
        wrap : Result<&2, &2, String, Maybe<&2, Ai.ModelThinkingLevel>> <- Session.cycleThinkingLevel(live, Session.ModelMutationOptions{False{}})
        check(good(extended) && good(fromHigh) && String.eq(String.join(levelNames(available), ","), "off,minimal,low,medium,high,xhigh,max") && String.eq(cycleLevel(xhigh), "xhigh") && String.eq(cycleLevel(max), "max") && String.eq(cycleLevel(wrap), "off"), "cycles xhigh before max when both are supported")
        Sdk.dispose(owner)

def defaultsFinished(result: Sdk.Outcome(), a: Ai.Model<Ai.JsonValue>, b: Ai.Model<Ai.JsonValue>, c: Ai.Model<Ai.JsonValue>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{owner}: defaultsChecked(Sdk.sessionOf(owner), a, b, c)

def defaultContracts(+directory: String) -> IO(Unit):
  do IO<Unit>:
    +a : Ai.Model<Ai.JsonValue> = model("one", "One", "capture-provider", True{})
    +b : Ai.Model<Ai.JsonValue> = model("two", "Two", "capture-provider", False{})
    +c : Ai.Model<Ai.JsonValue> = model("three", "Three", "capture-provider", True{})
    +store : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- AuthContext.defaultProviderAuthContext()
    +models : Models.ModelRuntime <- Models.fromProviders(Nil{}, store, context)
    native : AiModels.Provider <- provider([a, b, c])
    registered : Result<&2, &2, String, Unit> <- Models.registerNativeProviderStream(models, native, None{})
    authorized : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.setRuntimeApiKey(models, "capture-provider", "test-key", None{})
    created : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{directory}, Some{directory}, Some{models}, Some{a}, Some{Ai.Off{}}, Nil{}, None{}, Some{Nil{}}, None{}, None{}, None{}, None{}, Nil{}, None{}})
    defaultsFinished(created, a, b, c)
    Models.dispose(models)
    Auth.disposeStore(store)

def runArgs(args: List<String>) -> IO(Unit):
  match args:
    case +directory <> Nil{}:
      do IO<Unit>:
        run(directory)
        defaultContracts(directory)
    case _: IO.die(Unit, 1, "expected isolated directory")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    runArgs(args)
