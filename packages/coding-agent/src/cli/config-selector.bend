import Base
import ../core/package-manager.bend as Package
import ../core/settings-manager.bend as Settings
import ../core/keybindings.bend as AppKeys
import ../core/project-trust.bend as ProjectTrust
import ../core/trust-manager.bend as Trust
import ../utils/paths.bend as Paths
import ../modes/interactive/components/config-selector.bend as Config
import ../modes/interactive/theme/theme.bend as Theme
import ../modes/interactive/theme/color.bend as Color
import ../modes/interactive/theme/detection.bend as Detection
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/deferred.bend as Deferred
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/serial-resource.bend as Serial
import ../../../runtime/src/word-segmenter.bend as Words
import ../../../tui/src/components/input.bend as Search
import ../../../tui/src/component.bend as Component
import ../../../tui/src/keybindings.bend as Bindings
import ../../../tui/src/keys.bend as Keys
import ../../../tui/src/word-navigation.bend as Word
import ../../../tui/src/tui-base.bend as Tui
import ../../../tui/src/tui-main-screen.bend as Screen
import ../../../tui/src/tui-process.bend as Process
import ../../../tui/src/terminal.bend as Terminal
import ../../../tui/src/terminal-image.bend as Image

type View is Data:
  View{state: Config.State, manager: Settings.SettingsManager, query: Search.Input, error: Maybe<&2, String>}
type Input is Data:
  Input{view: Ref.Ref<View>, words: Ref.Ref<Words.Source>, stop: Deferred.Deferred<Unit>, bindings: Bindings.KeybindingsManager, cwd: String, agentDir: String}
type Paint is Data:
  Paint{view: Ref.Ref<View>, theme: Theme.Theme, cwd: String, agentDir: String}
type Owner is Data:
  Owner{view: Ref.Ref<View>, words: Ref.Ref<Words.Source>, stop: Deferred.Deferred<Unit>, component: Component.Component, render: Callback.Callback<Nat, List<&2, String>>, input: Callback.Callback<String, Unit>, invalidate: Callback.Callback<Unit, Unit>, focus: Callback.Callback<Bool, Unit>}
type Action is Data:
  Up{} Down{} PageUp{} PageDown{} Toggle{} Switch{} Close{} Edit{}

def nonAtomic(_: Words.Source, _: String) -> Bool: False{}
def newSearch() -> Search.Input: Search.setFocused(Search.new(None{}), True{})
def searchLine(value: Search.Input & List<&2, String>) -> String:
  match value:
    case (_, line <> _): line
    case (_, Nil{}): ""

def renderView(view: View, theme: Theme.Theme, cwd: String, agentDir: String, +width: Nat) -> IO(List<&2, String>):
  match view:
    case View{state, manager, query, error}:
      do IO<List<&2, String>>:
        line : Search.Input & List<&2, String> <- Search.render(query, width)
        return List.append(&2, String, Config.lines(state, manager, cwd, agentDir, theme, width, searchLine(line)), Maybe.default(&2, List<&2, String>, Maybe.map(&2, String, List<&2, String>, message => [message], error), Nil{}))

def draw(paint: Paint, width: Nat) -> IO(List<&2, String>):
  match paint:
    case Paint{view, theme, cwd, agentDir}:
      do IO<List<&2, String>>:
        current : View <- Ref.read(View, view)
        renderView(current, theme, cwd, agentDir, width)

def bound(bindings: Bindings.KeybindingsManager, data: String, name: String) -> Bool:
  Bindings.matches(bindings, Keys.defaults(), data, name)

type Binding is Data: Binding{name: String, action: Action}
def actionBindings() -> List<&2, Binding>:
  [Binding{"tui.select.up", Up{}}, Binding{"tui.select.down", Down{}},
   Binding{"tui.select.pageUp", PageUp{}}, Binding{"tui.select.pageDown", PageDown{}},
   Binding{"tui.select.cancel", Close{}}, Binding{"tui.input.tab", Switch{}},
   Binding{"tui.select.confirm", Toggle{}}]
def boundAction(values: List<&2, Binding>, +bindings: Bindings.KeybindingsManager, +data: String) -> Action:
  match values:
    case Nil{}: Edit{}
    case Binding{name, selected} <> rest:
      Bool.pick(Unit -> Action, bound(bindings, data, name), _ => selected, _ => boundAction(rest, bindings, data))(Unit{})
def action(bindings: Bindings.KeybindingsManager, data: String) -> Action:
  match data:
    case "\u{3}": Close{}
    case " ": Toggle{}
    case other: boundAction(actionBindings(), bindings, other)

def moved(view: View, selected: Action) -> View:
  match view selected:
    case View{state, manager, query, error} Up{}: View{Config.up(state), manager, query, error}
    case View{state, manager, query, error} Down{}: View{Config.down(state), manager, query, error}
    case View{state, manager, query, error} PageUp{}: View{Config.page(state, False{}), manager, query, error}
    case View{state, manager, query, error} PageDown{}: View{Config.page(state, True{}), manager, query, error}
    case View{state, manager, query, error} Switch{}: View{Config.switchScope(state), manager, query, error}
    case current _: current

def savedView(state: Config.State, query: Search.Input, saved: Settings.SettingsManager & List<&2, Settings.SettingsError>) -> View:
  match saved:
    case (manager, Nil{}): View{state, manager, query, None{}}
    case (manager, _): View{state, manager, query, Some{"Could not save resource settings"}}

def changed(view: View, result: Settings.Outcome(Config.Changed)) -> IO(View):
  match view result:
    case View{_, _, query, _} Done{Config.Changed{state, manager}}:
      do IO<View>:
        saved : Settings.SettingsManager <- Settings.flushFiles(manager)
        return savedView(state, query, Settings.drainErrors(saved))
    case View{state, manager, query, _} Fail{_}: IO.pure(View, View{state, manager, query, Some{"Could not update resource settings"}})

def toggle(view: View, cwd: String, agentDir: String) -> IO(View):
  match view:
    case View{+state, +manager, query, error}:
      changed(View{state, manager, query, error}, Config.changeSelected(state, manager, cwd, agentDir))

def editQuery(+query: Search.Input, source: Words.Source, bindings: Bindings.KeybindingsManager, data: String) -> IO(Search.Input):
  do IO<Search.Input>:
    first : Word.ResultOf(Search.Input) <- Search.handleInput(~Words.Source, ~Word.sourceSegments, ~nonAtomic, source, query, bindings, Keys.defaults(), data)
    return Result.default(&2, &2, Word.Error, Search.Input, first, query)

def edited(view: View, +words: Ref.Ref<Words.Source>, bindings: Bindings.KeybindingsManager, data: String) -> IO(View):
  match view:
    case View{state, manager, +query, error}:
      do IO<View>:
        source : Words.Source <- Ref.read(Words.Source, words)
        +ready : Words.Source <- Words.readyFor(source, Search.getValue(query))
        Ref.write(Words.Source, words, ready)
        +updated : Search.Input <- editQuery(query, ready, bindings, data)
        return View{Config.search(state, Search.getValue(updated)), manager, updated, error}

def applyAction(input: Input, data: String, selected: Action) -> IO(Unit):
  match input selected:
    case Input{_, _, stop, _, _, _} Close{}:
      do IO<Unit>:
        resolved : Bool <- Deferred.resolve(Unit, stop, Unit{})
        return Unit{}
    case Input{+view, _, _, _, cwd, agentDir} Toggle{}:
      do IO<Unit>:
        current : View <- Ref.read(View, view)
        updated : View <- toggle(current, cwd, agentDir)
        Ref.write(View, view, updated)
    case Input{+view, words, _, bindings, _, _} Edit{}:
      do IO<Unit>:
        current : View <- Ref.read(View, view)
        updated : View <- edited(current, words, bindings, data)
        Ref.write(View, view, updated)
    case Input{view, _, _, _, _, _} movement:
      Ref.modify(View, Unit, view, current => (moved(current, movement), Unit{}))

def receivedShared(input: Input, +data: String) -> IO(Unit):
  match input:
    case Input{view, words, stop, +bindings, cwd, agentDir}:
      applyAction(Input{view, words, stop, bindings, cwd, agentDir}, data, action(bindings, data))

def received(input: Input, data: String) -> IO(Unit): receivedShared(input, data)

def ignore(_: Unit, _: Unit) -> IO(Unit): IO.pure(Unit, Unit{})
def unfocused(_: Unit, _: Bool) -> IO(Unit): IO.pure(Unit, Unit{})

def new(state: Config.State, manager: Settings.SettingsManager, theme: Theme.Theme, +bindings: Bindings.KeybindingsManager, +cwd: String, +agentDir: String, assetsRoot: String) -> IO(Owner):
  do IO<Owner>:
    +view : Ref.Ref<View> <- Ref.new(View, View{state, manager, newSearch(), None{}})
    +words : Ref.Ref<Words.Source> <- Ref.new(Words.Source, Words.Pending{Path.join(assetsRoot, "packages/runtime/data")})
    +stop : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +render : Callback.Callback<Nat, List<&2, String>> <- Callback.create(~Paint, ~Nat, ~List<&2, String>, ~draw, Paint{view, theme, cwd, agentDir})
    +input : Callback.Callback<String, Unit> <- Callback.create(~Input, ~String, ~Unit, ~received, Input{view, words, stop, bindings, cwd, agentDir})
    +invalidate : Callback.Callback<Unit, Unit> <- Callback.create(~Unit, ~Unit, ~Unit, ~ignore, Unit{})
    +focus : Callback.Callback<Bool, Unit> <- Callback.create(~Unit, ~Bool, ~Unit, ~unfocused, Unit{})
    +component : Component.Component <- IO.pure(Component.Component, Component.Component{Component.ComponentId{1n}, render, Some{input}, None{}, invalidate, Some{focus}, False{}})
    return Owner{view, words, stop, component, render, input, invalidate, focus}

def terminalError(error: Terminal.Error) -> String:
  match error:
    case Terminal.System{operation, _, message}: "Terminal " ++ operation ++ ": " ++ message
    case _: "Cannot start config selector terminal"

def result(outcome: Result<&2, &2, Terminal.Error, Process.Active>) -> Result<&2, &2, String, Unit>:
  match outcome:
    case Fail{error}: Fail{terminalError(error)}
    case Done{_}: Done{Unit{}}

def finish(owner: Owner, outcome: Result<&2, &2, Terminal.Error, Process.Active>) -> IO(Result<&2, &2, String, Unit>):
  match owner:
    case Owner{view, words, stop, _, render, input, invalidate, focus}:
      do IO<Result<&2, &2, String, Unit>>:
        final : View <- Ref.dispose(View, view)
        source : Words.Source <- Ref.dispose(Words.Source, words)
        Callback.dispose(Nat, List<&2, String>, render)
        Callback.dispose(String, Unit, input)
        Callback.dispose(Unit, Unit, invalidate)
        Callback.dispose(Bool, Unit, focus)
        Deferred.dispose(Unit, stop)
        return result(outcome)

def resizedView(view: View, size: Terminal.Dimensions) -> View & Unit:
  match view size:
    case View{state, manager, query, error} Terminal.Dimensions{_, rows}:
      (View{Config.withHeight(state, U32.to_nat(rows)), manager, query, error}, Unit{})

def configureTerminal(view: View, +preferences: Callback.Callback<Process.TerminalPreference, Unit>) -> IO(Unit):
  match view:
    case View{_, +manager, _, _}:
      do IO<Unit>:
        Callback.call(Process.TerminalPreference, Unit, preferences, Process.HardwareCursor{Maybe.default(&2, Bool, Settings.selectedShowHardwareCursor(Settings.get(Settings.effective(manager), "showHardwareCursor")), False{})})
        Callback.call(Process.TerminalPreference, Unit, preferences, Process.ClearOnShrink{Settings.resolvedClearOnShrink(Settings.terminalOptions(manager), False{})})

def terminalReadyShared(+view: Ref.Ref<View>, ready: Process.QueryReady) -> IO(Unit):
  match ready:
    case Process.QueryReady{_, terminal, _, request, +preferences,_}:
      do IO<Unit>:
        size : Terminal.Dimensions <- Terminal.getDimensions(terminal)
        Ref.modify(View, Unit, view, current => resizedView(current, size))
        current : View <- Ref.read(View, view)
        configureTerminal(current, preferences)
        Callback.call(Unit, Unit, request, Unit{})

def terminalReady(view: Ref.Ref<View>, ready: Process.QueryReady) -> IO(Unit): terminalReadyShared(view, ready)

def mounted(owner: Owner, base: Tui.ResultOf(Tui.TuiBase)) -> IO(Result<&2, &2, String, Unit>):
  match owner base:
    case owner Fail{_}: finish(owner, Fail{Terminal.Closed{}})
    case Owner{+view, words, +stop, +component, render, input, invalidate, focus} Done{tui}:
      do IO<Result<&2, &2, String, Unit>>:
        process : Serial.Owner<Process.Active> <- Serial.create(Process.Active, Process.active(Process.Session{tui, Process.Main{Screen.initial()}}, [component], [Component.ComponentId{1n}]))
        +ready : Callback.Callback<Process.QueryReady, Unit> <- Callback.create(~Ref.Ref<View>, ~Process.QueryReady, ~Unit, ~terminalReady, view)
        outcome : Result<&2, &2, Terminal.Error, Process.Active> <- Process.runOwner(Serial.borrow(Process.Active, process), stop, False{}, Some{ready}, None{}, Process.beforeStop)
        Callback.dispose(Process.QueryReady, Unit, ready)
        finish(Owner{view, words, stop, component, render, input, invalidate, focus}, outcome)

def runOwner(owner: Owner) -> IO(Result<&2, &2, String, Unit>):
  match owner:
    case Owner{view, words, stop, +component, render, input, invalidate, focus}:
      do IO<Result<&2, &2, String, Unit>>:
        base : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(), component), [component], [Component.ComponentId{1n}], Some{Component.ComponentId{1n}})
        mounted(Owner{view, words, stop, component, render, input, invalidate, focus}, base)

type Options is Data:
  Options{local: Bool, trustOverride: Maybe<&2, Bool>}

def optionStep(arg: String, options: Options) -> Result<&2, &2, String, Options>:
  match arg options:
    case "-l" Options{_, trust}: Done{Options{True{}, trust}}
    case "--local" Options{_, trust}: Done{Options{True{}, trust}}
    case "-a" Options{local, _}: Done{Options{local, Some{True{}}}}
    case "--approve" Options{local, _}: Done{Options{local, Some{True{}}}}
    case "-na" Options{local, _}: Done{Options{local, Some{False{}}}}
    case "--no-approve" Options{local, _}: Done{Options{local, Some{False{}}}}
    case +value Options{_, _}: Fail{Bool.pick(String, String.starts_with(value, "-"), "Unknown option " ++ value ++ " for config", "Unexpected argument " ++ value)}

def parse(values: List<&2, String>, options: Options) -> Result<&2, &2, String, Options>:
  match values:
    case Nil{}: Done{options}
    case arg <> rest: Result.bind(&2, &2, String, Options, Options, optionStep(arg, options), next => parse(rest, next))

def help() -> IO(Unit):
  IO.print("Usage:\n  pi config [-l] [--approve|--no-approve]\n\nOpen the resource configuration TUI to enable or disable package resources.\nWithout -l, starts in global settings (~/.pi/agent/settings.json).\nPress Tab in the TUI to switch between global and project-local modes.\n\nOptions:\n  -l, --local       Edit project overrides (.pi/settings.json)\n  -a, --approve     Trust project-local files for this command with -l\n  -na, --no-approve Ignore project-local files for this command with -l")

def envText(value: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match value:
    case Done{text}: Some{text}
    case Fail{_}: None{}

def terminalHeight(value: Result<&1, &1, U32 & String, String>) -> Nat:
  Maybe.default(&2, Nat, Maybe.bind(&2, String, Nat, envText(value), Nat.read), 24n)

def terminalName(theme: Detection.TerminalTheme) -> String:
  match theme:
    case Detection.Dark{}: "dark"
    case Detection.Light{}: "light"

def themeName(setting: Maybe<&2, String>, background: Maybe<&2, String>) -> String:
  +detected = Detection.detectionTheme(Detection.detectTerminalBackgroundFromEnv(background))
  Maybe.default(&2, String, Detection.resolveThemeSetting(setting, detected), terminalName(detected))

def trueColorOverride(capabilities: Settings.TerminalCapabilities) -> Maybe<&2, Bool>:
  match capabilities:
    case Settings.TerminalCapabilities{_, color, _}: color

def reported(outcome: Result<&2, &2, String, Unit>) -> IO(Unit):
  match outcome:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{error}: IO.die(Unit, 1, error)

def selected(global: Package.ResolvedPaths, project: Package.ResolvedPaths, +settings: Settings.SettingsManager, options: Options, cwd: String, home: String, +agentDir: String, assetsRoot: String, theme: Theme.Theme, bindings: Bindings.KeybindingsManager, height: Nat) -> IO(Unit):
  match options:
    case Options{local, _}:
      +available = Settings.isProjectTrusted(settings)
      +scope = Bool.pick(Config.WriteScope, local, Config.Project{}, Config.Global{})
      do IO<Unit>:
        owner : Owner <- new(Config.initial(global, project, agentDir, home, available, scope, height), settings, theme, bindings, cwd, agentDir, assetsRoot)
        outcome : Result<&2, &2, String, Unit> <- runOwner(owner)
        reported(outcome)

def loadedUi(global: Package.ResolvedPaths, project: Package.ResolvedPaths, settings: Settings.SettingsManager, options: Options, cwd: String, home: String, agentDir: String, assetsRoot: String, bindings: Bindings.KeybindingsManager, theme: Result<&2, &2, Theme.LoadError, Theme.Theme>, height: Nat) -> IO(Unit):
  match theme:
    case Done{ready}:
      selected(global, project, settings, options, cwd, home, agentDir, assetsRoot, ready, bindings, height)
    case Fail{_}: IO.die(Unit, 1, "Could not initialize config selector theme")

def startUi(global: Package.ResolvedPaths, project: Package.ResolvedPaths, +settings: Settings.SettingsManager, options: Options, cwd: String, home: String, +agentDir: String, +assetsRoot: String) -> IO(Unit):
  do IO<Unit>:
    # Upstream config runs before the app loads keybindings.json.
    bindings : Bindings.KeybindingsManager = Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux", None{}, None{}}), Record.new(List<&2, Keys.KeyId>))
    background : Result<&1, &1, U32 & String, String> <- IO.get_env("COLORFGBG")
    homeEnv : Result<&1, &1, U32 & String, String> <- IO.get_env("HOME")
    rows : Result<&1, &1, U32 & String, String> <- IO.get_env("LINES")
    environment : Image.Environment <- Image.processEnvironment("linux", Maybe.default(&2, String, envText(homeEnv), ""))
    mode : Color.Mode <- IO.pure(Color.Mode, Color.modeFor(Image.trueColor(environment, trueColorOverride(Settings.getTerminalCapabilityOverrides(settings)))))
    theme : Result<&2, &2, Theme.LoadError, Theme.Theme> <- Theme.loadByName(themeName(Settings.getThemeSetting(settings), envText(background)), Path.join(assetsRoot, "packages/coding-agent/src/modes/interactive/theme"), Path.join(agentDir, "themes"), mode)
    loadedUi(global, project, settings, options, cwd, home, agentDir, assetsRoot, bindings, theme, terminalHeight(rows))

def resolvedProject(global: Package.ResolvedPaths, settings: Settings.SettingsManager, environment: Paths.Environment, cwd: String, agentDir: String, trusted: Bool) -> IO(Package.ResolvedPaths):
  Bool.pick(Unit -> IO(Package.ResolvedPaths), trusted,
    _ => Package.resolve(environment, settings, cwd, agentDir),
    _ => IO.pure(Package.ResolvedPaths, global))(Unit{})

def loadedSettings(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def preparedTrusted(options: Options, environment: Paths.Environment, +agentDir: String, assetsRoot: String, +trusted: Bool) -> IO(Unit):
  match environment:
    case Paths.Environment{+cwd, +home, +url}:
      do IO<Unit>:
        loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.SettingsManagerCreateOptions{trusted})
        +settings : Settings.SettingsManager <- IO.pure(Settings.SettingsManager, loadedSettings(loaded))
        globalLoaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.SettingsManagerCreateOptions{False{}})
        +global : Package.ResolvedPaths <- Package.resolve(Paths.Environment{cwd, home, url}, loadedSettings(globalLoaded), cwd, agentDir)
        project : Package.ResolvedPaths <- resolvedProject(global, settings, Paths.Environment{cwd, home, url}, cwd, agentDir, trusted)
        startUi(global, project, settings, options, cwd, home, agentDir, assetsRoot)

def prepared(options: Options, environment: Paths.Environment, agentDir: String, assetsRoot: String, +trusted: Bool) -> IO(Unit):
  match options environment:
    case Options{True{}, _} _:
      Bool.pick(Unit -> IO(Unit), trusted, _ => preparedTrusted(options, environment, agentDir, assetsRoot, trusted), _ => IO.die(Unit, 1, "Project is not trusted. Use --approve to modify local resource config."))(Unit{})
    case _ _: preparedTrusted(options, environment, agentDir, assetsRoot, trusted)

def decided(options: Options, environment: Paths.Environment, agentDir: String, assetsRoot: String, decision: Result<&2, &2, String, Bool>) -> IO(Unit):
  match decision:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{trusted}: prepared(options, environment, agentDir, assetsRoot, trusted)

def withOptions(+options: Options, environment: Paths.Environment, +agentDir: String, assetsRoot: String) -> IO(Unit):
  match options environment:
    case Options{_, override} Paths.Environment{+cwd, +home, +url}:
      do IO<Unit>:
        initial : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.SettingsManagerCreateOptions{False{}})
        decision : Result<&2, &2, String, Bool> <- ProjectTrust.resolveProjectTrusted(ProjectTrust.ResolveProjectTrustedOptions{cwd, Some{home}, Trust.create(agentDir), override, Settings.getDefaultProjectTrust(loadedSettings(initial))}, None{})
        decided(options, Paths.Environment{cwd, home, url}, agentDir, assetsRoot, decision)

def parsed(request: Result<&2, &2, String, Options>, environment: Paths.Environment, agentDir: String, assetsRoot: String) -> IO(Unit):
  match request:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{options}: withOptions(options, environment, agentDir, assetsRoot)

def requestsHelp(values: List<&2, String>) -> Bool:
  match values:
    case Nil{}: False{}
    case "-h" <> _: True{}
    case "--help" <> _: True{}
    case _ <> rest: requestsHelp(rest)

def run(values: List<&2, String>, environment: Paths.Environment, agentDir: String, assetsRoot: String) -> IO(Unit):
  match values:
    case "config" <> +rest:
      Bool.pick(Unit -> IO(Unit), requestsHelp(rest),
        _ => help(), _ => parsed(parse(rest, Options{False{}, None{}}), environment, agentDir, assetsRoot))(Unit{})
    case _: IO.die(Unit, 1, "Usage: pi config [-l] [--approve|--no-approve]")
