import Base
import ../packages/coding-agent/src/config.bend as Config
import ../packages/coding-agent/src/core/package-manager.bend as PackageManager
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties

# Match the CLI's URL defaults without importing its provider and agent stack.
def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def enabled(resources: List<&2, PackageManager.ResolvedResource>) -> List<&2, String>:
  match resources:
    case Nil{}: Nil{}
    case PackageManager.ResolvedResource{path, selected, _} <> rest:
      match selected:
        case True{}: Json.quote(path) <> enabled(rest)
        case False{}: enabled(rest)

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def printSources(found: PackageManager.ResolvedPaths) -> IO(Unit):
  match found:
    case PackageManager.ResolvedPaths{extensions, _, _, _}: IO.print("[" ++ String.join(enabled(extensions), ",") ++ "]")

def run(cwd: Result<&2, &2, FS.Error, String>, agentDir: Config.Located(), environment: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Unit):
  match cwd agentDir environment:
    case Done{+directory} Done{+agent} Done{paths}:
      do IO<Unit>:
        loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(directory, agent, Settings.options())
        found : PackageManager.ResolvedPaths <- PackageManager.resolve(paths, settingsOf(loaded), directory, agent)
        printSources(found)
    case _ _ _: IO.die(Unit, 1, "Could not resolve extension sources")

def main() -> IO(Unit):
  do IO<Unit>:
    cwd : Result<&2, &2, FS.Error, String> <- FS.cwd()
    agentDir : Config.Located() <- Config.getAgentDir()
    environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(urlContext())
    run(cwd, agentDir, environment)
