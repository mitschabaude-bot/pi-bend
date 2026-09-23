import Base
import ../src/cli/session-picker.bend as Picker

# PTY fixture entry point: exercise the selector without starting an agent.
def report(result: Picker.Outcome()) -> IO(Unit):
  match result:
    case Fail{message}: IO.print_err("PICKER ERROR: " ++ message)
    case Done{None{}}: IO.print("PICKER CANCEL")
    case Done{Some{path}}: IO.print("PICKER SELECT " ++ path)

def start(args: List<&2,String>) -> IO(Unit):
  match args:
    case cwd <> agentDir <> sessionsDir <> _:
      do IO<Unit>:
        result : Picker.Outcome() <- Picker.selectSession(cwd,None{},agentDir,sessionsDir)
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
