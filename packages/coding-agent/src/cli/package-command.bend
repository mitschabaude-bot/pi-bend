import Base
import ../core/package-manager.bend as Package
import ../core/settings-manager.bend as Settings
import ../core/settings-diagnostics.bend as Diagnostics
import ../core/project-trust.bend as ProjectTrust
import ../core/trust-manager.bend as Trust
import ../utils/paths.bend as Paths
import ../../../runtime/src/filesystem.bend as FS

# Package commands are kept separate from session startup: they load and
# persist settings without creating a model or a terminal session.
type Request is Data:
  Install{source: String, local: Bool}
  Remove{source: String, local: Bool}
  ListPackages{}
  UpdatePackages{source: Maybe<&2, String>}
  SelfUpdate{}

type Command is Data:
  Command{request: Request, trustOverride: Maybe<&2, Bool>}

type CommandKind is Data:
  InstallKind{}
  RemoveKind{}
  ListKind{}
  UpdateKind{}

def commandKind(name: String) -> Maybe<&2, CommandKind>:
  match name:
    case "install": Some{InstallKind{}}
    case "remove": Some{RemoveKind{}}
    case "uninstall": Some{RemoveKind{}}
    case "list": Some{ListKind{}}
    case "update": Some{UpdateKind{}}
    case _: None{}

def finish(kind: CommandKind, source: Maybe<&2, String>, local: Bool, override: Maybe<&2, Bool>, extensions: Bool) -> Result<&2, &2, String, Command>:
  match kind source extensions:
    case ListKind{} _ True{}: Fail{"--extensions is only valid with update"}
    case InstallKind{} _ True{}: Fail{"--extensions is only valid with update"}
    case RemoveKind{} _ True{}: Fail{"--extensions is only valid with update"}
    case InstallKind{} Some{source} _: Done{Command{Install{source, local}, override}}
    case RemoveKind{} Some{source} _: Done{Command{Remove{source, local}, override}}
    case ListKind{} None{} _: Bool.pick(Result<&2, &2, String, Command>, local, Fail{"--local is not valid with list"}, Done{Command{ListPackages{}, override}})
    case UpdateKind{} None{} True{}: Bool.pick(Result<&2, &2, String, Command>, local, Fail{"--local is not valid with update"}, Done{Command{UpdatePackages{None{}}, override}})
    case UpdateKind{} Some{source} True{}: Bool.pick(Result<&2, &2, String, Command>, local, Fail{"--local is not valid with update"}, Done{Command{UpdatePackages{Some{source}}, override}})
    case UpdateKind{} None{} False{}: Bool.pick(Result<&2, &2, String, Command>, local, Fail{"--local is not valid with update"}, Done{Command{SelfUpdate{}, override}})
    case UpdateKind{} Some{"pi"} False{}: Bool.pick(Result<&2, &2, String, Command>, local, Fail{"--local is not valid with update"}, Done{Command{SelfUpdate{}, override}})
    case UpdateKind{} Some{"self"} False{}: Bool.pick(Result<&2, &2, String, Command>, local, Fail{"--local is not valid with update"}, Done{Command{SelfUpdate{}, override}})
    case UpdateKind{} Some{source} False{}: Bool.pick(Result<&2, &2, String, Command>, local, Fail{"--local is not valid with update"}, Done{Command{UpdatePackages{Some{source}}, override}})
    case _ _ _: Fail{"Invalid package command arguments"}

type ScanState is Data:
  ScanState{source: Maybe<&2, String>, local: Bool, override: Maybe<&2, Bool>, extensions: Bool}

def optionStep(arg: String, state: ScanState) -> Result<&2, &2, String, ScanState>:
  match arg state:
    case "-l" ScanState{source, _, override, extensions}: Done{ScanState{source, True{}, override, extensions}}
    case "--local" ScanState{source, _, override, extensions}: Done{ScanState{source, True{}, override, extensions}}
    case "-a" ScanState{source, local, _, extensions}: Done{ScanState{source, local, Some{True{}}, extensions}}
    case "--approve" ScanState{source, local, _, extensions}: Done{ScanState{source, local, Some{True{}}, extensions}}
    case "-na" ScanState{source, local, _, extensions}: Done{ScanState{source, local, Some{False{}}, extensions}}
    case "--no-approve" ScanState{source, local, _, extensions}: Done{ScanState{source, local, Some{False{}}, extensions}}
    case "--extensions" ScanState{source, local, override, _}: Done{ScanState{source, local, override, True{}}}
    case +value ScanState{None{}, local, override, extensions}:
      Bool.pick(Result<&2, &2, String, ScanState>, String.starts_with(value, "-"), Fail{"Unknown package option: " ++ value}, Done{ScanState{Some{value}, local, override, extensions}})
    case value ScanState{Some{_}, _, _, _}: Fail{"Unexpected package argument: " ++ value}

def extensionValue(value: String, state: ScanState) -> Result<&2, &2, String, ScanState>:
  match state:
    case ScanState{None{}, local, override, _}: Done{ScanState{Some{value}, local, override, True{}}}
    case ScanState{Some{_}, _, _, _}: Fail{"--extension can only be provided once"}

def finishState(kind: CommandKind, state: ScanState) -> Result<&2, &2, String, Command>:
  match state:
    case ScanState{source, local, override, extensions}: finish(kind, source, local, override, extensions)

def scan(+kind: CommandKind, values: List<&2, String>, state: ScanState) -> Result<&2, &2, String, Command>:
  match values:
    case Nil{}: finishState(kind, state)
    case "--extension" <> value <> rest: Result.bind(&2, &2, String, ScanState, Command, extensionValue(value, state), next => scan(kind, rest, next))
    case arg <> rest: Result.bind(&2, &2, String, ScanState, Command, optionStep(arg, state), next => scan(kind, rest, next))

def parsedKind(name: String, rest: List<&2, String>, found: Maybe<&2, CommandKind>) -> Result<&2, &2, String, Command>:
  match found:
    case Some{kind}: scan(kind, rest, ScanState{None{}, False{}, None{}, False{}})
    case None{}: Fail{"Unknown package command: " ++ name}

def parsed(values: List<&2, String>) -> Result<&2, &2, String, Command>:
  match values:
    case +name <> rest: parsedKind(name, rest, commandKind(name))
    case Nil{}: Fail{"Usage: pi install|remove|update|list"}

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def persisted(change: Bool, result: Settings.SettingsManager & List<&2, Settings.SettingsError>) -> Result<&2, &2, String, Bool>:
  match result:
    case (_, Nil{}): Done{change}
    case (_, Settings.SettingsError{_, _, cause} <> _): Fail{Diagnostics.settingsErrorText(cause)}

def changed(result: Result<&2, &2, String, Package.SettingsChange>) -> IO(Result<&2, &2, String, Bool>):
  match result:
    case Fail{message}: IO.pure(Result<&2, &2, String, Bool>, Fail{message})
    case Done{Package.SettingsChange{wasChanged, context}}:
      do IO<Result<&2, &2, String, Bool>>:
        saved : Settings.SettingsManager <- Settings.flushFiles(Package.settingsOf(context))
        return persisted(wasChanged, Settings.drainErrors(saved))

def added(+context: Package.Context, +source: String, local: Bool, outcome: Package.PackageResult()) -> IO(Result<&2, &2, String, Bool>):
  match outcome:
    case Fail{message}: IO.pure(Result<&2, &2, String, Bool>, Fail{message})
    case Done{_}: changed(Package.addSourceToSettings(context, source, local))

def removed(+context: Package.Context, +source: String, local: Bool, outcome: Package.PackageResult()) -> IO(Result<&2, &2, String, Bool>):
  match outcome:
    case Fail{message}: IO.pure(Result<&2, &2, String, Bool>, Fail{message})
    case Done{_}: changed(Package.removeSourceFromSettings(context, source, local))

def reportInstall(source: String, outcome: Result<&2, &2, String, Bool>) -> IO(Unit):
  match outcome:
    case Fail{message}: IO.die(Unit, 1, "Error: " ++ message)
    case Done{_}: IO.print("Installed " ++ source)

def reportRemove(source: String, outcome: Result<&2, &2, String, Bool>) -> IO(Unit):
  match outcome:
    case Fail{message}: IO.die(Unit, 1, "Error: " ++ message)
    case Done{True{}}: IO.print("Removed " ++ source)
    case Done{False{}}: IO.die(Unit, 1, "No matching package found for " ++ source)

def reportUpdate(source: Maybe<&2, String>, outcome: Package.PackageResult()) -> IO(Unit):
  match source outcome:
    case _ Fail{message}: IO.die(Unit, 1, "Error: " ++ message)
    case Some{requested} Done{_}: IO.print("Updated " ++ requested)
    case None{} Done{_}: IO.print("Updated packages")

def packageLines(packages: List<&2, Settings.PackageSource>) -> IO(Unit):
  match packages:
    case Nil{}: IO.pure(Unit, Unit{})
    case package <> rest:
      do IO<Unit>:
        IO.print("  " ++ Package.sourceString(package))
        packageLines(rest)

def listedEntries(users: List<&2, Settings.PackageSource>, projects: List<&2, Settings.PackageSource>) -> IO(Unit):
  match users projects:
    case Nil{} Nil{}: IO.print("No packages installed.")
    case Nil{} projects:
      do IO<Unit>:
        IO.print("Project packages:")
        packageLines(projects)

    case users Nil{}:
      do IO<Unit>:
        IO.print("User packages:")
        packageLines(users)
    case users projects:
      do IO<Unit>:
        IO.print("User packages:")
        packageLines(users)
        IO.print("")
        IO.print("Project packages:")
        packageLines(projects)

def listed(+context: Package.Context) -> IO(Unit):
  listedEntries(Package.packagesIn(Package.settingsFor(context, Package.UserSource{})), Package.packagesIn(Package.settingsFor(context, Package.ProjectSource{})))

def localAllowed(context: Package.Context, local: Bool) -> Bool:
  Bool.not(local) || Settings.isProjectTrusted(Package.settingsOf(context))

def installAllowed(+context: Package.Context, +source: String, +local: Bool, allowed: Bool) -> IO(Unit):
  match allowed:
    case False{}: IO.die(Unit, 1, "Project is not trusted. Use --approve to modify local package config.")
    case True{}:
      do IO<Unit>:
        outcome : Package.PackageResult() <- Package.install(context, source, local)
        persisted : Result<&2, &2, String, Bool> <- added(context, source, local, outcome)
        reportInstall(source, persisted)

def installCommand(+context: Package.Context, +source: String, +local: Bool) -> IO(Unit):
  installAllowed(context, source, local, localAllowed(context, local))

def removeAllowed(+context: Package.Context, +source: String, +local: Bool, allowed: Bool) -> IO(Unit):
  match allowed:
    case False{}: IO.die(Unit, 1, "Project is not trusted. Use --approve to modify local package config.")
    case True{}:
      do IO<Unit>:
        outcome : Package.PackageResult() <- Package.remove(context, source, local)
        persisted : Result<&2, &2, String, Bool> <- removed(context, source, local, outcome)
        reportRemove(source, persisted)

def removeCommand(+context: Package.Context, +source: String, +local: Bool) -> IO(Unit):
  removeAllowed(context, source, local, localAllowed(context, local))

def execute(+context: Package.Context, request: Request) -> IO(Unit):
  match request:
    case Install{source, local}: installCommand(context, source, local)
    case Remove{source, local}: removeCommand(context, source, local)
    case ListPackages{}: listed(context)
    case UpdatePackages{+source}:
      do IO<Unit>:
        result : Package.PackageResult() <- Package.updateConfigured(context, source)
        reportUpdate(source, result)
    case SelfUpdate{}: IO.die(Unit, 1, "Self-update is unavailable for a source build")

def trustedReady(request: Request, +environment: Paths.Environment, +agentDir: String, decision: Result<&2, &2, String, Bool>) -> IO(Unit):
  match decision environment:
    case Fail{message} _: IO.die(Unit, 1, message)
    case Done{trusted} Paths.Environment{+cwd, _, _}:
      do IO<Unit>:
        loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.SettingsManagerCreateOptions{trusted})
        execute(Package.contextOf(environment, settingsOf(loaded), cwd, agentDir), request)

def prepared(request: Result<&2, &2, String, Command>, environment: Paths.Environment, +agentDir: String) -> IO(Unit):
  match request environment:
    case Fail{message} _: IO.die(Unit, 1, message)
    case Done{Command{action, override}} Paths.Environment{+cwd, +home, +url}:
      do IO<Unit>:
        initial : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.SettingsManagerCreateOptions{False{}})
        decision : Result<&2, &2, String, Bool> <- ProjectTrust.resolveProjectTrusted(ProjectTrust.ResolveProjectTrustedOptions{cwd, Some{home}, Trust.create(agentDir), override, Settings.getDefaultProjectTrust(settingsOf(initial))}, None{})
        trustedReady(action, Paths.Environment{cwd, home, url}, agentDir, decision)

def run(values: List<&2, String>, environment: Paths.Environment, agentDir: String) -> IO(Unit):
  prepared(parsed(values), environment, agentDir)
