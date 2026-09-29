import Base
import ../packages/coding-agent/src/cli/package-command.bend as PackageCommand
import ../packages/coding-agent/src/config.bend as Config
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/runtime/src/filesystem.bend as FS

def shared(values: List<&1, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: value <> shared(rest)

def ready(args: List<String>, environment: Result<&2, &2, FS.Error, Paths.Environment>, directory: Config.Located()) -> IO(Unit):
  match environment directory:
    case Done{environment} Done{agentDir}: PackageCommand.run(shared(args), environment, agentDir)
    case _ _: IO.die(Unit, 1, "Could not resolve package directories")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Runtime.urlContext())
    directory : Config.Located() <- Config.getAgentDir()
    ready(args, environment, directory)
