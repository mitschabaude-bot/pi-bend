import Base
import ../packages/coding-agent/src/core/package-manager.bend as PM
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/json.bend as Decode

# Prints PackageManager.resolve for <cwd> <agentDir> in the reference's JSON shape.

def sourceName(source: PM.Source) -> String:
  match source:
    case PM.Local{}: "local"
    case PM.Auto{}: "auto"

def scopeName(scope: PM.Scope) -> String:
  match scope:
    case PM.ProjectScope{}: "project"
    case PM.UserScope{}: "user"

def row(resource: PM.ResolvedResource) -> String:
  match resource:
    case PM.ResolvedResource{path, enabled, PM.PathMetadata{source, scope, baseDir}}:
      "{\"path\":" ++ Decode.quote(path) ++ ",\"enabled\":" ++ Bool.pick(String, enabled, "true", "false") ++ ",\"source\":\"" ++ sourceName(source) ++ "\",\"scope\":\"" ++ scopeName(scope) ++ "\",\"baseDir\":" ++ Maybe.default(&2, String, Maybe.map(&2, String, String, Decode.quote, baseDir), "null") ++ "}"

def rows(resources: List<&2, PM.ResolvedResource>) -> List<&2, String>:
  match resources:
    case Nil{}: Nil{}
    case resource <> rest: row(resource) <> rows(rest)

def printed(paths: PM.ResolvedPaths) -> IO(Unit):
  match paths:
    case PM.ResolvedPaths{skills, prompts, themes}:
      IO.print("{\"skills\":[" ++ String.join(rows(skills), ",") ++ "],\"prompts\":[" ++ String.join(rows(prompts), ",") ++ "],\"themes\":[" ++ String.join(rows(themes), ",") ++ "]}")

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def resolved(+cwd: String, +agentDir: String, environment: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Unit):
  match environment:
    case Fail{_}: IO.die(Unit, 1, "no environment")
    case Done{paths}:
      do IO<Unit>:
        loaded : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.options())
        found : PM.ResolvedPaths <- PM.resolve(paths, settingsOf(loaded), cwd, agentDir)
        printed(found)

def run(args: List<String>) -> IO(Unit):
  match args:
    case cwd <> agentDir <> Nil{}:
      do IO<Unit>:
        environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Runtime.urlContext())
        resolved(cwd, agentDir, environment)
    case _: IO.die(Unit, 1, "usage: package-manager <cwd> <agentDir>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
