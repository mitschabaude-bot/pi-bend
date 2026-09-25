import Base
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/runtime/src/record.bend as Record
import ../packages/coding-agent/src/core/tools/index.bend as Tools

def contents(fields: List<&2,Record.Property<String>>) -> List<&2,String>:
  match fields:
    case Nil{}: Nil{}
    case Record.Property{_,content} <> rest: content <> contents(rest)

# The prompt sections in declaration order.
def rendered(value: Result<&2,&2,String,Record.Record<String>>) -> IO(Unit):
  match value:
    case Done{sections}: IO.print(String.join(contents(Record.entries(String,sections)),"\n\n"))
    case Fail{message}: IO.die(Unit,1,message)

def managerOf(pair: Settings.InMemorySettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case Tuple{_, manager}: manager

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case +cwd <> +agentDir <> enabled <> skills <> Nil{}:
      do IO<Unit>:
        pair : Settings.InMemorySettingsStorage & Settings.SettingsManager <- Settings.inMemory(Settings.empty(),Settings.options())
        result : Result<&2,&2,String,Record.Record<String>> <- Runtime.systemPromptFor(Paths.Environment{cwd,agentDir,Runtime.urlContext()},Runtime.CreateOptions{cwd,agentDir,"","","/pi",None{},None{},None{},None{},Some{"fixture system prompt"},Nil{},Runtime.ToolSelection{Some{["read"]},None{},None{}},String.eq(enabled,"on"),Runtime.emptySeed(),managerOf(pair),Runtime.ResourceOptions{Nil{},String.eq(skills,"off"),Nil{},False{}}},"/pi")
        rendered(result)
    case _: IO.die(Unit,1,"expected cwd, agentDir, on/off, skills on/off")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
