import Base
import ../packages/coding-agent/src/core/agent-runtime.bend as Runtime
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/coding-agent/src/core/settings-manager.bend as Settings
import ../packages/runtime/src/record.bend as Record
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/tools/read.bend as Read
import ../packages/coding-agent/src/core/tools/bash.bend as Bash

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

def shown(value: Maybe<&2,String>) -> String: Maybe.default(&2,String,value,"unset")
def shownBool(value: Maybe<&2,Bool>) -> String:
  match value:
    case Some{True{}}: "true"
    case Some{False{}}: "false"
    case None{}: "unset"

def readShown(read: Maybe<&2,Read.ReadToolOptions>) -> String:
  match read:
    case Some{Read.ReadToolOptions{resize,_,_,_}}: "read.autoResizeImages=" ++ shownBool(resize)
    case None{}: "read=unset"

def bashShown(bash: Maybe<&2,Bash.BashToolOptions>) -> String:
  match bash:
    case Some{Bash.BashToolOptions{_,prefix,shell,expose,_}}: "bash.commandPrefix=" ++ shown(prefix) ++ " bash.shellPath=" ++ shown(shell) ++ " bash.exposeSessionEnvironment=" ++ shownBool(expose)
    case None{}: "bash=unset"

# The options the runtime creates its built-in tools with.
def optionsShown(options: Tools.ToolsOptions) -> String:
  match options:
    case Tools.ToolsOptions{read,bash,_,_,_,_,_}: readShown(read) ++ " " ++ bashShown(bash)

def callerBuiltins() -> Tools.ToolsOptions:
  Tools.ToolsOptions{None{},Some{Bash.BashToolOptions{None{},Some{"caller prefix"},None{},Some{False{}},None{}}},None{},None{},None{},None{},None{}}

def configured(value: Settings.Outcome(Settings.SettingsManager)) -> IO(Settings.SettingsManager):
  match value:
    case Done{manager}: IO.pure(Settings.SettingsManager,manager)
    case Fail{_}: IO.die(Settings.SettingsManager,1,"settings update failed")

def bashPrompt(+paths: Paths.Environment,+cwd: String,+agentDir: String,+settings: Settings.SettingsManager,builtins: Maybe<&2,Tools.ToolsOptions>) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,String,Record.Record<String>> <- Runtime.systemPromptFor(paths,Runtime.CreateOptions{cwd,agentDir,"","","/pi",None{},None{},None{},None{},None{},Nil{},Runtime.ToolSelection{Some{["bash"]},None{},None{},builtins},False{},Runtime.emptySeed(),settings,Runtime.ResourceOptions{Nil{},True{},Nil{},False{}}},"/pi")
    IO.print("--- prompt")
    rendered(result)

# Caller-supplied built-in options win; settings fill what the caller leaves
# unset (upstream _buildRuntime's read autoResizeImages and bash
# commandPrefix/shellPath), and the prompt guidelines follow the options.
def toolOptions(+cwd: String,+agentDir: String) -> IO(Unit):
  do IO<Unit>:
    pair : Settings.InMemorySettingsStorage & Settings.SettingsManager <- Settings.inMemory(Settings.empty(),Settings.options())
    shelled : Settings.SettingsManager <- configured(Settings.setShellPath(Some{"~/bin/settings-shell"},managerOf(pair)))
    prefixed : Settings.SettingsManager <- configured(Settings.setShellCommandPrefix(Some{"settings prefix"},shelled))
    +settings : Settings.SettingsManager <- configured(Settings.setImageAutoResize(False{},prefixed))
    +paths : Paths.Environment = Paths.Environment{cwd,agentDir,Runtime.urlContext()}
    IO.print("defaults: " ++ optionsShown(Runtime.toolsOptionsFor(Tools.defaultOptions(),settings,paths)))
    IO.print("caller: " ++ optionsShown(Runtime.toolsOptionsFor(callerBuiltins(),settings,paths)))
    bashPrompt(paths,cwd,agentDir,settings,None{})
    bashPrompt(paths,cwd,agentDir,settings,Some{callerBuiltins()})

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case _ <> +cwd <> +agentDir <> Nil{}: toolOptions(cwd,agentDir)
    case +cwd <> +agentDir <> enabled <> skills <> Nil{}:
      do IO<Unit>:
        pair : Settings.InMemorySettingsStorage & Settings.SettingsManager <- Settings.inMemory(Settings.empty(),Settings.options())
        result : Result<&2,&2,String,Record.Record<String>> <- Runtime.systemPromptFor(Paths.Environment{cwd,agentDir,Runtime.urlContext()},Runtime.CreateOptions{cwd,agentDir,"","","/pi",None{},None{},None{},None{},Some{"fixture system prompt"},Nil{},Runtime.ToolSelection{Some{["read"]},None{},None{},None{}},String.eq(enabled,"on"),Runtime.emptySeed(),managerOf(pair),Runtime.ResourceOptions{Nil{},String.eq(skills,"off"),Nil{},False{}}},"/pi")
        rendered(result)
    case _: IO.die(Unit,1,"expected cwd, agentDir, on/off, skills on/off")

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
