import Base
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/posix-path.bend as Path
import ../packages/coding-agent/src/core/settings-diagnostics.bend as Diagnostics
import ../packages/coding-agent/src/core/settings-manager.bend as Settings

# upstream test/settings-diagnostics.test.ts. Adaptations: the diagnostic's
# `type` is `kind`; storage is the SettingsStorage function upstream's
# `withLock` object stands for; the file-backed case uses the directory the
# check script passes.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def D() -> Data: Diagnostics.AgentSessionRuntimeDiagnostic

def isWarning(kind: Diagnostics.DiagnosticType) -> Bool: String.eq(Diagnostics.typeName(kind), "warning")

def diagnosticsOf(pair: Settings.SettingsManager & List<&2, D()>) -> List<&2, D()>:
  match pair:
    case (_, diagnostics): diagnostics

def managerOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def fileBacked(diagnostics: List<&2, D()>, +settingsPath: String) -> Bool:
  match diagnostics:
    case [Diagnostics.AgentSessionRuntimeDiagnostic{kind, message}]: isWarning(kind) && String.contains(message, "Invalid settings file " ++ settingsPath ++ ":")
    case _: False{}

def includesPath(+tempDir: String) -> IO(Unit):
  do IO<Unit>:
    +agentDir : String <- IO.pure(String, Path.join(tempDir, "agent"))
    +settingsPath : String <- IO.pure(String, Path.join(agentDir, "settings.json"))
    made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(agentDir)
    written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(settingsPath, "{")
    loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(tempDir, agentDir, Settings.options())
    check(fileBacked(diagnosticsOf(Diagnostics.collectSettingsDiagnostics(managerOf(loaded))), settingsPath), "includes the settings file path for file-backed storage")

def updatedSettings(update: Settings.StorageUpdate) -> Settings.Settings:
  match update:
    case Settings.StorageUpdate{settings, _}: settings

# Global storage fails; project storage has no settings.
def failingWithLock(storage: Unit, scope: Settings.SettingsScope, writable: Bool, transaction: Maybe<&2, String> -> Settings.Outcome(Settings.StorageUpdate)) -> IO(Unit & Settings.Outcome(Settings.Settings)):
  match scope:
    case Settings.Global{}: IO.pure(Unit & Settings.Outcome(Settings.Settings), (Unit{}, Fail{Settings.StorageFailure{"backend failed"}}))
    case Settings.Project{}: IO.pure(Unit & Settings.Outcome(Settings.Settings), (Unit{}, Result.map(&2, &2, Settings.Error, Settings.StorageUpdate, Settings.Settings, update => updatedSettings(update), transaction(None{}))))

def storageManager(pair: Unit & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def scopeFallback(diagnostics: List<&2, D()>) -> Bool:
  match diagnostics:
    case [Diagnostics.AgentSessionRuntimeDiagnostic{kind, message}]: isWarning(kind) && String.eq(message, "Invalid global settings: backend failed")
    case _: False{}

def fallsBackToScope() -> IO(Unit):
  do IO<Unit>:
    loaded : Unit & Settings.SettingsManager <- Settings.fromStorage(~Unit, ~failingWithLock, Unit{}, Settings.options())
    check(scopeFallback(diagnosticsOf(Diagnostics.collectSettingsDiagnostics(storageManager(loaded)))), "falls back to the settings scope for storage without file paths")

def shown(diagnostics: List<&2, D()>) -> List<&2, String>:
  match diagnostics:
    case Nil{}: Nil{}
    case Diagnostics.AgentSessionRuntimeDiagnostic{kind, message} <> rest: (Diagnostics.typeName(kind) ++ ":" ++ message) <> shown(rest)

def deduplicates() -> IO(Unit):
  do IO<Unit>:
    +warning : D() <- IO.pure(D(), Diagnostics.AgentSessionRuntimeDiagnostic{Diagnostics.Warning{}, "Invalid settings file /tmp/settings.json"})
    +error : D() <- IO.pure(D(), Diagnostics.AgentSessionRuntimeDiagnostic{Diagnostics.Error{}, "Invalid settings file /tmp/settings.json"})
    check(String.eq(String.join(shown(Diagnostics.deduplicateDiagnostics([warning, warning, error])), "|"), "warning:Invalid settings file /tmp/settings.json|error:Invalid settings file /tmp/settings.json"), "deduplicates diagnostics by type and message")

def run(args: List<String>) -> IO(Unit):
  match args:
    case tempDir <> Nil{}:
      do IO<Unit>:
        includesPath(tempDir)
        fallsBackToScope()
        deduplicates()
    case _: IO.die(Unit, 1, "usage: settings-diagnostics <empty temporary directory>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
