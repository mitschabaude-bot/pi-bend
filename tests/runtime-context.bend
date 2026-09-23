import Base
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/core/settings-manager.bend as Settings

def rendered(value: Result<&2,&2,String,String>) -> IO(Unit):
  match value:
    case Done{text}: IO.print(text)
    case Fail{message}: IO.die(Unit,1,message)

def managerOf(pair: Settings.InMemorySettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case Tuple{_, manager}: manager

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case +cwd <> +agentDir <> enabled <> Nil{}:
      do IO<Unit>:
        pair : Settings.InMemorySettingsStorage & Settings.SettingsManager <- Settings.inMemory(Settings.empty(),Settings.options())
        result : Result<&2,&2,String,String> <- Runtime.systemPromptFor(Paths.Environment{cwd,agentDir,Runtime.urlContext()},Runtime.CreateOptions{cwd,agentDir,"","","/pi",None{},None{},None{},None{},Some{"fixture system prompt"},Nil{},Nil{},String.eq(enabled,"on"),Runtime.emptySeed(),managerOf(pair)},"/pi")
        rendered(result)
    case _: IO.die(Unit,1,"expected cwd, agentDir, on/off")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
