import Base
import ../packages/coding-agent/src/core/package-manager.bend as Package
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/utils/git.bend as Git
import ../packages/runtime/src/filesystem.bend as FS

# The caller owns a local Git remote and an isolated agent directory. This
# exercises the same managed path and update operation as configured sources.
def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def reported(result: Package.PackageResult()) -> IO(Unit):
  match result:
    case Done{_}: IO.print("updated")
    case Fail{message}: IO.die(Unit, 1, message)

def withEnvironment(+cwd: String, +agentDir: String, repo: String, +ref: Maybe<&2, String>, loaded: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Unit):
  match loaded:
    case Fail{_}: IO.die(Unit, 1, "no environment")
    case Done{environment}:
      do IO<Unit>:
        settings : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.options())
        source : Git.GitSource = Git.GitSource{repo, "github.com", "test/extension", ref, Maybe.is_some(&2, String, ref)}
        result : Package.PackageResult() <- Package.updateGit(Package.contextOf(environment, settingsOf(settings), cwd, agentDir), source, Package.UserSource{})
        reported(result)

def run(args: List<String>) -> IO(Unit):
  match args:
    case cwd <> agentDir <> repo <> +ref <> Nil{}:
      do IO<Unit>:
        environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Runtime.urlContext())
        withEnvironment(cwd, agentDir, repo, Bool.pick(Maybe<&2, String>, String.eq(ref, "-"), None{}, Some{ref}), environment)
    case _: IO.die(Unit, 1, "usage: package-git-update <cwd> <agentDir> <repo> <ref|->")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
