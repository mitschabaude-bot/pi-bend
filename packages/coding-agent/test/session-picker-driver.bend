import Base
import ../src/cli/session-picker.bend as Picker

# PTY fixture entry point: exercise the selector without starting an agent.
def report(result: Picker.Outcome()) -> IO(Unit):
  match result:
    case Fail{message}: IO.print_err("PICKER ERROR: " ++ message)
    case Done{None{}}: IO.print("PICKER CANCEL")
    case Done{Some{path}}: IO.print("PICKER SELECT " ++ path)

def envOr(value: Result<&1,&1,U32 & String,String>,fallback: String) -> String:
  match value:
    case Done{found}: found
    case Fail{_}: fallback

# The picker's look comes from the installed assets (themes, collation data):
# PI_BEND_PACKAGE_DIR names the package root, as for the CLI; the default
# theme and terminal color detection apply.
def start(args: List<&2,String>) -> IO(Unit):
  match args:
    case cwd <> +agentDir <> sessionsDir <> _:
      do IO<Unit>:
        assets : Result<&1,&1,U32 & String,String> <- IO.get_env("PI_BEND_PACKAGE_DIR")
        home : Result<&1,&1,U32 & String,String> <- IO.get_env("HOME")
        result : Picker.Outcome() <- Picker.selectSession(cwd,None{},agentDir,sessionsDir,Picker.Visual{None{},envOr(assets,"."),agentDir,envOr(home,""),None{}})
        report(result)
    case _: IO.die(Unit,1,"Expected cwd, agent directory and sessions directory")

def shared(values: List<&1,String>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: value <> shared(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(shared(args))
