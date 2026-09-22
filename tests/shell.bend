import Base
import ../packages/coding-agent/src/utils/shell.bend as Shell
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as Wire
import ./tool-truncate.bend as Text

def environment(parts: List<&2,String>) -> List<String>:
  match parts:
    case Nil{}: Nil{}
    case value <> rest: Text.text(value) <> environment(rest)

def shownEntries(entries: List<String>, reversed: List<&2,String>) -> String:
  match entries:
    case Nil{}: String.join(List.reverse(&2,String,reversed),";")
    case value <> rest: shownEntries(rest,Wire.showText(value) <> reversed)

def envResult(value: Result<&2,&2,Shell.Error,Shell.Environment()>) -> String:
  match value:
    case Done{entries}: shownEntries(Shell.toEntries(entries),Nil{})
    case Fail{Shell.InvalidEnvironment{_}}: "invalid"
    case Fail{Shell.DuplicateVariable{_}}: "duplicate"
    case Fail{_}: "error"

def shellEnv(bin: String, value: Result<&2,&2,Shell.Error,Shell.Environment()>) -> String:
  match value:
    case Fail{cause}: envResult(Fail{cause})
    case Done{entries}: envResult(Done{Shell.getShellEnv(bin,entries)})

def transport(value: Maybe<&2,Shell.CommandTransport>) -> String:
  match value:
    case None{}: "none"
    case Some{Shell.Argv{}}: "argv"
    case Some{Shell.Stdin{}}: "stdin"

def shownArgs(args: List<&2,String>) -> List<&2,String>:
  match args:
    case Nil{}: Nil{}
    case value <> rest: Wire.showText(value) <> shownArgs(rest)

def config(value: Result<&2,&2,Shell.Error,Shell.ShellConfig>) -> String:
  match value:
    case Fail{Shell.CustomShellNotFound{path}}: "missing|" ++ Wire.showText(path)
    case Fail{_}: "error"
    case Done{Shell.ShellConfig{shell,args,mode}}: Wire.showText(shell) ++ "|" ++ String.join(shownArgs(args),";") ++ "|" ++ transport(mode)

def option(value: String) -> Maybe<&2,String>:
  match value:
    case "-": None{}
    case value: Some{Text.text(value)}

def search(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "none"
    case Some{path}: Wire.showText(path)

def envParts(text: String) -> List<String>:
  match text:
    case "": Nil{}
    case value: environment(Strings.split(value,';'))

def run(parts: List<&2,String>) -> IO(Unit):
  match parts:
    case "s" <> text <> Nil{}: IO.print(Wire.showText(Shell.sanitizeBinaryOutput(Text.text(text))))
    case "e" <> bin <> entries <> Nil{}: IO.print(shellEnv(Text.text(bin),Shell.fromEntries(envParts(entries))))
    case "r" <> entries <> Nil{}: IO.print(envResult(Shell.fromEntries(envParts(entries))))
    case "l" <> bin <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,Shell.Error,Shell.Environment()> <- Shell.loadShellEnv(Text.text(bin))
        IO.print(envResult(result))
    case "n" <> custom <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,Shell.Error,Shell.ShellConfig> <- Shell.getShellConfig(option(custom))
        IO.print(config(result))
    case "c" <> custom <> default <> paths <> Nil{}:
      do IO<Unit>:
        result : Result<&2,&2,Shell.Error,Shell.ShellConfig> <- Shell.getShellConfigWith(option(custom),Text.text(default),Strings.split(Text.text(paths),':'))
        IO.print(config(result))
    case "f" <> name <> paths <> Nil{}:
      do IO<Unit>:
        result : Maybe<&2,String> <- Shell.findExecutableOnPath(Text.text(name),Strings.split(Text.text(paths),':'),None{})
        IO.print(search(result))
    case _: IO.print("invalid-command")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        run(Strings.split(value,':'))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
