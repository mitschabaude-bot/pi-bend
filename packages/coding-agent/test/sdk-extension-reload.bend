import Base
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../src/utils/paths.bend as Paths
import ../src/core/agent-runtime.bend as Runtime
import ../src/core/agent-session.bend as Session
import ../src/core/sdk.bend as Sdk
import ../src/core/settings-manager.bend as Settings
import ../src/core/resource-loader.bend as Resources
import ../src/core/extensions/loader.bend as Loader
import ../src/core/extensions/runner.bend as Runner
import ../src/core/extensions/tool-context.bend as ToolContext
import ../src/core/extensions/types.bend as Ext

# The SDK borrows the resource loader; the loader owns its reusable factory.
type Evidence is Data:
  Evidence{calls: R.Ref<Nat>, events: R.Ref<List<&2, String>>}

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def increment(+n: Nat) -> Nat & Nat: (n + 1n, n + 1n)
def next(n: Nat) -> Nat & Nat: increment(n)

def recorded(events: R.Ref<List<&2, String>>, +value: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, events, current => (List.append(&2, String, current, [value]), Unit{}))

def onStart(events: R.Ref<List<&2, String>>, call: Ext.HandlerCall<Ext.SessionStartEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  match call:
    case Ext.HandlerCall{Ext.SessionStartEvent{Ext.ReloadStart{}, _}, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Unit>>>:
        recorded(events, "start")
        return Done{None{}}
    case _: IO.pure(Result<&2, &2, String, Maybe<&2, Unit>>, Done{None{}})

def onShutdown(events: R.Ref<List<&2, String>>, call: Ext.HandlerCall<Ext.SessionShutdownEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  do IO<Result<&2, &2, String, Maybe<&2, Unit>>>:
    recorded(events, "shutdown")
    return Done{None{}}

def subscriptions(results: List<&2, Result<&2, &2, String, Loader.Unsubscribe>>) -> Result<&2, &2, String, Unit>:
  match results:
    case Nil{}: Done{Unit{}}
    case Fail{error} <> _: Fail{error}
    case Done{_} <> rest: subscriptions(rest)

def factoryWith(env: Evidence, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match env:
    case Evidence{+calls, +events}:
      do IO<Result<&2, &2, String, Unit>>:
        count : Nat <- R.modify(Nat, Nat, calls, next)
        recorded(events, "factory-" ++ Nat.show(count))
        start : Ext.ExtensionHandler(Ext.SessionStartEvent, Unit) <- C.create(~R.Ref<List<&2, String>>, ~Ext.HandlerCall<Ext.SessionStartEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~onStart, events)
        shutdown : Ext.ExtensionHandler(Ext.SessionShutdownEvent, Unit) <- C.create(~R.Ref<List<&2, String>>, ~Ext.HandlerCall<Ext.SessionShutdownEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~onShutdown, events)
        flag : Result<&2, &2, String, Unit> <- Loader.registerFlag(api, "live", Ext.FlagOptions{None{}, Ext.BooleanFlag{}, Some{Ext.FlagBoolean{False{}}}})
        first : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnSessionShutdown{shutdown})
        second : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnSessionStart{start})
        return subscriptions([first, second])

def factory(env: Evidence, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>): factoryWith(env, api)

def before(events: R.Ref<List<&2, String>>, unit: Unit) -> IO(Unit): recorded(events, "before")
def ignore(unit: Unit, unused: Unit) -> IO(Unit): IO.pure(Unit, Unit{})

def required(found: Maybe<&2, Runner.ExtensionRunner>) -> IO(Runner.ExtensionRunner):
  match found:
    case Some{runner}: IO.pure(Runner.ExtensionRunner, runner)
    case None{}: IO.die(Runner.ExtensionRunner, 1, "missing extension runner")

def flagValue(settings: List<&2, Ext.FlagSetting>) -> Bool:
  match settings:
    case Nil{}: False{}
    case Ext.FlagSetting{"live", Ext.FlagBoolean{True{}}} <> _: True{}
    case _ <> rest: flagValue(rest)

def stableContext(loadout: Runtime.Loadout) -> ToolContext.ContextSource():
  match loadout:
    case Runtime.Loadout{_, _, _, _, _, _, Some{Runtime.LoadoutSource{_, _, _, _, Some{Runtime.ExtensionOwner{_, _, context}}}}, _}: context
    case _: None{}

def present(view: Maybe<&2, ToolContext.ContextView>) -> Bool:
  match view:
    case Some{_}: True{}
    case None{}: False{}

def completed(result: Result<&2, &2, String, Unit>) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, value): value

def checkedSession(pair: Sdk.CreateAgentSessionResult & Session.AgentSession, loader: Resources.DefaultResourceLoader, +calls: R.Ref<Nat>, +events: R.Ref<List<&2, String>>) -> IO(Unit):
  match pair:
    case Tuple{owned, +live}:
      do IO<Unit>:
        Session.bindExtensions(live, Ext.SessionStartEvent{Ext.StartupStart{}, None{}})
        oldFound : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(live)
        +old : Runner.ExtensionRunner <- required(oldFound)
        Runner.setFlagValue(old, "live", Ext.FlagBoolean{True{}})
        loadout : Runtime.Loadout <- Session.loadoutOf(live)
        +reader : ToolContext.ContextSource() = stableContext(loadout)
        +mode : C.Callback<Unit, Unit> <- C.create(~Unit, ~Unit, ~Unit, ~ignore, Unit{})
        Session.setShutdownHandler(live, mode)
        R.write(List<&2, String>, events, Nil{})
        +hook : C.Callback<Unit, Unit> <- C.create(~R.Ref<List<&2, String>>, ~Unit, ~Unit, ~before, events)
        outcome : Result<&2, &2, String, Unit> <- Session.reload(live, Some{Session.ReloadOptions{Some{hook}}})
        check(completed(outcome), "SDK session reload succeeds")
        count : Nat <- R.read(Nat, calls)
        history : List<&2, String> <- R.read(List<&2, String>, events)
        check(Nat.is_eq(count, 2n) && String.eq(String.join(history, ","), "shutdown,factory-2,before,start"), "reload lifecycle order and factory rerun")
        newFound : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(live)
        +new : Runner.ExtensionRunner <- required(newFound)
        currentFlags : List<&2, Ext.FlagSetting> <- Runner.getFlagValues(new)
        oldExtensions : List<&2, Ext.Extension> <- Runner.extensions(old)
        check(flagValue(currentFlags) && Nat.is_eq(List.length(&2, Ext.Extension, oldExtensions), 0n) && Bool.not(R.same(Ext.ExtensionRuntimeState, Runner.runtimeOf(old), Runner.runtimeOf(new))), "flag value survives and old runner is invalidated")
        Runner.dispose(old)
        context : Maybe<&2, ToolContext.ContextView> <- ToolContext.current(reader)
        check(present(context), "borrowed built-in tool context follows the new runner")
        C.dispose(Unit, Unit, hook)
        Sdk.dispose(owned)
        C.dispose(Unit, Unit, mode)
        Resources.disposeDefaultResourceLoader(loader)
        counted : Nat <- R.dispose(Nat, calls)
        recordedEvents : List<&2, String> <- R.dispose(List<&2, String>, events)
        IO.print("ok SDK, runner, loader, and factory disposed")

def finish(result: Sdk.Outcome(), loader: Resources.DefaultResourceLoader, calls: R.Ref<Nat>, events: R.Ref<List<&2, String>>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{owner}: checkedSession(Sdk.sessionOf(owner), loader, calls, events)

def run(+directory: String) -> IO(Unit):
  do IO<Unit>:
    +calls : R.Ref<Nat> <- R.new(Nat, 0n)
    +events : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    factoryHandle : Ext.ExtensionFactory() <- C.create(~Evidence, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~factory, Evidence{calls, events})
    settingsPair : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(directory, directory, Settings.options())
    +settings : Settings.SettingsManager = settingsOf(settingsPair)
    +loader : Resources.DefaultResourceLoader <- Resources.createDefaultResourceLoader(Paths.Environment{directory, directory, Runtime.urlContext()}, Resources.defaultResourceLoaderOptions(directory, directory, settings), [Ext.InlineExtension{"reload", factoryHandle, False{}}])
    Resources.reload(Resources.loaderOf(loader), Resources.ResourceLoaderReloadOptions{None{}})
    created : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{directory}, Some{directory}, None{}, None{}, None{}, Nil{}, None{}, None{}, None{}, Some{Resources.loaderOf(loader)}, None{}, Some{settings}, Nil{}, None{}})
    finish(created, loader, calls, events)

def runArgs(args: List<String>) -> IO(Unit):
  match args:
    case directory <> Nil{}: run(directory)
    case _: IO.die(Unit, 1, "expected isolated directory")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    runArgs(arguments)
