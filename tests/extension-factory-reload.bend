import Base
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/resource-loader.bend as Resources
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/types.bend as T

# Native inline factories are reusable handles. The resource loader owns the
# handles, while each returned runtime remains valid for its runner.
def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def increment(+n: Nat) -> Nat & Nat: (n + 1n, n + 1n)
def next(n: Nat) -> Nat & Nat: increment(n)

def counted(calls: R.Ref<Nat>, api: T.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    count : Nat <- R.modify(Nat, Nat, calls, next)
    Loader.registerFlag(api, "load-" ++ Nat.show(count), T.FlagOptions{None{}, T.BooleanFlag{}, None{}})

def fails(message: String, api: T.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  IO.pure(Result<&2, &2, String, Unit>, Fail{message})

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, value): value

def runtimeOf(result: Resources.LoadExtensionsResult) -> T.ExtensionRuntime():
  match result:
    case Resources.LoadExtensionsResult{_, _, runtime}: runtime

def extensionsOf(result: Resources.LoadExtensionsResult) -> List<&2, T.Extension>:
  match result:
    case Resources.LoadExtensionsResult{extensions, _, _}: extensions

def errorsOf(result: Resources.LoadExtensionsResult) -> List<&2, T.LoadError>:
  match result:
    case Resources.LoadExtensionsResult{_, errors, _}: errors

def names(flags: List<&2, T.ExtensionFlag>) -> List<&2, String>:
  match flags:
    case Nil{}: Nil{}
    case T.ExtensionFlag{name, _, _, _, _} <> rest: name <> names(rest)

def flagNames(extensions: List<&2, T.Extension>) -> List<&2, String>:
  match extensions:
    case Nil{}: Nil{}
    case T.Extension{_, _, _, _, _, _, _, _, _, _, T.ExtensionExtras{flags, _, _, _}} <> rest: List.append(&2, String, names(flags), flagNames(rest))

def errorPaths(errors: List<&2, T.LoadError>) -> List<&2, String>:
  match errors:
    case Nil{}: Nil{}
    case T.LoadError{path, _} <> rest: path <> errorPaths(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    +calls : R.Ref<Nat> <- R.new(Nat, 0n)
    countedFactory : T.ExtensionFactory() <- C.create(~R.Ref<Nat>, ~T.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~counted, calls)
    badNamed : T.ExtensionFactory() <- C.create(~String, ~T.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~fails, "named failed")
    badBare : T.ExtensionFactory() <- C.create(~String, ~T.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~fails, "bare failed")
    settingsPair : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create("/tmp", "/tmp/pi-bend-factory-agent", Settings.options())
    +environment : Paths.Environment = Paths.Environment{"/tmp", "/tmp", urlContext()}
    +loader : Resources.DefaultResourceLoader <- Resources.createDefaultResourceLoader(environment, Resources.defaultResourceLoaderOptions("/tmp", "/tmp/pi-bend-factory-agent", settingsOf(settingsPair)), [T.InlineExtension{"counted", countedFactory, False{}}, T.InlineExtension{"bad", badNamed, False{}}, T.BareExtension{badBare}])
    +initial : Resources.LoadExtensionsResult <- Resources.getExtensions(Resources.loaderOf(loader))
    initialCalls : Nat <- R.read(Nat, calls)
    check(Nat.is_eq(initialCalls, 0n) && Nat.is_eq(List.length(&2, T.Extension, extensionsOf(initial)), 0n), "constructor defers factories")
    Resources.reload(Resources.loaderOf(loader), Resources.ResourceLoaderReloadOptions{None{}})
    +first : Resources.LoadExtensionsResult <- Resources.getExtensions(Resources.loaderOf(loader))
    firstCalls : Nat <- R.read(Nat, calls)
    check(Nat.is_eq(firstCalls, 1n) && String.eq(String.join(flagNames(extensionsOf(first)), ","), "load-1"), "first reload constructs fresh registrations once")
    check(String.eq(String.join(errorPaths(errorsOf(first)), ","), "<inline:bad>,<inline:3>"), "failed factories retain ordered paths")
    Resources.extendResources(Resources.loaderOf(loader), Resources.ResourceExtensionPaths{Nil{}, Nil{}, Nil{}})
    extended : Resources.LoadExtensionsResult <- Resources.getExtensions(Resources.loaderOf(loader))
    afterExtend : Nat <- R.read(Nat, calls)
    check(Nat.is_eq(afterExtend, 1n) && R.same(T.ExtensionRuntimeState, runtimeOf(first), runtimeOf(extended)), "extendResources preserves runtime without rerunning factories")
    Resources.reload(Resources.loaderOf(loader), Resources.ResourceLoaderReloadOptions{None{}})
    +second : Resources.LoadExtensionsResult <- Resources.getExtensions(Resources.loaderOf(loader))
    secondCalls : Nat <- R.read(Nat, calls)
    check(Nat.is_eq(secondCalls, 2n) && String.eq(String.join(flagNames(extensionsOf(second)), ","), "load-2") && Bool.not(R.same(T.ExtensionRuntimeState, runtimeOf(first), runtimeOf(second))), "second reload constructs a new runtime and state")
    check(String.eq(String.join(errorPaths(errorsOf(second)), ","), "<inline:bad>,<inline:3>"), "reload retains failure order")
    Resources.disposeDefaultResourceLoader(loader)
    old : T.ExtensionRuntimeState <- R.dispose(T.ExtensionRuntimeState, runtimeOf(initial))
    previous : T.ExtensionRuntimeState <- R.dispose(T.ExtensionRuntimeState, runtimeOf(first))
    current : T.ExtensionRuntimeState <- R.dispose(T.ExtensionRuntimeState, runtimeOf(second))
    count : Nat <- R.dispose(Nat, calls)
    return Unit{}
