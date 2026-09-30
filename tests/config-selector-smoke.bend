import Base
import ../packages/coding-agent/src/modes/interactive/components/config-selector.bend as Config
import ../packages/coding-agent/src/core/package-manager.bend as PackageManager
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/runtime/src/record.bend as Record

def manager() -> Settings.SettingsManager:
  +empty = {Settings.ScopedSettings{Settings.empty(), None{}, Nil{}} : Settings.ScopedSettings}
  Settings.initial(empty, empty, True{}, Settings.SettingsPaths{None{}, None{}})

def shownPaths(value: Settings.SettingsManager, scope: PackageManager.Scope) -> String:
  String.join(Config.pathsOf(value, scope, Config.Extensions{}), ",")

def changed(result: Settings.Outcome(Config.Changed)) -> String:
  match result:
    case Fail{_}: "error"
    case Done{Config.Changed{state, +manager}}: shownPaths(manager, PackageManager.UserScope{}) ++ "|" ++ shownPaths(manager, PackageManager.ProjectScope{}) ++ "|" ++ Nat.show(Config.selectedOf(state))

def namedPackagePaths(packages: List<&2, Settings.PackageSource>) -> String:
  match packages:
    case Settings.FilteredPackage{_, filter, _} <> _: String.join(Config.filterPaths(filter, Config.Extensions{}), ",")
    case _: "missing"

def packagePaths(manager: Settings.SettingsManager) -> String:
  namedPackagePaths(Config.packagesOf(manager, PackageManager.UserScope{}))

def changedPackage(result: Settings.Outcome(Config.Changed)) -> String:
  match result:
    case Fail{_}: "error"
    case Done{Config.Changed{_, manager}}: packagePaths(manager)

def packageChange(state: Config.State) -> Settings.Outcome(Config.Changed):
  Result.bind(&2, &2, Settings.Error, Settings.SettingsManager, Config.Changed,
    Settings.setPackages([Settings.PackageName{"pkg"}], manager()),
    configured => Config.changeSelected(Config.withSelected(state, 0n), configured, "/tmp", "/tmp/agent"))

def label(entry: Config.Entry) -> String:
  match entry:
    case Config.GroupHeader{name, _}: "group:" ++ name
    case Config.SubgroupHeader{kind, _}: "kind:" ++ Config.kindName(kind)
    case Config.ResourceRow{Config.Item{_, _, _, _, name, _, _}}: "item:" ++ name

def labels(entries: List<&2, Config.Entry>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: label(entry) <> labels(rest)

def require(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def projectPackages(manager: Settings.SettingsManager) -> Value.Value:
  Value.ArrayValue{Settings.encodeValues(~Settings.PackageSource, ~Settings.encodePackageSource, Config.packagesOf(manager, PackageManager.ProjectScope{}), Nil{})}

def expectedPackage(pattern: String) -> Value.Value:
  Value.ArrayValue{[Settings.encodePackageSource(Settings.FilteredPackage{"npm:pi-tools", Settings.PackageFilter{Some{False{}}, Some{[pattern]}, None{}, None{}, None{}}, Record.new(Value.Value)})]}

def cycleStep(result: Settings.Outcome(Config.Changed), expected: Value.Value) -> IO(Config.Changed):
  match result:
    case Fail{_}: IO.die(Config.Changed, 1, "cycles project package overrides in config local mode: update failed")
    case Done{Config.Changed{state, +manager}}:
      do IO<Config.Changed>:
        require(Value.equal(projectPackages(manager), expected), "cycles project package overrides in config local mode: settings mismatch")
        return Config.Changed{state, manager}

def cycleNext(changed: Config.Changed, expected: Value.Value) -> IO(Config.Changed):
  match changed:
    case Config.Changed{state, manager}: cycleStep(Config.changeSelected(state, manager, "/tmp/project", "/tmp/agent"), expected)

# Port of the identically named package-command-paths.test.ts assertion.
def packageOverrideCycle() -> IO(Unit):
  +metadata = {PackageManager.PathMetadata{PackageManager.Package{"npm:pi-tools"}, PackageManager.UserScope{}, Some{"/tmp/pkg"}} : PackageManager.PathMetadata}
  +paths = {PackageManager.ResolvedPaths{[PackageManager.ResolvedResource{"/tmp/pkg/extensions/bar.bend", True{}, metadata}], Nil{}, Nil{}, Nil{}} : PackageManager.ResolvedPaths}
  state = Config.initial(paths, paths, "/tmp/agent", "/tmp", True{}, Config.Project{}, 24n)
  first = Result.bind(&2, &2, Settings.Error, Settings.SettingsManager, Config.Changed,
    Settings.setPackages([Settings.PackageName{"npm:pi-tools"}], manager()),
    configured => Config.changeSelected(state, configured, "/tmp/project", "/tmp/agent"))
  do IO<Unit>:
    unloaded : Config.Changed <- cycleStep(first, expectedPackage("-extensions/bar.bend"))
    loaded : Config.Changed <- cycleNext(unloaded, expectedPackage("+extensions/bar.bend"))
    inherited : Config.Changed <- cycleNext(loaded, Value.ArrayValue{Nil{}})
    IO.print("cycles project package overrides in config local mode: ok")

def main() -> IO(Unit):
  +package = {PackageManager.PathMetadata{PackageManager.Package{"pkg"}, PackageManager.UserScope{}, Some{"/pkg"}} : PackageManager.PathMetadata}
  +local = {PackageManager.PathMetadata{PackageManager.Auto{}, PackageManager.UserScope{}, Some{"/tmp/agent/extensions"}} : PackageManager.PathMetadata}
  +global = {PackageManager.ResolvedPaths{[PackageManager.ResolvedResource{"/pkg/extensions/z.bend", True{}, package}, PackageManager.ResolvedResource{"/tmp/agent/extensions/a.bend", True{}, local}], Nil{}, [PackageManager.ResolvedResource{"/pkg/prompts/brief.md", True{}, package}], Nil{}} : PackageManager.ResolvedPaths}
  +state = Config.initial(global, global, "/tmp/agent", "/tmp", True{}, Config.Global{}, 24n)
  do IO<Unit>:
    IO.print(String.join(labels(Config.visible(state)), "|"))
    IO.print(String.join(labels(Config.visible(Config.search(state, "brief"))), "|"))
    IO.print(Nat.show(Config.selectedOf(Config.down(state))))
    IO.print(changed(Config.changeSelected(Config.withSelected(state, 2n), manager(), "/tmp", "/tmp/agent")))
    IO.print(changed(Config.changeSelected(Config.withSelected(Config.switchScope(state), 2n), manager(), "/tmp", "/tmp/agent")))
    IO.print(changedPackage(packageChange(state)))
    packageOverrideCycle()
