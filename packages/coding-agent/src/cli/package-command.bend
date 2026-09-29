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

def parsed(values: List<&2, String>) -> Result<&2, &2, String, Request>:
  match values:
    case "install" <> source <> Nil{}: Done{Install{source, False{}}}
    case "install" <> source <> "-l" <> Nil{}: Done{Install{source, True{}}}
    case "install" <> source <> "--local" <> Nil{}: Done{Install{source, True{}}}
    case "remove" <> source <> Nil{}: Done{Remove{source, False{}}}
    case "remove" <> source <> "-l" <> Nil{}: Done{Remove{source, True{}}}
    case "remove" <> source <> "--local" <> Nil{}: Done{Remove{source, True{}}}
    case "uninstall" <> source <> Nil{}: Done{Remove{source, False{}}}
    case "uninstall" <> source <> "-l" <> Nil{}: Done{Remove{source, True{}}}
    case "uninstall" <> source <> "--local" <> Nil{}: Done{Remove{source, True{}}}
    case "list" <> Nil{}: Done{ListPackages{}}
    case _: Fail{"Usage: pi install|remove <source> [-l], or pi list"}

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

def trustedReady(request: Request, +environment: Paths.Environment, +agentDir: String, decision: Result<&2, &2, String, Bool>) -> IO(Unit):
  match decision environment:
    case Fail{message} _: IO.die(Unit, 1, message)
    case Done{trusted} Paths.Environment{+cwd, _, _}:
      do IO<Unit>:
        loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.SettingsManagerCreateOptions{trusted})
        execute(Package.contextOf(environment, settingsOf(loaded), cwd, agentDir), request)

def prepared(request: Result<&2, &2, String, Request>, environment: Paths.Environment, +agentDir: String) -> IO(Unit):
  match request environment:
    case Fail{message} _: IO.die(Unit, 1, message)
    case Done{action} Paths.Environment{+cwd, +home, +url}:
      do IO<Unit>:
        initial : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.SettingsManagerCreateOptions{False{}})
        decision : Result<&2, &2, String, Bool> <- ProjectTrust.resolveProjectTrusted(ProjectTrust.ResolveProjectTrustedOptions{cwd, Some{home}, Trust.create(agentDir), None{}, Settings.getDefaultProjectTrust(settingsOf(initial))}, None{})
        trustedReady(action, Paths.Environment{cwd, home, url}, agentDir, decision)

def run(values: List<&2, String>, environment: Paths.Environment, agentDir: String) -> IO(Unit):
  prepared(parsed(values), environment, agentDir)
